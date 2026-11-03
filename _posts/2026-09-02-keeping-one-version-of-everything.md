---
layout: post
title: 'Keeping one version of everything'
date: 2026-09-02 12:00 -0700
---

After [the last post]({% post_url 2026-09-01-the-holy-grail-of-nixpkgs-version-ranges %}) introduced _the holy grail_ of version ranges for nixpkgs, [@arianvp](https://github.com/arianvp) over [X](https://x.com/ProgrammerDude/status/2095052917426298981) felt it was a doomed endeavor: "What happens when a plan spans revisions and you accidentally load two versions of the same library? DOOMED." 💀

He was right to be skeptical. The diamond dependency problem is a truly nasty one. I am however determined to add enough safeguards to make it a _safe_ endeavor. The first step is to make sure that the solver never produces a plan that mixes versions of the same library in one process image, _when requested_.

The general shape of the diamond problem: you link `libfoo-2` and `libbar-1`, but `libbar-1` links `libfoo-1`. Now your process carries both libfoos, and only one symbol can win.

<figure>
<svg class="grail-diamond" viewBox="0 0 480 330" width="480" height="330" role="img"
     style="display:block;margin-inline:auto"
     aria-label="the diamond dependency problem: your app links libfoo-2 and libbar-1, libbar-1 links libfoo-1, one process carries both libfoos">
<style>
  .grail-diamond text { font-family: var(--mono, "JetBrains Mono", ui-monospace, Menlo, Consolas, monospace); font-size: 13px; fill: var(--ink, #1a1815); }
  .grail-diamond .node { fill: none; stroke: var(--rule-strong, #c2b9a6); }
  .grail-diamond .bad { fill: #cf5d2829; stroke: #cf5d28; }
  .grail-diamond .edge { stroke: var(--ink-faint, #6f685b); fill: none; }
  .grail-diamond .arrow { fill: var(--ink-faint, #6f685b); stroke: none; }
  .grail-diamond .clash { stroke: #cf5d28; stroke-dasharray: 5 4; fill: none; }
  .grail-diamond .clashtext { fill: #cf5d28; font-size: 12px; }
  .grail-diamond .caption { fill: var(--ink-muted, #565046); font-size: 12px; }
</style>

<!-- nodes -->
<rect class="node" x="186" y="14" width="108" height="34" rx="8"/>
<text x="240" y="36" text-anchor="middle">your app</text>

<rect class="bad" x="62" y="112" width="118" height="34" rx="8"/>
<text x="121" y="134" text-anchor="middle">libfoo-2</text>

<rect class="node" x="296" y="112" width="118" height="34" rx="8"/>
<text x="355" y="134" text-anchor="middle">libbar-1</text>

<rect class="bad" x="296" y="216" width="118" height="34" rx="8"/>
<text x="355" y="238" text-anchor="middle">libfoo-1</text>

<!-- link edges -->
<path class="edge" d="M 214 48 C 180 70, 150 88, 130 106"/>
<path class="arrow" d="M 126 100 L 128 111 L 136 103 Z"/>
<path class="edge" d="M 266 48 C 300 70, 330 88, 350 106"/>
<path class="arrow" d="M 344 103 L 352 111 L 354 100 Z"/>
<path class="edge" d="M 355 146 L 355 209"/>
<path class="arrow" d="M 351 202 L 355 212 L 359 202 Z"/>

<!-- the collision -->
<path class="clash" d="M 140 150 C 180 210, 240 236, 289 236"/>
<text class="clashtext" x="52" y="262">same symbols,</text>
<text class="clashtext" x="52" y="278">different structs</text>

<text class="caption" x="240" y="308" text-anchor="middle">one process image: only one symbol can win</text>
</svg>
</figure>


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

<figure>
<svg class="grail-eras" viewBox="0 0 600 281" width="600" height="281" role="img"
     style="display:block;margin-inline:auto"
     aria-label="postgresql 13 and python 3.10 lifetimes over the glibc, zstd and openssl eras; the coherence window ends 2022-06-26, where the plan pins python 3.10.4">
<style>
  .grail-eras { font-family: var(--mono, "JetBrains Mono", ui-monospace, Menlo, Consolas, monospace); }
  .grail-eras text { font-size: 12px; fill: var(--ink-muted, #565046); }
  .grail-eras .head { font-size: 13px; font-weight: 600; fill: var(--ink, #1a1815); }
  .grail-eras .grid { stroke: var(--rule, #dcd5c5); stroke-width: 1; }
  .grail-eras .hit { fill: #2a78d6; }
  .grail-eras .era { fill: var(--ink-faint, #6f685b); opacity: .35; }
  .grail-eras .era.odd { opacity: .55; }
  .grail-eras .etext { fill: var(--ink, #1a1815); font-size: 11px; }
  .grail-eras .win { fill: #cf5d28; opacity: .16; }
  .grail-eras .wtext { fill: #cf5d28; font-size: 12px; }
  .grail-eras .pin { fill: #cf5d28; stroke: var(--paper, #f5f2ec); stroke-width: 1.5; }
  .grail-eras .free { fill: none; stroke: var(--ink-faint, #6f685b); stroke-width: 2; }
  .grail-eras .arrow { stroke: #cf5d28; stroke-width: 1.4; fill: none; }
</style>
<line class="grid" x1="92.0" y1="68" x2="92.0" y2="251"/>
<text x="92.0" y="267" text-anchor="middle">2022-01</text>
<line class="grid" x1="216.0" y1="68" x2="216.0" y2="251"/>
<text x="216.0" y="267" text-anchor="middle">2022-07</text>
<line class="grid" x1="342.0" y1="68" x2="342.0" y2="251"/>
<text x="342.0" y="267" text-anchor="middle">2023-01</text>
<line class="grid" x1="466.0" y1="68" x2="466.0" y2="251"/>
<text x="466.0" y="267" text-anchor="middle">2023-07</text>
<line class="grid" x1="592.0" y1="68" x2="592.0" y2="251"/>
<text x="592.0" y="267" text-anchor="end">2024-01</text>
<rect class="win" x="179.7" y="68" width="32.9" height="183"/>
<text class="wtext" x="220.5" y="150">every era agrees: 2022-05-09 → 2022-06-26</text>
<text class="wtext" x="220.5" y="166">(openssl 1.1.1o is the wall)</text>
<rect class="hit" x="92" y="20" width="18" height="7" rx="3.5"/>
<text x="116" y="28">requested attr lifetime</text>
<rect class="era odd" x="342" y="18" width="18" height="11"/>
<text x="366" y="28">library eras</text>
<text class="head" x="84" y="87" text-anchor="end">postgresql</text>
<rect class="hit" x="92.0" y="78" width="95.2" height="9" rx="3.5"/>
<text class="head" x="84" y="113" text-anchor="end">python3</text>
<rect class="hit" x="207.8" y="104" width="333.6" height="9" rx="3.5"/>
<circle class="free" cx="541.3" cy="108.5" r="4"/>
<circle class="pin" cx="212.5" cy="108.5" r="4.5"/>
<path class="arrow" d="M 541.3 102.5 C 541.3 64.0, 212.5 64.0, 214.5 101.5" marker-end="url(#grail-eras-tip)"/>
<defs><marker id="grail-eras-tip" markerWidth="7" markerHeight="7" refX="5" refY="3.5" orient="auto"><path d="M0,0 L7,3.5 L0,7 z" fill="#cf5d28"/></marker></defs>
<text class="wtext" x="376.9" y="58.0" text-anchor="middle">--one zstd --one openssl retreats python 16 months</text>
<text x="212.5" y="128.5" text-anchor="middle">3.10.4 (r793)</text>
<text x="541.3" y="128.5" text-anchor="middle">3.10.12 (r1128)</text>
<text class="head" x="84" y="190" text-anchor="end">glibc</text>
<rect class="era" x="92.0" y="176" width="63.0" height="17"/>
<text class="etext" x="123.5" y="190" text-anchor="middle">2.33</text>
<rect class="era odd" x="157.1" y="176" width="81.5" height="17"/>
<text class="etext" x="197.8" y="190" text-anchor="middle">2.34</text>
<rect class="era" x="238.6" y="176" width="171.9" height="17"/>
<text class="etext" x="324.5" y="190" text-anchor="middle">2.35</text>
<rect class="era odd" x="411.2" y="176" width="130.1" height="17"/>
<text class="etext" x="476.2" y="190" text-anchor="middle">2.37</text>
<rect class="era" x="544.7" y="176" width="47.3" height="17"/>
<text class="head" x="84" y="216" text-anchor="end">zstd</text>
<rect class="era" x="92.0" y="202" width="15.8" height="17"/>
<rect class="era odd" x="108.4" y="202" width="10.3" height="17"/>
<rect class="era" x="119.4" y="202" width="260.3" height="17"/>
<text class="etext" x="249.5" y="216" text-anchor="middle">1.5.2</text>
<rect class="era odd" x="380.4" y="202" width="39.7" height="17"/>
<rect class="era" x="420.8" y="202" width="171.2" height="17"/>
<text class="etext" x="506.4" y="216" text-anchor="middle">1.5.5</text>
<text class="head" x="84" y="242" text-anchor="end">openssl</text>
<rect class="era" x="92.0" y="228" width="4.1" height="17"/>
<rect class="era odd" x="97.5" y="228" width="43.8" height="17"/>
<rect class="era" x="145.4" y="228" width="31.5" height="17"/>
<rect class="era odd" x="179.7" y="228" width="32.9" height="17"/>
<rect class="era" x="213.2" y="228" width="14.4" height="17"/>
<rect class="era odd" x="228.3" y="228" width="37.7" height="17"/>
<rect class="era" x="266.7" y="228" width="32.9" height="17"/>
<rect class="era odd" x="300.9" y="228" width="69.9" height="17"/>
<text class="etext" x="335.8" y="242" text-anchor="middle">3.0.7</text>
<rect class="era" x="371.5" y="228" width="76.0" height="17"/>
<text class="etext" x="409.5" y="242" text-anchor="middle">3.0.8</text>
<rect class="era odd" x="448.2" y="228" width="51.4" height="17"/>
<text class="etext" x="473.8" y="242" text-anchor="middle">3.0.9</text>
<rect class="era" x="500.9" y="228" width="40.4" height="17"/>
<rect class="era odd" x="544.7" y="228" width="14.4" height="17"/>
<rect class="era" x="561.2" y="228" width="30.8" height="17"/>
</svg>
</figure>

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