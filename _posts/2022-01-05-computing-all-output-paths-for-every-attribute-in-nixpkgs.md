---
layout: post
title: Computing all output paths for every attribute in Nixpkgs
date: 2022-01-05 20:49 -0800
excerpt_separator: <!--more-->
---

Nix is an amazing tool, unfortunately doing _simple_ things can be quite challenging.

This is a little write-up of my attempt to try and accomplish what I would have thought to be a _simple_ thing; computing all store paths for every attribute in [nixpkgs](https://github.com/NixOS/nixpkgs/).

Why would I want to do such a thing?

I had some _/nix/store_ entries on my system and I wanted to revisit the **exact** nixpkgs commit with which it was built to debug something.
Without this [reverse index](https://en.wikipedia.org/wiki/Reverse_index) you are pretty much out of luck for figuring it out.

> I want to give early _shoutout_ to other similar tools in this space that let you do meta searches over nixpkgs such as [Nix Package Versions](https://lazamar.co.uk/nix-versions/) and [Pkgs on Nix](https://pkgs.on-nix.com/).

<!--more-->

🗣️ This goal has been made extra arduous due to the migrations of the new Nix CLI commands and the migration to Flakes.

## 🎯 Goal 1: Get a list of all package names

Any attempt to try and do this within the Nix language expression is **doomed**.
Any immediate attempt to iterate over all keys within the _top-level_ attribute in Nixpkgs is faced with hurdle and after hurdle.

I got pretty far with the following [gist](https://gist.github.com/fzakaria/ae27a2ad58e1d80f5453b0ed0052297f) but it still hit roadblocks.
```nix
let
  pkgs = import <nixpkgs> {
    config.allowBroken = true;
    config.allowUnfree = true;
  };
  lib = import <nixpkgs/lib>;
  tryEval = builtins.tryEval;
in
  lib.mapAttrs (k: v:
    let name = (tryEval v.name or "");
    out = (tryEval v.outPath or "");
    in {
      name = name.value;
      out  = out.value;
    }
  ) pkgs
```

Feedback from the community has been to use _nix_ tooling such as _nix-env_ or _nix-search_ that have special handling for all these sharp edges, or some of the _fancier_ work used
by [hydra](https://github.com/NixOS/hydra) or [ofborg](https://github.com/NixOS/ofborg/).

I succumb to peer pressure and decided to use these tools 😮‍💨 rather than what I was hoping to be an elegant _pure Nix_ expression.

```bash
❯ nix search . --json | jq -r 'keys|.[]' > package-names.txt

❯ head -n 10 package-names.txt
legacyPackages.x86_64-linux.AMB-plugins
legacyPackages.x86_64-linux.ArchiSteamFarm
legacyPackages.x86_64-linux.AusweisApp2
legacyPackages.x86_64-linux.CHOWTapeModel
legacyPackages.x86_64-linux.ChowKick
legacyPackages.x86_64-linux.CoinMP
legacyPackages.x86_64-linux.CuboCore.coreaction
legacyPackages.x86_64-linux.CuboCore.corearchiver
legacyPackages.x86_64-linux.CuboCore.corefm
legacyPackages.x86_64-linux.CuboCore.coregarage
```

> 😑 Super annoying that these new Nix commands even with _-L_ continue to write the text in-place for their log output.

## 🎯 Goal 2: Compute outPaths for every package

Since we are using _nix search_ the names of the packages are now following the Flakes naming convention with prefixing them with _legacyPackages_.

The plan here to continue with the new Nix commands and now evaluate the _outPath_ of each package.

⚠️ This does not build the derivation.

```bash
❯ cat package-names.txt | \
xargs -I'{}' sh -c \
'nix eval --raw ".#{}.outPath" >> outpaths.txt; echo >> outpaths.txt'

❯ head -n 10 outpaths.txt
/nix/store/jrvzirqlzpylxxij8q10hramdsgk6nvx-AMB-plugins-0.8.1
/nix/store/szh7aikwz12vj1sbkf4r6vdvy1k8apym-archisteamfarm-5.1.5.3
/nix/store/mxi5pignri1z8n3lizkcp8y8m8cgfn55-AusweisApp2-1.22.2
/nix/store/6d69d3lbk6dbgqnvzccx9lpi7hj3f6i9-CHOWTapeModel-2.10.0
/nix/store/lhk99h3adbfhzdk1spcx7awky7bzhwab-ChowKick-1.1.1
/nix/store/6p5g08rrq4cf5yrs970h4qrv7drj812l-CoinMP-1.8.4
/nix/store/qlxs8yrmssi1x54a5m3q0941ha4qvaa8-coreaction-4.2.0
/nix/store/64r6kkd6cxm1jhlhl9zma80jgvidrfyw-corearchiver-4.2.0
/nix/store/mh79zi4l343fj1xa54p1a4qif38f4435-corefm-4.2.0
/nix/store/6disqp58dkyi8i3vpb6ja5sr8g4xpqxg-coregarage-4.2.0
```

⚠️ I could not seem to make this _parallel_ at all since the evaluation requires a global lock.

Now I just need to rename _outpaths.txt_ to something that indicates the Git commit I used when generating this and I am starting to
build some nice structure data 📊.

## Bonus Work and Collaboration

Of course what I am doing here is only generating for my current _builtins.currentSystem_ (i.e. x86_64) and will not generate for all other supported platforms.

There are also recursive subtrees within _nixpkgs_ such as _pkgsStatic_ or _pkgsMusl_ that I don't believe are returned from _nix search_ and therefore I am not
detecting those output paths.

I would like to continue to understand better how tools such as Hydra generate all attributes for all systems.

If this problem and goal to build an _outputPath_ reverse index for Nix sounds interesting, reach out to [me](mailto:farid.m.zakaria@gmail.com)!
I would love to collaborate.