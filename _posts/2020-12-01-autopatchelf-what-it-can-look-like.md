---
layout: post
title: autopatchelf - what it can look like
date: 2020-12-01 21:18 -0800
excerpt_separator: <!--more-->
---

> This is a follow up post to my previous one to [on-demand linked libraries for NixOS]({% post_url 2020-11-17-on-demand-linked-libraries-for-nix %}).

I previously wrote about the work into a new NixOS tool [nix-ld](https://github.com/Mic92/nix-ld), which will allow the possibility of hot-patching the linking of dynamic libraries.

At the moment the goal of the tool is modest in allowing modification of the library search path via a custom environment variable _NIX_LD_LIBRARY_PATH_.

> I'm minimizing the task as there's a ton of complexity, such as not loading in a different glibc and other subtleties -- ask [Mic92](https://github.com/Mic92) about it on [#nixos](irc://irc.freenode.net/#nixos)!

I finished with a bit of a _teaser_ on what a full-fledged tool may look like...

<!--more-->

### autopatchelf

[autopatchelf](https://github.com/fzakaria/autopatchelf) is my _work in progress_ in what the other half of on-demand linked libraries may look & feel like.

> Don't judge me on the code, it's still in exploratory phase. 👨‍⚖️

It's goal is quite simple and works in tandem with [nix-ld](https://github.com/Mic92/nix-ld). _autopatchelf_ attempts to locate a valid _/nix/store_ entry for every required library required by the binary.

An _asciinema_ is worth a thousand words.

> Here is a small example of how running _autopatchelf_ will prompt the user to select the most appropriate matching library for the Ruby binary. It's pretty quick..

<script id="asciicast-376182" src="https://asciinema.org/a/376182.js" async data-speed="0.5"></script>

Once the libraries are chosen, it's _mostly_ a straightforward invocation to [nix-ld](https://github.com/Mic92/nix-ld) with the set _NIX_LD_LIBRARY_PATH_ environment variable.

#### Challenges

I already foresee a few challenges (all solvable!) that need to be addressed for a thorough solution which I want to articulate here for others that might want to pursue this idea.

1. A garbage-collection root must be created for all realised _/nix/store_ entries. This is to avoid the chosen libraries from being garbage-collected during process run.

2. [autopatchelf](https://github.com/fzakaria/autopatchelf) will try to normalize or find closest matching libraries if a non-exact match can be found. The ELF binary itself then must be patched to set the selected names.

3. Solving for diamond dependencies must be performed. For instance, the selected glibc version must match the same one used in all the selected _/nix/store_ paths. It may be necessary to build a depth-first graph of selected libraries.

4. A cache file "fingerprint" of the selected libraries can be saved for the binary so that subsequent startups are faster.

5. An option to directly edit the ELF binary rather than supply the _NIX_LD_LIBRARY_PATH_ variable should be possible.

The long-term vision is anyone can either start any non-NixOS binary if this functionality is directly embedded within the _ld_ interpreter, patch the ELF binary interactively for the required libraries or even ship the "fingerprint" file alongside the binary for others to consume.

There's a lot of promise in the idea especially for unlocking cases where users may lean on [buildFHSUserEnv](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments).

If you'd like to work on this together reach out to me or contribute at <https://github.com/fzakaria/autopatchelf>