---
layout: post
title: Investigating hydration times with Nix
date: 2021-08-10 08:43 -0700
excerpt_separator: <!--more-->
---

>  📣 I want a give a huge shoutout to my colleague [Micah Catlin](https://www.linkedin.com/in/micah-catlin-0718991), whose been constantly challenging me on questions on Nix -- his analytical skills are 11/10. 🤓

We are working on a new build system using Nix as the underpinning framework. In order to smooth out the developer experience, we wanted to tackle a very simple question:

_"Can we force developers only to pull from the Nix binary cache?"_

<!--more-->

🤔 I did what you might typically do and visit the documentation for [nix.conf](https://nixos.org/manual/nix/unstable/command-ref/conf-file.html) where it lists.

> max-jobs
>
> This option defines the maximum number of jobs that Nix will try to build in parallel. The default is 1. The special value auto causes Nix to use the number of CPUs in your system. 0 is useful when using remote builders to prevent any local builds (except for preferLocalBuild derivation attribute which executes locally regardless). It can be overridden using the --max-jobs (-j) command line switch.
>
> Default: 1
> 
> Deprecated alias: build-max-jobs

👌 Perfect! I answer the following and show an example:

"Sure, just set _max-jobs_ to zero in the configuration."

```bash
❯ nix-build --no-out-link lolhello.nix --option max-jobs 0
these derivations will be built:
  /nix/store/vwrgdjl9h1h53ch2zh8cb18nd2raz8a7-lolhello.drv
these paths will be fetched (0.35 MiB download, 0.34 MiB unpacked):
  /nix/store/vgaqghyhgk3apb503q5483v8cmn32ggm-hello-2.3.tar.bz2
error: 1 derivations need to be built, but neither local builds ('--max-jobs') nor remote builds ('--builders') are enabled
```

My astute colleague however notices that setting up our _nix-shell_ now takes considerably longer. His hypothesis is that the _max-jobs_ when set to 0 now forces the downloading to become sequential.

Let's test! 📝

First we will create a _large_ dummy Nix artifact.

```nix
let nixpkgs = import <nixpkgs> {};
in
with nixpkgs;
with stdenv;
with lib;
let make-large-derivation = name: derivation {
        inherit name;
        system = builtins.currentSystem;
        builder = writeScript "builder.sh" ''
            #!/bin/sh
            ${coreutils}/bin/dd if=/dev/urandom of=$out bs=64M count=16
        '';
    };
    a = (make-large-derivation "a");
    b = (make-large-derivation "b");
in
derivation {
    name = "test";
    system = builtins.currentSystem;
    builder = writeScript "builder.sh" ''
        #!/bin/sh
        echo ${a} >> $out
        echo ${b} >> $out
    '';
}
```

```bash
❯ time nix-build --no-out-link large-dummy-a.nix
these derivations will be built:
  /nix/store/nk7gljxxv2g5c6n4x08sdhmrvmg8smph-builder.sh.drv
  /nix/store/vgbgd05fcgas6imrm4xsgilsv8gx1jqm-b.drv
  /nix/store/zcdqjiqvampv7k3n161vzb6vzk2m35an-a.drv
  /nix/store/gll9fjjcsji6yvw4zg3lfcmwi9mn4v3w-builder.sh.drv
  /nix/store/xyx3zxkvjrkchjsz7gb9kzp7j3kiwypz-test.drv
building '/nix/store/nk7gljxxv2g5c6n4x08sdhmrvmg8smph-builder.sh.drv'...
building '/nix/store/zcdqjiqvampv7k3n161vzb6vzk2m35an-a.drv'...
/nix/store/0vkw1m51q34dr64z5i87dy99an4hfmyg-coreutils-8.32/bin/dd: warning: partial read (33554431 bytes); suggest iflag=fullblock
0+16 records in
0+16 records out
536870896 bytes (537 MB, 512 MiB) copied, 15.8208 s, 33.9 MB/s
building '/nix/store/vgbgd05fcgas6imrm4xsgilsv8gx1jqm-b.drv'...
/nix/store/0vkw1m51q34dr64z5i87dy99an4hfmyg-coreutils-8.32/bin/dd: warning: partial read (33554431 bytes); suggest iflag=fullblock
0+16 records in
0+16 records out
536870896 bytes (537 MB, 512 MiB) copied, 15.18 s, 35.4 MB/s
building '/nix/store/gll9fjjcsji6yvw4zg3lfcmwi9mn4v3w-builder.sh.drv'...
building '/nix/store/xyx3zxkvjrkchjsz7gb9kzp7j3kiwypz-test.drv'...
/nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
nix-build --no-out-link large-dummy-a.nix  3.24s user 31.37s system 94% cpu 36.506 total

❯ cat /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test

/nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a
/nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b

❯ ls -lh /nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a

Permissions Size User     Date Modified Name
.r--r--r--  536M fmzakari 31 Dec  1969  /nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a
❯ ls -lh /nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b

Permissions Size User     Date Modified Name
.r--r--r--  536M fmzakari 31 Dec  1969  /nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b
```

Building it from scratch takes **31.37s** 🕒

I add the large derivations to `$out` so it's a runtime dependency
```bash
❯ nix-store --query --tree /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test

/nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
+---/nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b
+---/nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a
```

Let's upload them both to cachix.

```bash
❯ cachix push fzakaria /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
compressing and pushing /nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a (512.00 MiB)
compressing and pushing /nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b (512.00 MiB)
compressing and pushing /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test (208.00 B)
All done.
```

**Don't forget to cleanup these paths in between tests**

```bash
❯ nix-store --delete /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test; \
  nix-store --delete /nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a; \
  nix-store --delete /nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b;
```

Now let's _time_ building it with jobs set to the _max-jobs_ set to 5.

```bash
❯ time nix-build --no-out-link large-dummy-a.nix --option max-jobs 5
these paths will be fetched (1024.05 MiB download, 1024.00 MiB unpacked):
  /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
  /nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b
  /nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a
copying path '/nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a' from 'https://fzakaria.cachix.org'...
copying path '/nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b' from 'https://fzakaria.cachix.org'...
copying path '/nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test' from 'https://fzakaria.cachix.org'...
/nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
nix-build --no-out-link large-dummy-a.nix --option max-jobs 5  17.78s user 5.87s system 55% cpu 42.275 total
```

Downloading it with the default number of jobs, takes **17.78s** 🕒


Now let's _time_ building it with jobs set to _0_.

```bash
❯ time nix-build --no-out-link large-dummy-a.nix --option max-jobs 0
these paths will be fetched (1024.05 MiB download, 1024.00 MiB unpacked):
  /nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
  /nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b
  /nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a
copying path '/nix/store/ln0d29k6zfskhgvig4kyhcql0phxd4qw-a' from 'https://fzakaria.cachix.org'...
copying path '/nix/store/ifc68r8i5dng7c4vmds81vl3gig6gfpr-b' from 'https://fzakaria.cachix.org'...
copying path '/nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test' from 'https://fzakaria.cachix.org'...
/nix/store/232rq7y1f09pn2amk3lcjqmws341vp3q-test
nix-build --no-out-link large-dummy-a.nix --option max-jobs 0  16.89s user 5.19s system 37% cpu 59.330 total

```

Hmmm. It still takes the same amount of time roughly **16.89s**.

I can't seem to get a noticeable impact with my experiment. I did find another configuration parameter _http-connections_ that seems to affect more the concurrency of the downloads from the binary store.

> http-connections
>
> The maximum number of parallel TCP connections used to fetch files from binary caches and by other downloads. It defaults to 25. 0 means no limit.
>
> Default: 25
> 
> Deprecated alias: binary-caches-parallel-connections

Next step is to audit the source code and or think more about my experiment.
Perhaps it's not representative enough to show the problem he was noticing.