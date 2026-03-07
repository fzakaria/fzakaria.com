---
layout: post
title: Nix is a lie, and that's ok
date: 2026-03-07 09:21 -0800
---

When [Eelco Dolstra](https://edolstra.github.io/), father of Nix, descended from the mountain tops and enlightened us all, one of the main _commandments_ for Nix was to eschew all uses of the [Filesystem Hierarchy Standard (FHS)](https://www.pathname.com/fhs/).

> The FHS is the "find libraries and files by convention" dogma Nix abandons in the pursuit of purity.

[![nix commandments](/assets/images/nix_commandments_50p.png)](/assets/images/nix_commandments_large.png)

What if I told you that was a _lie_ ? 😑

Nix was explicitly designed to eliminate standard FHS paths (like `/usr/lib` or `/lib64`) to guarantee reproducibility. However, graphics drivers represent a hard boundary between user-space and kernel-space.

The user-space library (`libGL.so`) must match the host OS's kernel module and the physical GPU. 

Nearly all derivations do not bundle `libGL.so` with them because they have no way of predicting the hardware or host kernel the binary will run on.

What about NixOS? Surely, we know what kernel and drivers we have there!? 🤔

Well, if we modified every derivation to include the correct `libGL.so` it would cause massive rebuilds for every user and make the NixOS cache effectively useless.

To solve this, NixOS & Home Manager introduce an intentional impurity, a global path at `/run/opengl-driver/lib` where derivations expect to find `libGL.so`.

We've just re-introduced a convention path à la FHS. 🫠

Unfortunately, that leaves users who use Nix on other Linux distributions in a bad state which is documented in [issue#9415](https://github.com/NixOS/nixpkgs/issues/9415), that has been opened since 2015. If you tried to install and run any Nix application that requires graphics, you'll be hit with the exact error message Nix was designed to thwart:

```
error while loading shared libraries: libGL.so.1: 
cannot open shared object file: No such file or directory
```

There are a couple of workarounds for those of us who use Nix on alternate distributions:
* [nixGL](https://github.com/nix-community/nixGL), a runtime script that injects the library via `$LD_LIBRARY_PATH`
* manually hacking `$LD_LIBRARY_PATH`
* creating your own `/run/opengl-driver` and symlinking it with the drivers from `/usr/lib/x86_64-linux-gnu`

For those of us though who cling to the beautiful purity of Nix however it feels like a sad but ultimately necessary trade-off.

_Thou shall not use FHS, unless you really need to._