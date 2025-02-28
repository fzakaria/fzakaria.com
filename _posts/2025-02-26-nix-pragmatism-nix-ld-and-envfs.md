---
layout: post
title: 'Nix pragmatism: nix-ld and envfs'
date: 2025-02-26 16:22 -0800
excerpt_separator: <!--more-->
---

I have been daily driving [NixOS](https://nixos.org) for nearly a year on my wonderful [frame.work](https://frame.work/) laptop; and have been a Nix-enthusiast for ~5 years.

Prior to NixOS, I primarily ran Nix atop my Debian distro, single-user mode, which worked suprisingly well. I loved the simplicity _but_ I was blissfully unaware of how non-hermetic I was! 😱

<!--more-->

A typical distribution has a filesystem-hierarchy-standard (FHS) that underpins how everything works; something Nix works hard to expunge. Interestingly though, this backstop provided a nice UX for leveraging Nix tools that might not be fully sealed (i.e. may still rely on a system-wide library) to continue working.

Examples of Nix packages that are not "fully sealed" are more numerous than I presumed, such as applications that presumed a binary to exist. This is something that became _very clear_ the moment I migrated to NixOS and no longer had that safety-net.

Many of the applications I considered to have _"Nixified"_ were borked in some odd-way that required me to investigate and fix as I considered myself a "Nix purist" 🕊️.

I'm here to let you all know, it's OK to be pragmatic in the spirit of having a friendly UX and inching your way to Nix Valhalla 👌.

[Mic92](https://github.com/Mic92) has done some of the best contributions in making this possible via two amazing tools: [envfs](https://github.com/Mic92/envfs) & [nix-ld](https://github.com/nix-community/nix-ld).

To make your NixOS 100% more usable, _at a slight cost to reproducibility_, simply add the following to your `configuration.nix`

```nix
# I got tired of facing NixOS issues
# Let's be more pragmatic and try to run binaries sometimes
# at the cost of sweeping bugs under the rug.
programs = {
  nix-ld = {
    enable = true;
    # put whatever libraries you think you might need
    # nix-ld includes a strong sane-default as well
    # in addition to these
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
    ];
  };
};

services = {
  envfs = {
    enable = true;
  };
};
```

What are these two things? 🤨

**nix-ld**

Typically, ELF binaries set their dynamic linker / interpreter to a global path on the system that is usually `/lib64/ld-linux-x86-64.so.2`.

On a NixOS system there is no standard `ld.so` (dynamic linker) and each ELF binary specifies an exact _/nix/store/_ entry instead.

Furthermore, the libraries necessary for a binary in a Nix application are specified by the `RPATH` to entries as well within the _/nix/store_.

This wreaks havoc with prebuilt binaries from other distributions on NixOS as the first thing the Linux kernel performs is `execve` into the interpreter set on the binary and find all the necessary shared libraries.

_nix-ld_ places a special interpreter at this well known that respects a special environment variable `NIX_LD_LIBRARY_PATH`. This interpreter then sets `LD_LIBRARY_PATH` to the same value before `execve` into a dynamic linker within the _/nix/store_.

The `LD_LIBRARY_PATH` set, allows for these prebuilt binaries to find libraries on a NixOS system they would otherwise could not due to the lack of FHS.

**envfs**

Plenty of downloaded scripts and prebuild code _presume_ the presence of binaries at `/bin` or `/usr/bin`. The "correct" solution would be to patch the code to use `/usr/bin/env` or directly reference the _/nix/store_ we are pragmatists!

[envfs](https://github.com/Mic92/envfs) sets up a FUSE filesystem (i.e. virtual filesystem) at `/bin` and `/usr/bin` that pretends every binary available at your `PATH` can be found at these directories.

That means the values of these directories can change depending on your current `PATH`, such if you enter a new `nix shell` 😮.

When life gives you lemons 🍋 make lemonade 🥤. Nix is great but not at the cost of your sanity. Ease yourself in and become a pragmatist.