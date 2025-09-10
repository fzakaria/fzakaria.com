---
layout: post
title: 'Bazel Knowledge: Smuggling capabilities through a tarball'
date: 2025-09-09 14:25 -0700
---

> **tl;dr**: Linux capabilities are just xattrs (extended attributes) on files — and since `tar` can preserve xattrs, Bazel can “smuggle” them into OCI layers without ever running `sudo setcap`.

Every so often I stumble on a trick that makes me do a double-take. This one came up while poking around needing to replace the contents of a `Dockerfile` that set capabilities on a file, via `setcap`, and trying to replace it with [rules_oci](https://github.com/bazel-contrib/rules_oci).

> I learnt this idea from reading [bazeldnf](https://github.com/rmohr/bazeldnf).

What are capabilities? 🤔

We are all pretty familiar with _the all powerful_ `root` in Linux and escalating to `root` via `sudo`. Capabilities break that monolith into smaller, more focused privileges [[ref](https://man7.org/linux/man-pages/man7/capabilities.7.html)]. Instead of giving a process the full keys to the kingdom, you can hand it just the one it needs.

For example:

`CAP_NET_BIND_SERVICE`
: lets a process bind to ports below 1024.

`CAP_SYS_ADMIN`
: a grab-bag of scary powers (mount, pivot_root, …).

`CAP_CHOWN`
: lets a process change file ownership.

Capabilities are inherited from the spawning process but they can also be added to the file itself, such that any time that process is `exec` it has the desired capabilities. The Linux kernel stores these capabilities in the "extended attributes" (i.e. additional metadata) of the file [[ref](https://man7.org/linux/man-pages/man7/xattr.7.html)].

> If the filesystem you are using does not support extended attributes, then _you cannot_ set capabilities on a file.

Let's see an example we will work through.

```c
#include <netinet/in.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void) {
    int fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    if (fd < 0) {
        perror("socket");
        return 1;
    }
    printf("Raw socket created successfully!\n");
    close(fd);
    return 0;
}
```

If we build this with Bazel and try to run it, we will see that it fails _unless_ we either spawn it with `CAP_NET_RAW`, `sudo` or add it to the binary via `setcap`.

```bash
> bazel build //:rawsock

> bazel-bin/rawsock
socket: Operation not permitted

> sudo bazel-bin/rawsock
Raw socket created successfully!

# here we add the capability via setcap
# no longer need sudo
> cp bazel-bin/rawsock /tmp/rawsock
> sudo setcap 'cap_net_raw=+ep' /tmp/rawsock
> /tmp/rawsock
Raw socket created successfully!

# let's check the xattr
> getfattr -n security.capability /tmp/rawsock
# file: bazel-bin/rawsock
security.capability=0sAQAAAgAgAAAAAAAAAAAAAAAAAAA=
```

Okay great -- but what does this have to do with Bazel?

Well we were converting a `Dockerfile` that used `setcap` to modify the binary.

If your OCI image runs as a non-root user, it will also be unpermitted from creating the raw socket.

```Dockerfile
FROM alpine:latest
COPY bazel-bin/rawsock
USER nobody
ENTRYPOINT rawsock
```

We can build this Docker image and notice that the entrypoint **fails**.

```
> docker build -f Dockerfile.base bazel-bin -t no-caps
> docker run --rm no-caps
socket: Operation not permitted
```

If we amend the `Dockerfile` by adding `setcap` we also see it succeeds.

```patch
--- Dockerfile.base	2025-09-09 15:03:22.525245904 -0700
+++ Dockerfile.setcap	2025-09-09 15:30:54.939933727 -0700
@@ -1,5 +1,6 @@
 FROM alpine:latest
 COPY rawsock /bin/rawsock
-
+RUN apk add --no-cache libcap
+RUN setcap 'cap_net_raw=+ep' /bin/rawsock
 USER nobody
 ENTRYPOINT /bin/rawsock
\ No newline at end of file
```

Now we can build and run it again.

```bash
> docker build -f Dockerfile.setcap bazel-bin -t with-caps

> docker run --rm with-caps
Raw socket created successfully!
```

Back to Bazel! Actions in Bazel are executed under the user that spawned the Bazel process. We can validate this with a simple `genrule`.

```python
genrule(
  name = "whoami",
  outs = ["whoami.txt"],
  cmd = "whoami > $@",
)
```

```bash
# see my user
> echo $USER
fmzakari

> bazel build //:whoami

> cat bazel-bin/whoami.txt
fmzakari
```

How can we go ahead then to create a file with a capability set such that we can replace our `Dockerfile` layer?

Escalating privileges inside a Bazel action with `sudo` isn’t straightforward. You might need to configure `NOPASSWD` for the user, so that it can execute `sudo` without a password. You could also run the whole `bazel` command as `root` but that is granting too much privilege everywhere.

This is where the magic happens ✨.

Let's take another detour!

What are OCI images?

> I actually did a previous write-up on [containers from first principles]({% post_url 2020-05-31-containers-from-first-principles %}) if you are curious for a deeper dive.

We can export the image from Docker and inspect it.

```bash
> docker save with-caps -o image.tar

> mkdir out && tar -C out -xf image.tar 

> tree out
out
├── blobs
│   └── sha256
│       ├── 2ef3d90333782c3ac8d90cc1ebde398f4e822e9556a53ef8d4572b64e31c6216
│       ├── 36ee8511c21d057018b233f2d19f5e99456a66f326e207439bf819aa1c4fd820
│       ├── 418dccb7d85a63a6aa574439840f7a6fa6fd2321b3e2394568a317735e867d35
│       ├── 6fc2d3d65edec3f8b0d5d98e91b1ab397e3e52cfb32898435a02c8fc1009d6ff
│       ├── 719f1782ddd087f61c4e00fbcc84b0174f5905f0a3bfe4af4c585f93305fb0e9
│       ├── 7580940023e6398d8eab451c4c43af0a40fea9bb1a4579ea13339264a2c0e8ca
│       ├── 9b556607f407050861ca81e00fb81b2d418fbe3946a70aa427dfa80f4f38c84f
│       ├── d212c54e044f0092575c669cb9991f99a85007231b14fc3a7da3e1b76a72db92
│       ├── da1a39c8c0dabc8784a2567fa24df668b50d32b13f2893812d4740fa07a1d41c
│       └── f0b1eb9d2ddad91643bebf6a109ac5f47dc3bdb9dfc3bc8d1667b9182125a64b
├── index.json
├── manifest.json
├── oci-layout
└── repositories

> file out/blobs/sha256/9b556607f407050861ca81e00fb81b2d418fbe3946a70aa427dfa80f4f38c84f 
out/blobs/sha256/9b556607f407050861ca81e00fb81b2d418fbe3946a70aa427dfa80f4f38c84f: POSIX tar archive
```

An OCI image is a `tar` archive containing metadata and a series of "blobs" some of which are themselves are `tar` archives.

These blobs are the "layers" that are used to construct the final filesystem and contain all the files that will comprise the rootfs.

```bash
> tar -tf out/blobs/sha256/da1a39c8c0dabc8784a2567fa24df668b50d32b13f2893812d4740fa07a1d41c 

bin/
bin/rawsock
etc/
```

For capabilities to _transport_ themselves through a tar archive, the tar archive itself must have the capability to store extended attributes as well. You can enable this feature with the `--xattrs` option.

```bash
> tar --xattrs --xattrs-include="*" -tf --verbose --verbose \
    out/blobs/sha256/da1a39c8c0dabc8784a2567fa24df668b50d32b13f2893812d4740fa07a1d41c  
drwxr-xr-x  0/0               0 2025-09-09 15:27 bin/
-r-xr-xr-x* 0/0          803920 2025-09-09 15:26 bin/rawsock
  x: 20 security.capability
drwxr-xr-x  0/0               0 2025-09-09 15:30 etc/
```

If you decompress the `tar` archive, and have necessary privileges to set extended attributes (`CAP_SETFCAP` or `sudo`) then the unarchived file will retain the capability and everything will work!

```bash
> mkdir test

> sudo tar --xattrs --xattrs-include="*" -C test -xf \
    out/blobs/sha256/da1a39c8c0dabc8784a2567fa24df668b50d32b13f2893812d4740fa07a1d41c

> getcap test/bin/rawsock
test/bin/rawsock cap_net_raw=ep

> test/bin/rawsock
Raw socket created successfully!
```

What does this have to do with building an OCI image in Bazel?  🤨

Turns out that a trick we can employ is to toggle the necessary bits to mark a file as having a necessary capability _in the tar archive_.

This is exactly what the [xattrs](https://github.com/rmohr/bazeldnf/blob/main/internal/xattrs.bzl) rule in [bazeldnf](https://github.com/rmohr/bazeldnf) does! 🤓

_The key idea_: capabilities live in extended attributes, and `tar` can carry those along. That means you don’t need to run `setcap` inside a `genrule` at build time as the `Dockerfile` equivalent — Bazel can smuggle the bits straight into the image _tar_ layer to be consumed by a OCI compliant runtime. ☝️

This trick neatly sidesteps the need for `sudo` in your rules and keeps builds hermetic.

Not every filesystem or runtime will honor these attributes, but when it works it’s a clever, Bazel-flavored way to package privileged binaries without breaking sandboxing.
