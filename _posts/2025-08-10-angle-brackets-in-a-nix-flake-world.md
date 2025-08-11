---
layout: post
title: Angle brackets in a Nix flake world
date: 2025-08-10 14:05 -0700
---

At [DEFCON33](https://defcon.org/html/defcon-33/dc-33-index.html), the Nix community had its first-ever presence via [nix.vegas](https://nix.vegas) and I ended up in fun conversation with [tomberek](https://github.com/tomberek) 🙌.

_"What fun things can we do with `<` and `>` with the eventual deprecation of `NIX_PATH`?_

> The actual 💡 was from [tomberek](https://github.com/tomberek) and this is a demonstration of what that might look like without necessitating any changes to CppNix itself.

[![Nix DEFCON Badge](/assets/images/nix_badge_25p.jpeg)](/assets/images/nix_badge_50p.jpeg)

As a very worthwhile aside, the first time presence of the Nix community at DEFCON was fantastic and I am extra appreciative to [numinit](https://github.com/numinit) and [RossComputerguy](https://github.com/RossComputerguy) 🙇. The badges handed out were so cool. They have strobing LEDs but also can act as a substituter for the Nix infra that was setup.

Okay, back to the idea 💁.

Importing _nixpks_ via the `NIX_PATH` through the angle-bracket syntax has been a long-standing wart on the reproducibility promises of Nix.

```nix
let pkgs = import <nixpkgs> {};
in
pkgs.hello
```

There is a really great article about all the problems with this approach to bringing in projects on [nix.dev](https://nix.dev/reference/pinning-nixpkgs.html), for those whom are still leveraging it.

With the eventual planned removal of support for `NIX_PATH`, we are now presented with an opportunity of some new functionality in Nix, namely the angled brackets `<something>` that can be reconstituted for a new purpose.

> Looks like others are already starting to think about this idea. The project [htmnix](https://rgbcu.be/blog/htmnix) demonstrates the functionality of writing pure-HTML but evaluating it with `nix eval` 😂.

For something potentially more immediately useful, how about giving quicker access to the attributes of the current flake? 🤔

A common pattern that has emerged is to inject `inputs` and `outputs` into `extraSpecialArgs` so that they are available to modules in NixOS or home-manager.

```nix
{
  homeConfigurations = {
    "alice" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."aarch64-darwin";
        extraSpecialArgs = {inherit inputs outputs;};
        modules = [
            ./users/alice
        ];
    };
}
```

This lets you add the modules from your `inputs` or reference the packages in your `outputs` from within the modules themselves.

```nix
{
  inputs,
  pkgs,
  lib,
  config,
  osConfig,
  ...
}: {
  imports = [
    ./git.nix
    inputs.h.homeModules.default
    inputs.nix-index-database.homeModules.nix-index
  ];
```

That seems nice but also unnecessary. Why not leverage the angled brackets for the same purpose. ☝️

That would make the equivalent example without needing to now wire up the `inputs`.

```nix
{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}: {
  imports = [
    ./git.nix
    <inputs.h.homeModules.default>
    <inputs.nix-index-database.homeModules.nix-index>
  ];
```

Is this possible today? Yes!

Whenever Nix sees angled brackets `<something>` it desugars the expression to a call to `__findFile`.

```bash
> nix-instantiate --parse --expr "<hello>"
(__findFile __nixPath "hello")
```

If we offer a variant of `__findFile` in scope, Nix will call our implementation rather than the default implementation.

Let's implement a variant that utilizes `builtins.getFlake` to return the current flake attributes.

Our goal is to write something as simple as the following and have the contents within the angle brackets be treated as an attribute path of the flake.

```nix
<outputs.hello> + " and welcome to Nix!"
```

What do we have to do to get this to work?
Well we need to provide our own version of `__findFile`.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgslib.url = "github:nix-community/nixpkgs.lib";
  };
  description = "Trivial flake that returns a string for eval";

  outputs = {
    nixpkgslib,
    nixpkgs,
    self,
  }: {
    __findFile = nixPath: name: let
      lib = nixpkgslib.lib;
      flakeAttrs = builtins.getFlake (toString ./.);
    in
      lib.getAttrFromPath (lib.splitString "." name) flakeAttrs;
    hello = "Hello from a flake!";

    example = builtins.scopedImport self ./default.nix;
  };
}
```

We write a function of `__findFile` that trivially splits the contents within the angle bracket to access the attrset of the flake as returned by `builtins.getFlake (toString ./.)`.

> There is some additional magic with `builtins.scopedImport` 🪄 which **is not documented**. It allows giving a different base set of variables, via a provided attrset, to use for variables. This is how we can override `__findFile` in all subsequent files.

So does this even work?

```bash
> nix eval .#example --impure
"Hello from a flake! and welcome to Nix!"
```

Yes! 🔥 _With the caveat that we had to provide `--impure` since getting the current flake via `./.` requires it_.

This is a pretty ergonomic way to access the attributes of the current Flake automatically without having us all to go through the same setup for what is amounting to common best practices.

The need to have `--impure` is a bit of a bummer although this is a pretty neat improvement. There could be a new builtin, `builtins.getCurrentFlake`, which automatically provides the context of the current flake and therefore could be pure.

### Update: simpler & pure

I got some wonderful feedback from [eljamm](https://github.com/eljamm) via the [discourse post](https://discourse.nixos.org/t/angle-brackets-in-a-nix-flake-world/67855) that we can just leverage `self` and avoid having to use `builtins.getFlake`.


```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgslib.url = "github:nix-community/nixpkgs.lib";
  };
  description = "Trivial flake that returns a string for eval";

  outputs =
    {
      nixpkgslib,
      nixpkgs,
      self,
    }:
    {
      __findFile =
        nixPath: name:
        let
          lib = nixpkgslib.lib;
        in
        lib.getAttrFromPath (lib.splitString "." name) self;

      hello = "Hello from a flake!";
      example = builtins.scopedImport self ./default.nix;
    };
}
```

We now don't need to provide `--impure` 👌 and we get all the same fun _new_ ergonomic way to access flake attributes.

```bash
> nix eval .#example
"Hello from a flake! and welcome to Nix!"
```