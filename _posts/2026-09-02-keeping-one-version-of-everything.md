---
layout: post
title: 'Keeping one version of everything'
date: 2026-09-02 12:00 -0700
---

After [the last post]({% post_url 2026-09-01-the-holy-grail-of-nixpkgs-version-ranges %}) introduced _the holy grail_ of version ranges for nixpkgs, [@arianvp](https://github.com/arianvp) over [X](https://x.com/ProgrammerDude/status/2095052917426298981) felt it was a doomed endeavor: "What happens when a plan spans revisions and you accidentally load two versions of the same library? DOOMED." 💀

He was right to be skeptical. The diamond dependency problem is a truly nasty one. I am however determined to add enough safeguards to make it a _safe_ endeavor. The first step is to make sure that the solver never produces a plan that mixes versions of the same library in one process image, _when requested_.

The general shape of the diamond problem: you link `libfoo-2` and `libbar-1`, but `libbar-1` links `libfoo-1`. Now your process carries both libfoos, and only one symbol can win.

[![the diamond dependency problem: your app links libfoo-2 and libbar-1, libbar-1 links libfoo-1, one process carries both libfoos](/assets/images/grail-diamond.svg)](/assets/images/grail-diamond.svg){: style="--image-width: 26rem"}


He provided an example that happened in Nixpkgs itself. [`fluent-bit`](https://fluentbit.io/) vendored one [`zstd`](https://github.com/facebook/zstd) and linked against libsystemd, which `dlopen` another `zstd` for compressed logging. `zstd` is not ABI compatible across versions like `glibc`, so the two disagreed on struct layout, and logging corrupted the address space. Two versions of one library in one process is a crash. 💥[^fluentbit-vendor]

[^fluentbit-vendor]: Turns out the bug is even more outlandish because `fluent-bit` vendored `zstd` itself breaking Nix's ability to reason about the graph at all.

## Sidestepping the problem

Nixpkgs generally sidesteps this problem by virtue of its coherency philosophy: everything is built against a single revision so the diamond dependency problem _generally_ does not arise.[^fluentbit-bug] The problem arises when you deliberately mix revisions.

[^fluentbit-bug]: The [fluent-bit#10139](https://github.com/fluent/fluent-bit/issues/10139) bug was itself an outlier within Nixpkgs.

Nix itself however can support, and was designed for, multiple revisions across processes. Each binary points to its own libraries through the `RUNPATH` at the `/nix/store`/, and they never collide.

The problem is only exposed when we are deliberately mixing revisions in one process image. Within a `^` coexistence group, `grail` already dodges this problem by virtue of its design: it also
forces the attributes to be coherent _to a single_ revision.

If you are using `grail lock` to import top-level binaries into your configuration, you are safe **no matter what**. This is what Nix was designed for!

If however you are using `mkDerivation` to build packages with attributes you locked, you might be mixing shared libraries across revisions, if you don't force a coexistence group `^`, and might have had a bad time. I have a solution for you below! 🙌

## Coherence constraints

The `grail` tool generalizes the `glibc` constraint from the last post to any library, and it turned out to need no new data at all.

The tool now supports a `--one <attr>` flag that demands every chosen revision fall in _one era_ of the given attribute.
For instance, `--one zstd` demands every chosen revision picked to solve the query must have shipped the same `zstd` version. The solver will refuse to mix revisions that ship different versions of `zstd`, and will report exactly what would have mixed.

Here is the same query `python3@3.10.* postgresql@13.*` with and without `--one zstd --one openssl`. You can see that the solver picks versions of each such that there is only one `zstd` and one `openssl` version.

```console?comments=true
# free: python at its freshest, sixteen months after postgresql 13
# died. glibc is RESOLVED, not constrained: the newest spanned era
# serves every input via symbol versioning
$ grail solve 'python3@3.10.* postgresql@13.*'
2 revisions
  2022-05-20-dfd82985c273  (2022-05-20, r771)
    postgresql 13.6
  2023-10-19-7c9cc5a6e5d3  (2023-10-19, r1128)
    python3 3.10.12
  glibc: 2.37 serves every input (eras spanned: 2.34, 2.37)

# one zstd, one openssl: python retreats until every library agrees —
# and glibc lands on one era for free
$ grail solve 'python3@3.10.* postgresql@13.*' --one zstd --one openssl
2 revisions
  2022-05-20-dfd82985c273  (2022-05-20, r771)
    postgresql 13.6
  2022-06-26-f2537a505d45  (2022-06-26, r793)
    python3 3.10.4
  zstd: 1.5.2
  openssl: 1.1.1o
  glibc: 2.34
```

This causes the chosen `python3` to retreat to an earlier revision to satisfy the `zstd` and `openssl` coherency.

[![postgresql 13 and python 3.10 lifetimes over the glibc, zstd and openssl eras; the coherence window ends 2022-06-26, where the plan pins python 3.10.4](/assets/images/grail-eras.svg)](/assets/images/grail-eras.svg)

When no coherent plan exists, the solver names exactly what would have mixed:

```console
$ grail solve 'ffmpeg@5.* nodejs@16.*' --one zstd --one openssl
unsatisfiable: satisfiable only by mixing zstd 1.5.2/1.5.5,
openssl 1.1.1q/3.0.10; --one forbids that
```

You can run these examples directly in the browser at [fzakaria.github.io/grail](https://fzakaria.github.io/grail/) which includes some precanned examples and the ability to select `--one` attributes.
The plan graph draws each library as its own node, so a coherent plan is visible at a glance: every revision converging on a single node per library.

## What it promises, and what it cannot

Precision matters here. `--one zstd` guarantees **version-level ABI agreement**: every chosen revision ships the same `zstd` version, so no plan can hand you a mix of two different versions.

It does not guarantee that they consolidate to the same commit or even `/nix/store` path. Two revisions can ship the same version as different rebuilds if anything in their closure changed

If you want to guarantee one path, you need to use `^` to force a single revision.

We can go even further too! Some libraries, notably `glibc`, have backwards compatibility guarantees across versions. The solver can reason about this and allow a plan to mix versions of `glibc` that are compatible, but not mix incompatible versions. That can make the solver much more flexible which is something I am keen to explore.

Building software always _contains dragons_, the only difference is our ability to reason through them. I am personally enjoying throwing a SAT solver at the problem and seeing what I can reliably cook up.