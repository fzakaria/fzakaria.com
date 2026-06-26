---
layout: post
title: 'GuixPkgs: every Guix package, as a Nix flake'
date: 2026-06-25 09:00 -0700
---

<p align="center">
  <img src="/assets/images/guixpkgs-logo.png" alt="GuixPkgs Logo" width="250" />
</p>

I wrote earlier about what I believe to be an _absurd idea_,  [The Guix Nix Abomination]({% post_url 2026-06-05-the-guix-nix-abomination-leveraging-guix-derivations-in-nix %}): a tool, [guix-transfer](https://github.com/fzakaria/guix-transfer), that takes **any** Guix derivation and rewrites it into a Nix derivation, and lets `nix-daemon` build it.

With this primitive in hand, I pondered what it would mean to **import the entire Guix package set** into Nix.

> That means we could even build a `flake` that is all of Guix packages available for use.

Well.... Hello [GuixPkgs](https://github.com/fzakaria/guixpkgs). 🤯


[Nixpkgs](https://github.com/NixOS/nixpkgs) is famously the largest package repository in the world. GuixPkgs makes it bigger by including in the _entire_ GNU Guix package set so you can mix and match Guix and Nixpkgs packages in the same flake.

```nix
{
  description = "A project mixing Nix and Guix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    guixpkgs.url = "github:fzakaria/guixpkgs";
  };

  outputs = { self, nixpkgs, guixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    guixPkgs = guixpkgs.packages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        pkgs.git        # from Nixpkgs
        guixPkgs.hello  # from Guix, via GuixPkgs
      ];
    };
  };
}
```

```console
❯ nix build github:fzakaria/guixpkgs#hello
❯ ./result/bin/hello
Hello, world!
```

☝ Don't forget, that `hello` is built from Guix's source bootstrap, a 357-byte seed all the way up to GCC and glibc but it lands in `/nix/store` and behaves like any other Nix package. No `guix` required on the consuming side.

Is this just a joke or is there anything of value here?

Well, some packages only exist in Guix, notable many GNU Guile built software, like [guile-png](https://github.com/artyom-poptsov/guile-png) that are now easily available in Nix. 🤷

How does it work?

1. Pins a Guix commit and uses `guix time-machine` to get derivations from _that exact_ Guix thus decoupling the result from whatever `guix-daemon` version happens to be on the host.
2. Dumps every package's `.drv` and feeds them to `guix-transfer --disable-tests --emit-nix-dir pkgs`.
3. Rebuilds the `by-name/` index and records the Guix channel + commit + timestamp in `guix-metadata.json`.

Realising a Guix package under Nix recompiles Guix's **entire source bootstrap**. That's _hours_ per closure. To skip it, GuixPkgs ships a [Cachix](https://www.cachix.org/), `cachix use guixpkgs`, binary cache that is included in the flake. Thank you [@domenkozar](https://github.com/domenkozar) for sponsoring me with extra storage. 🙏

What's next?

We can now do some truly horrendous evil stuff.
What about an overlay that replaces every package from Nixpkgs which one that exists in Guix? 😈

We can then build a NixOS machine where every package is the Guix equivalent 😱.

This was a really fun project to pursue during [TacoSprint](https://tacosprint.org).

[![taco sprint group photo](/assets/images/tacosprint_group_50p.jpg)](/assets/images/tacosprint_group.jpg)
