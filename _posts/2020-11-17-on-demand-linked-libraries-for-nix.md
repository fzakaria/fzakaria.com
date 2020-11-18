---
layout: post
title: On-demand linked libraries for Nix
date: 2020-11-17 21:32 -0800
excerpt_separator: <!--more-->
---

> This is a write up of some discussion ongoing with some folks on the [#nix-community](irc://irc.freenode.net/nix-community) IRC chat primarily being driven by [Mic92](https://github.com/Mic92).

Nixpkgs maintains the highest rating on [Repology](https://repology.org/) for having the most packages & which are up to date. Unfortunately even with the current ecosystem of packages, there will always be gaps, and for beginners in NixOS a common question is:

_"I've download a binary and would like to run it on NixOS"_

> Take a look at this graph <https://repology.org/repositories/graphs>

![repology graph](/assets/images/repology.svg)

**Can we do better & streamline running non-Nix software?** 🤔

This was some of the questions posed by some Nix contributors and I wanted to capture the ideas put forward for others.

<!--more-->

## A brief tour of linking

Without going into a ton of detail about how dynamic libraries are performed on Linux; a Linux binary - [ELF format](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format) - contains information pertaining to the dynamic libraries necessary for the binary.

For instance, here is a non-NixOS Ruby installation.
```bash
❯ readelf -d $(which ruby) | grep NEEDED
 0x0000000000000001 (NEEDED)             Shared library: [libruby-2.7.so.2.7]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
```
It requires two dynamic libraries _libruby_ & _libc_. These libraries may themselves have other dependencies, so we can use **ldd** to recursively find the dependency closure.

```bash
❯ ldd $(which ruby)
    linux-vdso.so.1 (0x00007ffed1705000)
    /lib/x86_64-linux-gnu/libnss_cache.so.2 (0x00007f3626cd0000)
    libruby-2.7.so.2.7 => /lib/x86_64-linux-gnu/libruby-2.7.so.2.7 (0x00007f3626960000)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f362679b000)
    libpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007f3626779000)
    librt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x00007f362676e000)
    libgmp.so.10 => /lib/x86_64-linux-gnu/libgmp.so.10 (0x00007f36266eb000)
    libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f36266e3000)
    libcrypt.so.1 => /lib/x86_64-linux-gnu/libcrypt.so.1 (0x00007f36266a8000)
    libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f3626564000)
    /lib64/ld-linux-x86-64.so.2 (0x00007f3626cde000)
```

We can see here that **ldd** resolved the libraries to locations in my [Filesystem Hierarchy Standard](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard)(FHS).

This is *not hermetic*, as the FHS is a global shared state across my machine.
This is the exact problem that Nix itself wants to address.

> I'm on a Debian distro at the moment.

Nix addresses this generally by patching the ELF header to _fully specify_ where the shared libraries can be found in the _/nix/store_; so that they are not resolved or searched on the FHS.

```
❯ readelf -d $(which ruby) | grep RUNPATH
 0x000000000000001d (RUNPATH) Library runpath:
 [/nix/store/z5lira1853d97gbmv1qbdjjpkjn7ksj8-ruby-2.6.6/lib:
 /nix/store/8fcxqg8dmwlkjw2vgkgz607kr5jy552w-zlib-1.2.11/lib:
 /nix/store/kah5n342wz4i0s9lz9ka4bgz91xa2i94-glibc-2.32/lib]
```

This _patching_ however relies on the Nix _stdenv_ derivation builder and ultimately is what makes binaries in Nix work.

> Nix actually takes it a step further and patches the linker so that it does not even try to check the FHS.

Binaries downloaded from the Internet are not patched. What can be done?

## Interpreter

A key insight into the bootstrapping of an ELF binary in Linux is the _interpreter_, whose presence is there to help satisfy any dynamic linkage.

Let's take a look again at my non-Nix Ruby binary

```bash
❯ readelf -l $(which ruby) | grep interpreter
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
```

> Nix built binaries use a [patchelf](https://github.com/NixOS/patchelf) utility that not only sets the _RUNPATH_ to pin libraries but also changes the interpreter to one in the _/nix/store_

It is the interpreter's goal to find the libraries listed in the ELF file either via the _RUNPATH_, _LD_LIBRARY_PATH_ or the _FHS_ well known directories.

⚠️ On NixOS `/lib64/ld-linux-x86-64.so.2` normally **does not exist** and as a result you will be greeted with an unfriendly _"bad ELF interpreter: No such file or directory"_ error.

## nix-ld

We have a binary that needs some shared libraries & the bootstrapping process calls out to the interpreter set in the ELF header.

💡 Let's put a _fake_ interpreter on NixOS machines!

> This idea works since the path of Linux _ld_ is well known for each distribution.

For instance, NixOS machines can place an entry at _/lib64/ld-linux-x86-64.so.2_ for a custom binary that can help resolve dynamic libraries **at runtime** to libraries within the _/nix/store_.

This is in fact what [Mic92](https://github.com/Mic92) has started with his project [nix-ld](https://github.com/Mic92/nix-ld).

How can our custom _ld_ locate the necessary libraries though? This is where we can get really crazy. 🤪

We can use [nix-index](https://github.com/bennofs/nix-index) -- a files database for nixpkgs -- to locate packages in Nix that provide the necessary library. 🤯

The packages can be realized on-demand onto the host and their _/nix/store_ entry can then be included into the _LD_LIBRARY_PATH_ environment variable set when handing off to the _real ld_.

> If gc-roots are set for the required libraries, this determination can then be cached for a given binary.

Fancier best-effort matching on picking packages that have the highest % of required symbols could also be done.

It seems kind of crazy that just picking random packages from the _nix-index_ would ultimately let us run the binary; except that is how traditional software in Linux normally works! 😱

At worst it is providing the same experience users typically experience on non-NixOS distributions but giving a gentler onboarding for people as they see the Nix-light 😇