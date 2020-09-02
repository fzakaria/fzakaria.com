---
layout: post
title: nix coercion trick
date: 2020-09-02 14:36 -0700
---

> **tl;dr;** If the _attrset_ contains **outPath**, it can automatically be converted to a String.

The Nix expression language is *somewhat* documented.
I came across the following links:
1. https://nixos.wiki/wiki/Nix_Expression_Language
2. https://nixery.dev/nix-1p.html
3. https://nixos.org/guides/nix-pills/basics-of-language.html
4. https://nixos.org/manual/nix/stable/#sec-constructs
5. https://medium.com/@MrJamesFisher/nix-by-example-a0063a1a4c55

Nix is a strongly typed language although it is lazily typed.
The fact that it is strongly typed means that certain type coercion are
not feasible.

```bash
nix-repl> (1 + "Hello")
error: cannot add a string to an integer, at (string):1:2
```

However while playing around with [niv](https://github.com/nmattia/niv); I noticed that the attribute sets could automatically be converted to strings.

```bash

nix-repl> sources = import ./nix/sources.nix

nix-repl> :p sources.nixpkgs
{ branch = "nixpkgs-unstable"; description = "Nix Packages collection"; homepage = null; outPath = "/nix/store/shayf8qxmb7aqgzncvz1abnar7s2cssa-nixpkgs-src"; owner = "NixOS"; repo = "nixpkgs"; rev = "f9567594d5af2926a9d5b96ae3bada707280bec6"; sha256 = "0vr2di6z31c5ng73f0cxj7rj9vqvlvx3wpqdmzl0bx3yl3wr39y6"; type = "tarball"; url = "https://github.com/NixOS/nixpkgs/archive/f9567594d5af2926a9d5b96ae3bada707280bec6.tar.gz"; url_template = "https://github.com/<owner>/<repo>/archive/<rev>.tar.gz"; }

nix-repl> builtins.typeOf sources.nixpkgs
"set"

nix-repl> "${sources.nixpkgs}"
"/nix/store/shayf8qxmb7aqgzncvz1abnar7s2cssa-nixpkgs-src"
```

How is this possible?

After a very helpful [post](https://discourse.nixos.org/t/using-niv-to-version-home-manager-zsh-plugins/5060/5) by [danieldk](https://github.com/danieldk); the answer was found!

> Please checkout https://github.com/NixOS/nix/blob/b721877b85bbf9f78fd2221d8eb540373ee1e889/src/libexpr/eval.cc#L1772 for relevant source.

```cpp
if (v.type == tAttrs) {
    auto maybeString = tryAttrsToString(pos, v, context, coerceMore, copyToStore);
    if (maybeString) {
        return *maybeString;
    }
    auto i = v.attrs->find(sOutPath);
    if (i == v.attrs->end()) throwTypeError(pos, "cannot coerce a set to a string");
    return coerceToString(pos, *i->value, context, coerceMore, copyToStore);
}
```

If the _set_  contains **outPath*; then the set can be coerced into a string!

```bash
nix-repl> set = { outPath="Hello World"; }

nix-repl> "${set}"
"Hello World"
```

