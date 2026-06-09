---
layout: post
title: Relocatable Derivations
date: 2026-06-08 20:39 -0700
---

The [earlier post]({% post_url 2026-06-05-the-guix-nix-abomination-leveraging-guix-derivations-in-nix %}) on [guix-transfer](https://github.com/fzakaria/guix-transfer) highlighted how we can use the tool to transfer derivations from `/gnu/store` to `/nix/store`.

It is always delightful when someone offers deeper insights into an idea I had put forward.

I was so focused on the transfer from derivations from Guix, I failed to see the larger applicability of the tool.

[@tomberek](https://github.com/tomberek) shared with me the insight that the tool can be generalized to: _"transfer derivations between realms"_.

Relocatable derivations. 💥

What does that mean?

Perhaps the clearest concept to apply it to are _deployments_.

You might have a derivation `FooBar.drv` that you want to propagate through cascading deployment tiers: alpha, beta, and prod.

You might have needed to painstakingly apply some logical firewall if all three _realms_ used `/nix/store` as their prefix to gate your deployment.

By changing the prefix of each one, i.e. `/beta/store` or `/prod/store`, they are naturally segregated in Nix.

How do we promote derivations from one _realm_ to another?

We could re-evaluate the Nix expression again against each new store or we can leverage [guix-transfer](https://github.com/fzakaria/guix-transfer).

Why is this better than doing `NIX_STORE_DIR=/prod/store nix-instantiate` against these new store directories?

What is our source of truth? The Nix files or the derivations?

I _posit_ that the derivations themselves are the source of truth.

Furthermore, evaluation could be slow and requires the full source code (Nix expressions) and the entire evaluation environment (i.e. Nixpkgs, plugins, and overlays).

By relocating at the derivation level, we move from **Evaluation-based deployment** (which is slow, requires source access, and may be prone to evaluation-time impurities potentially) to a **Plan-based deployment**.

We now treat the build graph, via the derivations, as a portable artifact that can be relocated into any realm, regardless of whether that realm has the source code, the right version of Nixpkgs, or in the case of Guix, even speaks the same front-end language.
