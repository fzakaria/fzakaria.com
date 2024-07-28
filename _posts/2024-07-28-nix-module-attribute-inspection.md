---
layout: post
title: Nix Module Attribute Inspection
date: 2024-07-28 14:51 -0700
excerpt_separator: <!--more-->
---

[NixOS](https://nixos.org) modules are great; and it's one of the _superpowers_ of NixOS.
They're so great, there was a [working group](https://discourse.nixos.org/t/working-group-member-search-module-system-for-packages/26574) to look into how to apply the concept to Nixpkgs itself.

> For those uninitiated, there are plenty of guides online describing it's value and purpose such as
[this one](https://nixos-and-flakes.thiscute.world/other-usage-of-flakes/module-system) or on [nix.dev](https://nix.dev/tutorials/module-system/deep-dive.html).

My _largest complaint_ thus far with it was that it's hard to go backwards. ⏪

_"Who and what defined a particular option?"_ 🕵️

<!--more-->

The problem I often want to solve is where did a particular NixOS module option get set.

Imagine we have 3 modules: A, B & C

```nix
# Module A
# moudleA.nix
{lib, ...}: {
  options = {
    a.value = lib.mkOption {
      type = lib.types.bool;
    };
  };
}
```

The common way people find out that a particular option is being set by multiple modules are when their values conflict.

```nix
# Module B
# moduleB.nix
{lib, ...}: {
  config = {
    a.value = true;
  };
}

# Module C
# moduleC.nix
{lib, ...}: {
  config = {
    a.value = false;
  };
}
```

If `Module B` and `Module C` were to conflict with how they set `a.value`, you are presented with a friendly error telling you to decide on a priority.

```console
❯ nix-instantiate --eval default.nix -A config.a.value
error: The option `a.value' has conflicting definition values:
- In `moduleC.nix': false
- In `moduleB.nix': true
Use `lib.mkForce value` or `lib.mkDefault value` to change
the priority on any of these definitions.
```

_This only works if you are using non-mergeable values. What if the values do merge?_

How can I discover all the locations where a particular option is set. 🤔

> Note: This is a real problem I often face. A recent example was I noticed my fingerprint reader `services.fprintd` was enabled.
> I could not figure out where the option was being toggled however.

When the majority of NixOS modules resided in Nixpkgs, I rarely had the problem of attributing where a particular option was set.
I had the not great, but usable, workflow of searching ([`rg`](https://github.com/BurntSushi/ripgrep)) through the whole codebase to find all the likely spots
that might have set it.

With the _proliferation_ of Nix Flakes, this problem has gotten increasingly worse. There is no longer a _single source of truth_ for all your NixOS modules. The Nix Flakes system, encourages decentralized configurations and bringing in individual NixOS modules from many "registries" (_sic: GitHub repositories_).

> Note: One could have pulled in NixOS modules from multiple repositories in the legacy mechanism, but it was hard to manage versioning even with tools like [niv](https://github.com/nmattia/niv) or [npins](https://github.com/andir/npins) so most people upstreamed their module to Nixpkgs itself.

Turns out, the solution to my woes has been in Nixpkgs for over 2 years (circa 2022) via `definitionsWithLocations`. 🎉

You can load up the `nix repl` for a given Nix Flake and find all the locations (only file sadly 😔 no line number) along with their values.

```console
❯ nix repl --extra-experimental-features 'flakes repl-flake' .
warning: unknown experimental feature 'repl-flake'
Nix 2.23.2
Type :? for help.
warning: Git tree '/home/fmzakari/code/github.com/fzakaria/nix-home' is dirty
Loading installable 'git+file:///home/fmzakari/code/github.com/fzakaria/nix-home#'...
Added 7 variables.
nix-repl> options = nixosConfigurations.nyx.options  
nix-repl> pkgs = nixosConfigurations.nyx.pkgs                                                

nix-repl> :p (pkgs.lib.take 2 options.environment.pathsToLink.definitionsWithLocations)      
[
  {
    file = "/nix/store/hxhym8c5xz6dxkl3d9yppiwlnzk3khn7-source/nixos/common.nix";
    value = [ "/etc/profile.d" ];
  }
  {
    file = "/nix/store/ncinwsh2j3197rp8pl4yw7amri5yf9zw-source/users";
    value = [
      "/share/zsh"
      "/share/fish"
      "/share/bash"
    ];
  }
]
```

If you only care to see the files, you can use `files` instead.

```console
nix-repl> :p (pkgs.lib.take 2 options.environment.pathsToLink.files)
[
  "/nix/store/hxhym8c5xz6dxkl3d9yppiwlnzk3khn7-source/nixos/common.nix"
  "/nix/store/ncinwsh2j3197rp8pl4yw7amri5yf9zw-source/users"
]
```

❗ Anywhere you see `XXXXXX-source` is the current Flake (your repository) but you can likely tell
from the path and filenames as well.

**Awesome**; we now have a gesture to find where a particular option is being set along with their values.
Now we can have our cake 🍰 and eat it too; we can have the magic of NixOS modules 🪄 while still having a workflow to
uncover where options may be set.

❗This works great for the most part but doesn't seem to give the correct location for modules imported via Flakes (_I see the humor in this_).
I filed [Issue #11210](https://github.com/NixOS/nix/issues/11210) to track the bug 🐛 and document the behavior.