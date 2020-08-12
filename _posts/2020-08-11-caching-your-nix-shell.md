---
layout: post
title: caching your nix-shell
date: 2020-08-11 19:12 -0700
excerpt_separator: <!--more-->
---

**tl;dr;** you can use the following invocation to cache  your _nix-shell_
```bash
 $ nix-store --query --references $(nix-instantiate shell.nix) | \
    xargs nix-store --realise | \
    xargs nix-store --query --requisites | \
    cachix push your_cache
```

I have been _hooked_ on Nix as a way to introduce **reproducible** development environments. However I had to introduce a _shell.nix_ file for a project that relied on a very old version of [nodejs](https://nodejs.org/en/).

<!--more-->

Using an old-version worked -- _which was great considering nix is promising hermetic packages_ -- however waiting to build this particular nodejs version on every machine was a big _time sink_.

No problem! Nix offers the concept of a binary cache to avoid having to rebuild packages needlessly.

> A binary cache builds Nix packages and caches the result for other machines.

If you do a quick Google search for _"how to cache my nix-shell"_ you quickly discover [cachix](https://cachix.org/).

The prevailing wisdom at the time, outlines the following _incantation_ to cache.
```bash
nix-store -qR --include-outputs $(nix-instantiate shell.nix)
```

While it's not _technically wrong_ it's caching **way more** than you want. It is included not only the immediate _buildInputs_ of your _mkShell_ but their complete _build-time_ transitive dependencies.

Let's break down a simple example!
Here is a simple _nix-shell_ that simply pulls in _Chromium_.
```nix
let nixpkgs = import <nixpkgs> {};
in
with nixpkgs;
with stdenv;
with stdenv.lib;
mkShell {
  name = "example-shell";
  buildInputs = [chromium];
}
```

Let's us run the prevailing wisdom command.

```bash
$ nix-store --query --requisites --include-outputs $(nix-instantiate shell.nix) | wc -l

2102
```

**2102** store-paths that need to be uploaded!

The problem comes with calling _requisites_ on a derivation which is the result of _nix-instantiate_. We cannot call **nix-build** because you cannot _realise_ **mkShell**!

> --requisites
>           A source deployment is obtained by distributing the closure of
>           a store derivation.

What do we want ? We want the immediate _build-time_ dependencies of our derivation but for each dependency, only include their _run-time_ dependencies.

Let's first checkout the immediate dependencies by using _references_.

> --references
           Prints the set of references of the store paths paths, that is, their immediate dependencies. (For all
           dependencies, use --requisites.)

```bash
 nix-store --query --references $(nix-instantiate shell.nix)
/nix/store/9krlzvny65gdc8s7kpb6lkx8cd02c25b-default-builder.sh
/nix/store/72kcdqdnz8myr2s28phzi48cv2a8q5x3-bash-4.4-p23.drv
/nix/store/04jbnjp8522lv7bpwzp2jy8nihplj9kk-chromium-84.0.4147.105.drv
/nix/store/prnb5ax5x8xapg5xmmh8w1c7zx8f0j9c-stdenv-linux.drv
```

The _problem_ is that it's returning the **.drv** for chromium; if we were to call `--requisites` on it; we would get the huge dependency set as earlier.

The _"trick"_ is to _realise_ it so we get an output-path.

```bash

$ nix-store --query --references $(nix-instantiate shell.nix) | \
    xargs nix-store --realise | \
    xargs nix-store --query --requisites | \
    wc -l

221
```

**221** store-paths that need to uploaded!

Hurray much smaller!

Tying it now with [cachix](https://cachix.org/) we get this nice one-liner.
```bash
 $ nix-store --query --references $(nix-instantiate shell.nix) | \
    xargs nix-store --realise | \
    xargs nix-store --query --requisites | \
    cachix push your_cache
```