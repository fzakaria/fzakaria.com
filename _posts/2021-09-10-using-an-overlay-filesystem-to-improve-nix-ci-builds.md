---
layout: post
title: Using an overlay filesystem to improve Nix CI builds
date: 2021-09-10 08:58 -0700
excerpt_separator: <!--more-->
---

Using Nix in our CI system has been a huge _boon_. Through Nix we have a level of guarantee of reproducibility between our local development environment and our CI platform. 🙌

Our CI infrastructure leverages containers (don't they all now?) for each job and we explored different solutions to reduce the cost of constantly downloading the _/nix/store_ necessary for the build.

<!--more-->

## Fat Docker image

At first, we implemented a solution where the _/nix/store_ was embedded within the Docker image itself.

This was an interesting choice for a few reasons:
1. We could disable building from source or any substituters in the build and guarantee the image itself had the complete necessary dependency closure.
2. The images themselves are cached locally on the underlying host, meaning subsequent CI jobs don't pay the cost of downloading _/nix/store_ contents
3. Changes to our dependency closure were annoying since it required rebuilding a new Docker image
4. The docker image was very large and minor changes resulted in a complete new large layer -- it wasn't incremental at all.


## Overlay Filesystem

We decided to seek out alternatives where we can remove the prebuild _/nix/store_ from the container but still reduce the cold-boot cost for CI jobs.

The **caveat** to the solution we seeked is that the Docker image still **installed** Nix which meant it created a _/nix/store_ entry and the necessary _~/.nix_profile_ symlinks.

> [Overlayfs](https://github.com/torvalds/linux/commit/e9be9d5e76e34872f0c37d72e25bc27fe9e2c54c) allows one, usually read-write, directory tree to be
overlaid onto another, read-only directory tree.  All modifications
go to the upper, writable layer.

Let's explore how we might go about setting this up! Let's use a _dummy example_.

```dockerfile
FROM ubuntu

# Let's make a dummy nix-store
RUN mkdir -p /nix/store

# let's put a dummy derivation
RUN echo "hello" > /nix/store/hello

# a dummy command
CMD ["/bin/bash"]
```

I will also create some _dummy directories_ on my **host**.

```bash
mkdir -p /tmp/fake-nix/{upper,workdir}

echo "ping" > /tmp/fake-nix/upper/pong
```

Let's spin up a docker container.

```bash
# lets run a docker and bind-mount of host /nix/store
# in this case we called it /tmp/fake-nix
# In reality this will be your host's /nix/store
docker run --privileged -v /tmp/fake-nix:/nix/store-host \
           -it $(docker build . --quiet) /bin/bash
```

Let's check the contents of the _/nix/store_ originally.
We see that it only has out _hello_ file.

```bash
root@c32024e56f25:/# ls /nix/store
hello
```

Now let's mount our overlay filesystem.
```bash
root@c32024e56f25:/# mount -t overlay overlay -o \ 
        lowerdir=/nix/store,upperdir=/nix/store-host/upper,workdir=/nix/store-host/workdir \
        /nix/store
```

Let's check the contents of our _/nix/store_ now.
```bash
root@c32024e56f25:/# ls -l /nix/store
total 8
-rw-r--r-- 1 root   root  6 Sep  9 17:15 hello
-rw-r--r-- 1 780412 89939 5 Sep 10 16:22 pong
```

Great! Our _/nix/store_ now has the contents of the host overlaid ontop of the one within the container.

What if we write a new file?

```bash
root@c32024e56f25:/# echo "test" > /nix/store/test

root@c32024e56f25:/# ls /nix/store
hello  pong  test

root@c32024e56f25:/# ls /nix/store-host/upper/
pong  test
```

We see that it created the file in the _upper_ directory.

What if we update a file in the _lower_ directory?

```bash
root@c32024e56f25:/# echo "world" > /nix/store/hello

root@c32024e56f25:/# ls /nix/store-host/upper/
hello  pong  test
```

Ok cool -- it moved it to our _upper_ directory.

What if we delete the file?
```bash
root@c32024e56f25:/# rm /nix/store/hello

root@c32024e56f25:/# ls /nix/store            
pong  test

root@c32024e56f25:/# ls -l /nix/store-host/upper      
total 8
c--------- 2 root   root  0, 0 Sep 11 02:22 hello
-rw-r--r-- 1 780412 89939    5 Sep 10 16:22 pong
-rw-r--r-- 1 root   root     5 Sep 11 02:19 test
```

The _hello_ file still exists in the _upper_ directory but it's a tombstone file now.
This is to distinguish it from the fact it's been deleted while still existing in the _lower_ directory.

Awesome -- what's great too is that the overlay filesystem that's supported natively in Linux gives you near native performance.

> The implementation differs from other "union filesystem"
implementations in that after a file is opened all operations go
directly to the underlying, lower or upper, filesystems.  This
simplifies the implementation and allows native performance in these
cases.

Hope that helps others in trying to speedup their builds. 🤓