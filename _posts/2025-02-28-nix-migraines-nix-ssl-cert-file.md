---
layout: post
title: 'Nix migraines: NIX_SSL_CERT_FILE'
date: 2025-02-28 19:07 -0800
---

> This will be a self-post to describe [nixpkgs#issue385955](https://github.com/NixOS/nixpkgs/issues/385955). I refused to just "copy code" from other packages and wanted to better understand what was going on.

If you're on a "proper" operating system (i.e. Linux), Nix protects you from accidental impurities by enforcing a filesystem **and network** sandbox.

_This is not the case in MacOS._ You can optionally enable the sandbox but it **does not include a network** sandbox.

> 🤔 I have some pretty strong opinions here. Although I am using Nix on MacOS, I would advocate for Nix/Nixpkgs *dropping* MacOS (& eventual Windows/BSD) support. Constraints are when you can find simplicity and beauty.

I had packaged up my personal blog (_this site right here!_ 📝) into a [flake.nix](https://github.com/fzakaria/fzakaria.com/blob/7b6e7621a25bfef0bd64bb88e7885b6f68545cd6/flake.nix) that worked on Linux but was failing on MacOS.