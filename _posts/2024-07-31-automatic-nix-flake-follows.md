---
layout: post
title: Automatic Nix flake follows
date: 2024-07-31 22:21 -0700
excerpt_separator: <!--more-->
---

If you have used [Nix](https://nixos.org) flakes, you likely encountered something like the following. 🤢

```nix
std.url = "github:divnix/std";
std.inputs.devshell.follows = "devshell";
std.inputs.nixago.follows = "nixago";
std.inputs.nixpkgs.follows = "nixpkgs";

hive.url = "github:divnix/hive";
hive.inputs.colmena.follows = "colmena";
hive.inputs.disko.follows = "disko";
hive.inputs.nixos-generators.follows = "nixos-generators";
hive.inputs.nixpkgs.follows = "nixpkgs";
```

Why is this follows necessary? 🤔

It's in fact **not necessary** but it makes the Nix evaluation simpler and as a result faster. 🤓

<!--more-->

Rather than using the exact Nix flake commit your dependency desires, we are overriding it, with one we have likely already declared. This has the effect of making our graph smaller, which is faster to evaluate and likely build.

For very large Nix projects, the Nix evaluator can be surprisingly slow, so the pattern of _follows_, especially for _nixpkgs_, is incredibly common.

> Note: Although it's faster it's *less correct* since we are deviating from what the authors of the flake desired.

Writing all those follows can get real teadious 🥱, and it's tough to even know you did them all.

Surely there has to be a better way? 🙏

Well take a look at [nix-auto-follow](https://github.com/fzakaria/nix-auto-follow) 🥳

Simply run the script which will modify your _flake.lock_ file. Commit the change and voilà!

```console
> python all-follow.py flake.lock -i
```

How does it work? 🧐 Let's dive in with an example.

Here let's create our main top-level flake. You can think of this as your application or NixOS machine.

```nix
{
  description = "Top Levle Flake";

  inputs = {
    a.url = path:./a;
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
  };

  outputs = { self, a, nixpkgs }: 
  {
    versions = {
        a.nixpkgs = a.versions.nixpkgs;
        nixpkgs = nixpkgs.lib.version;
    };
    
  };
}
```

Our flake has **2** dependencies: `a` & `nixpkgs`.

To keep this example simple, `a` is another local flake which itself only has **1** dependency: `nixpkgs`.

❗ Important to notice here that `nixpkgs` is at a different version in `a`. We have two versions **23.11** & **24.05**.

```nix
{
  description = "Flake A";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
  };

  outputs = { self, nixpkgs }: 
  {
    versions = {
      nixpkgs = nixpkgs.lib.version;
    };
  };
}
```

Our flake emits a `versions` attribute which we can evaluate.
We correcltly see at the start the two different versions of _nixpkgs_.

```console
❯ nix eval "#versions"

{
  a = {nixpkgs = "23.11pre-git";};
  nixpkgs = "24.05.20240729.12bf098";
}
```

If we peek in our `flake.lock` file we see that `nixpkgs` is listed twice as an _inputs_ (`nixpkgs` & `nixpkgs_2`) and that they reference nodess that exist.

```json
{
  "nodes": {
    "a": {
      "inputs": {
        "nixpkgs": "nixpkgs"
      },
    },
    "root": {
        "inputs": {
            "a": "a",
            "nixpkgs": "nixpkgs_2"
        }
    },
    "nixpkgs": {
        ...
    },
    "nixpkgs_2": {
        ...
    },
  }
}
```

Turns out if we make the nodes references by the `inputs` in `roots` (our top level _flake.nix_) the same everywhere, we've effectively done an **automatic follows**.

Let's apply _all-follow.py_ and see what happens.

```console
❯ nix eval "#versions"
{
  a = {nixpkgs = "24.05.20240729.12bf098";};
  nixpkgs = "24.05.20240729.12bf098";
}
```

The _nixpkgs_ versions are now the same! 🎆

Although this _post-processing_ happens out of band from the Nix tool, it's an incredibly simple way to simplify your Nix evaluation and build graph and save you from **follows hell** (Nix's version of _DLL Hell_)

If you find the tool useful, please consider contributing. You can find it at [https://github.com/fzakaria/nix-auto-follow](https://github.com/fzakaria/nix-auto-follow).

> Special thanks to [edolstra](https://github.com/edolstra) & [roberth](https://github.com/roberth) who helped me think through this. 🙇‍♂️
