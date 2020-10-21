---
layout: post
title: Nix parallelism & Import From Derivation
date: 2020-10-20 22:24 -0700
excerpt_separator: <!--more-->
---

I recently submitted a pull-request [#101096](https://github.com/NixOS/nixpkgs/pull/101096) for [nixpkgs](https://github.com/NixOS/nixpkgs) to include new functionality to list all files recursively within a directory.

One of the feedback from [@grahamc](https://github.com/grahamc) & [@roberth](https://github.com/roberth) was that function may cause Nix evaluation to _stall_.

It was not clear why and even more confusing is the name given to this _gotcha_; [Import From Derivation](https://nixos.wiki/wiki/Import_From_Derivation).

> Import From Derivation (IFD) is where during a single Nix evaluation, the Nix expression:
> 1. creates a derivation which will build a Nix expression
> 2. imports that expression
> 3. uses the results of the evaluation of the expression.

Let's dig into this problem and how it's caused.

<!--more-->

First off, let's consider a super simple Nix derivation that takes _15 seconds_ to build.

```nix
{ pkgs ? import <nixpkgs> {}}:
with pkgs;
runCommand "long-running" {} ''
    echo "Sleeping!"
    sleep 15
    echo "Finished sleeping" > $out
''
```

We can confirm that _nix-instantiate_ is **instant**, whereas _nix-build_ takes 15 seconds to realise "build" the derivation. _This makes sense, as the sleep is part of the builder of the derivation._

```bash
❯ time nix-instantiate long-running.nix
warning: you did not specify '--add-root'; the result might be removed by the garbage collector
/nix/store/qps2bfm3z5y1pkkq02gknyzd168hpawv-long-running.drv
nix-instantiate long-running.nix  0.19s user 0.04s system 100% cpu 0.227 total

❯ time nix-build --no-out-link long-running.nix
these derivations will be built:
  /nix/store/qps2bfm3z5y1pkkq02gknyzd168hpawv-long-running.drv
building '/nix/store/qps2bfm3z5y1pkkq02gknyzd168hpawv-long-running.drv'...
Sleeping!
/nix/store/smw0a75w5h0hc2wxayh93gzv4nwlnzf9-long-running
nix-build --no-out-link long-running.nix  0.25s user 0.07s system 2% cpu 15.356 total
```

**What if I use this derivation as a dependency of another derivation?**

Let's consider a simple case that uses the derivation within the builder script of another derivation. The derivation _basic-using-long-running_ builder merely stores the _/nix/store_ entry for _long-running_.

```nix
{ pkgs ? import <nixpkgs> {}}:
with pkgs;
let long-running = runCommand "long-running" {} ''
    echo "Sleeping!"
    sleep 15
    echo "Finished sleeping" > $out
'';
in
runCommand "basic-using-long-running" {} ''
    echo "${long-running}" > $out
''
```

Here we see that _nix-instantiate_ continue to be **instant** and _nix-build_ continues to be roughly 15 seconds to build both derivations.

```bash
❯ time nix-instantiate uses-long-running-simple.nix
warning: you did not specify '--add-root'; the result might be removed by the garbage collector
/nix/store/gd2jqmy54xlk3prcsaa3mgcyn7qf85mf-basic-using-long-running.drv
nix-instantiate uses-long-running-simple.nix  0.20s user 0.02s system 94% cpu 0.238 total

❯ time nix-build --no-out-link uses-long-running-simple.nix
these derivations will be built:
  /nix/store/5dqxa586rdb0hiw3d0sbv2xjx6w3wa4y-long-running.drv
  /nix/store/gd2jqmy54xlk3prcsaa3mgcyn7qf85mf-basic-using-long-running.drv
building '/nix/store/5dqxa586rdb0hiw3d0sbv2xjx6w3wa4y-long-running.drv'...
Sleeping!
building '/nix/store/gd2jqmy54xlk3prcsaa3mgcyn7qf85mf-basic-using-long-running.drv'...
/nix/store/6jg8sa5wj8zbynnq5irvxazlcl6cd655-basic-using-long-running
nix-build --no-out-link uses-long-running-simple.nix  0.42s user 0.12s system 3% cpu 16.933 total
```

However, if we access the derivation within a Nix expression itself, it forces the derivation to be built during _nix-instantiate_. 😞

Consider this example, where we read the contents of the first derivation via _builtins.readFile_.

```nix
{ pkgs ? import <nixpkgs> {}}:
with pkgs;
let long-running = runCommand "long-running" {} ''
    echo "Sleeping!"
    sleep 15
    echo "Finished sleeping" > $out
'';
    contents = builtins.readFile long-running;
in
runCommand "basic-using-long-running" {} ''
    echo "${contents}" > $out
''
```

In this case, _nix-instantiate_ takes roughly 16 seconds!

```bash
❯ time nix-instantiate uses-long-running-complex.nix
building '/nix/store/7fwqhzlnd7z21n63s2qrisvd5mjwpyji-long-running.drv'...
Sleeping!
warning: you did not specify '--add-root'; the result might be removed by the garbage collector
/nix/store/n7jiryhhcik4ps26p4ml4r27c5rc0sdn-basic-using-long-running.drv
nix-instantiate uses-long-running-complex.nix  0.40s user 0.06s system 2% cpu 16.273 total

```

_nix-instantiate_ is designed to evaluate quickly and is done serially. Parallelism in Nix enters during realisation of derivations; therefore, any slowing down _nix-instantiate_ simply head-of-line blocks the subsequent building and is no longer eligible to build concurrently potentially.

This was somewhat frustrating since I  prefer to do certain logic in the Nix language than Bash, which I find difficult to read. Helping understand the problem at hand, though, makes it an easier pill to swallow.

=)