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

**envfs**