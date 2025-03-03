---
layout: post
title: 'Nix: string interpolation of directories gone awry'
date: 2025-02-02 20:10 -0800
excerpt_separator: <!--more-->
redirect_from:
  - /2025/02/03/nix-string-interpolation-of-directories-gone-awry.html
  - /2025/02/03/nix-string-interpolation-of-directories-gone-awry
  - /2025/02/03/nix-string-interpolation-of-directories-gone-awry/
---

I was sleuthing 🦥 on the [NixOS](https://nixos.org/) Matrix channel ([#nix:nixos.org](https://matrix.to/#/#community:nixos.org)) -- trying to get some help for my own problems when myself and another user ([@mjm](@mjm:midna.dev)) starting helping someone whom was complaining that their seemingly innocuous derivation was continously rebuilding.

<!--more-->

Here is the _snippet_.

```nix
let
    scriptDir = f: dirPath: { exclude ? [ ], deps ? [ ], env ? { } }:
    lib.mapAttrsToList
        (name: _: f "${dirPath}/${name}" { inherit deps env; })
        (builtins.removeAttrs (builtins.readDir dirPath) exclude);
    scriptBinDir = scriptDir scriptBin;
in
(scriptBinDir ./converters { }) ++
(scriptBinDir ./other { }) ++
(scriptBinDir ./currencies { }) ++
(scriptBinDir ./university { }) ++
```

Do you see the bug? 🐛

At first I thought it was that `scriptBinDir` uses [writeShellApplication](https://ryantm.github.io/nixpkgs/builders/trivial-builders/#trivial-builder-writeShellApplication) which is a _trivial builder_. Most trivial builders set _runLocal_ to be **true**.

_runLocal_
  : If set to true this forces the derivation to be built locally, not using substitutes nor remote builds. This is intended for very cheap commands (<1s execution time) which can be sped up by avoiding the network round-trip(s). Its effect is to set preferLocalBuild = true and allowSubstitutes = false.

Hmm; turns out that it if that were the case, the local `/nix/store` would still be a substitute for the build; so that can't be the cause ❌.

The root-cause is much more _innocuous_, and it's the string interpolation of the directory: `"${dirPath}/${name}"`

Let's see a small example to break this down.

I have a simple file and subdirectory _directory_ with a file _text_ that has some content.

```nix
# You should always pin your nixpkgs
{pkgs ? import <nixpkgs> {}}: let
  a = ./directory + "/text";
  b = "${./directory}/text";
in
  pkgs.writeText "silly-script" ''
    ${a}
    ${b}

    ${builtins.readFile a}
    ${builtins.readFile b}
  ''
```

```shell
$ nix-build example_script.nix
this derivation will be built:
  /nix/store/dvb29lak8q7jq2dmh8gp04i4q48d4q5g-silly-script.drv
building '/nix/store/dvb29lak8q7jq2dmh8gp04i4q48d4q5g-silly-script.drv'...
/nix/store/nq1sf7caspc68bdwf1dyl4fnrfzvq41p-silly-script

$ nix-build example_script.nix
/nix/store/nq1sf7caspc68bdwf1dyl4fnrfzvq41p-silly-script

$ cat result
/nix/store/f8m4h9wbpr05g4dja91xshh9l48a6ac0-text
/nix/store/vd5g23fz1lzyvd6lmsm35hvhkm4rsf6z-directory/text

Hello there!
Hello there!
```

Interesting! Although I'm accessing the same file, it has resulted in a different store-path. 🤔

Does this matter at all? 🤨

Yes! It will cause rebuilds depending if the directory changes **even if the file _text_ does not change**.

I added a new file to _directory_ and here is the result of the derivation.

```shell
cat result
/nix/store/f8m4h9wbpr05g4dja91xshh9l48a6ac0-text
/nix/store/0m5j5lphpi2jsd6xi2fjwn1zqfmxy2hj-directory/text

Hello there!
Hello there!
```

Notice that `f8m4h9wbpr05g4dja91xshh9l48a6ac0` is still the derivation of the first way to access the file but the `-directory` store-path had changed.

This seemingly innocuous difference of how you can access the same file can cause massive rebuilds if you are working in a directory that may contain build files that change often.

Why is this way of "sucking in" a complete directory even available? Why not get rid of the foot-gun alltogether?

Many derivations use the `src` attribute which is often set to a whole directory. The ability to copy the whole directory is quintessential to how this works.

```nix
src = ./directory
```

Watch out for this _papercut_ when you are writing your derivations. If you find your builds are not memoized as muh as you think, this could be a likely culprit.