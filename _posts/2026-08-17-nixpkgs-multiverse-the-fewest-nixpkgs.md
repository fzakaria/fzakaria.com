---
layout: post
title: 'nixpkgs-multiverse: the fewest nixpkgs'
date: 2026-08-17 10:15 -0700
---

If you have not seen my previous posts, I have been working on [nixpkgs-multiverse]({% post_url 2026-08-09-nixpkgs-multiverse-every-version-that-ever-existed %}). It is a tool that lets you pin any package to any version it ever shipped, from one flake input.[^website]

[^website]: [nixpkgs-multiverse](https://nixmultiverse.com/) sitis a nice website that makes the data browseable.

You can specify a set of pins by release, commit or version.
By version is particularly useful because it lets you pin packages to a version you might not want to update while still getting the latest of everything else.

```nix
multiverse.pins = {
  ripgrep = "13.0.0";
  fd = "8.7.0";
  jq = "1.6";
  hello = "2.12.1";
};
```

In the worst case, each of those resolves on its own, against whichever revision last shipped that version. They are four different revisions, so that configuration is **four** Nixpkgs trees fetched and evaluated.

The cost of the multiverse has never been per package. It is per *revision touched*. Asking for five packages out of one revision only costs the one revision; asking for five packages out of five revisions and you pay five times.

It would be useful however to minimize the number of Nixpkgs revisions fetched and evaluated. I thought this was a SAT problem (NP-Complete) however the problem turns out to be simpler and solvable in polynomial time, _with a small caveat_.

## Pins are intervals

A version is not a point in Nixpkgs history, it is a *stretch*. `ripgrep` was at 13.0.0 from June 2021 until November 2023 throughout 541 consecutive channel bumps where `pkgs.ripgrep.version` returned exactly that string.

Every pin is a contiguous block on one axis, and a revision *serves* a pin if it lands inside that pin's block.

**What is the fewest points that touch every block?**

<figure>
<svg viewBox="0 0 760 366" role="img"
     style="display:block;margin-inline:auto;max-width:100%;height:auto;font-family:var(--mono)"
     aria-label="Six pins drawn as blocks on the revision axis, spaced for legibility rather than to scale. Sorted by where each block ends, the sweep places a revision at the end of the earliest-ending unserved block: jq forces the first, neovim forces the second. Those two blocks never overlap, which is why two revisions is the minimum. hello is served by both and joins the newer.">
  <g stroke="#b1201d" stroke-width="1.5" stroke-dasharray="4 4" opacity="0.85">
    <line x1="342" y1="48" x2="342" y2="258"/>
    <line x1="598" y1="48" x2="598" y2="258"/>
  </g>
  <g fill="currentColor" font-size="15" text-anchor="middle" font-weight="600">
    <text x="342" y="36">revision 1</text>
    <text x="598" y="36">revision 2</text>
  </g>

  <g fill="currentColor" font-size="15" text-anchor="end">
    <text x="140" y="79">jq 1.6</text>
    <text x="140" y="113">fd 8.7.0</text>
    <text x="140" y="147">ripgrep 13.0.0</text>
    <text x="140" y="181">neovim 0.10.4</text>
    <text x="140" y="215">hello 2.12.1</text>
    <text x="140" y="249">helix 25.01.1</text>
  </g>

  <rect x="150" y="68"  width="192" height="12" rx="6" fill="#b1201d"/>
  <rect x="214" y="102" width="224" height="12" rx="6" fill="#4c72b0"/>
  <rect x="278" y="136" width="256" height="12" rx="6" fill="#4c72b0"/>
  <rect x="406" y="170" width="192" height="12" rx="6" fill="#b1201d"/>
  <rect x="214" y="204" width="448" height="12" rx="6" fill="#4c72b0"/>
  <rect x="502" y="238" width="160" height="12" rx="6" fill="#4c72b0"/>

  <g fill="currentColor">
    <circle cx="342" cy="74"  r="5"/>
    <circle cx="342" cy="108" r="5"/>
    <circle cx="342" cy="142" r="5"/>
    <circle cx="598" cy="176" r="5"/>
    <circle cx="598" cy="210" r="5"/>
    <circle cx="598" cy="244" r="5"/>
  </g>
  <text x="352" y="276" fill="currentColor" font-size="14" opacity="0.85">hello is served by both, and joins the newer</text>

  <line x1="150" y1="298" x2="726" y2="298" stroke="currentColor" stroke-width="1" opacity="0.35"/>
  <g fill="currentColor" font-size="14" opacity="0.85">
    <text x="150" y="317">older revisions</text>
    <text x="726" y="317" text-anchor="end">newer revisions</text>
  </g>

  <g fill="#b1201d">
    <rect x="150" y="333" width="192" height="3" rx="1.5"/>
    <rect x="406" y="333" width="192" height="3" rx="1.5"/>
  </g>
  <text x="438" y="357" fill="currentColor" font-size="14" opacity="0.85" text-anchor="middle">the two blocks that forced a revision never overlap &#8212; so no plan smaller than 2 exists</text>
</svg>
</figure>


In the example above, six pins require at a minimum two revisions. The dashed lines are the Nixpkgs that actually get fetched, the dots are where each pin ends up, and the red blocks are the two pins that decided it.

## The sweep

Turns out the algorithm is relatively simple once we visualize it.
It is the opposite to **interval partitioning** (i.e. fewest meeting rooms), we are doing **activity selection**.

We sort the pins by where their block **ends**. Walk them in that order. If the last revision you placed does not reach the block in front of you, place a new one at that block's end.


```python
# blocks[i] = (first, last), one pin's stretch of revisions
SWEEP(blocks):
  order  = indices 0..n, sorted by blocks[i].last ascending
  # the revisions we will actually fetch
  chosen = []

  for i in order:
    (first, last) = blocks[i]

    if chosen and chosen[-1] >= first:
      # a revision we already placed falls inside this pin's block
      continue

    # unserved, place a revision at the end of its block
    chosen.append(last)

  return chosen
```

The algorithm is effectively a sort plus one pass: `O(n log n)`. Happily we did not need a solver, z3, or backtracking. It is not approximation either, we get the optimal solution.

How much can this help?

Here is a simulation of the sweep over random pin sets of various sizes, drawn from the real index. The sweep is run three times: once with one revision per pin, once minimised over any era, and once minimised over recent versions.

```plotnine
import pandas as pd
from plotnine import *

# Simulated over the real index (index/history.json, 1,532 revisions):
# 400 random pin sets at each size, run through the same sweep mvs ships.
#
# "any era" draws versions uniformly from all fourteen years, which is the
# adversarial case. "recent versions" draws from roughly the last three years,
# which is what people actually pin.
df = pd.DataFrame({
    "pins": [2, 3, 5, 8, 12, 16, 20, 30] * 3,
    "revisions": [2, 3, 5, 8, 12, 16, 20, 30]
               + [1.9, 2.7, 4.2, 6.2, 8.6, 10.8, 12.6, 17.1]
               + [1.6, 2.1, 3.1, 4.2, 5.5, 6.7, 7.8, 9.9],
    "how": ["one revision per pin"] * 8
         + ["minimised, any era"] * 8
         + ["minimised, recent versions"] * 8,
})

plot = (
    ggplot(df, aes("pins", "revisions", color="how"))
    + geom_line(size=1.0)
    + geom_point(size=1.8)
    + scale_color_manual(values={"one revision per pin": "#8a8580",
                                 "minimised, any era": "#4c72b0",
                                 "minimised, recent versions": "#b1201d"},
                         name="")
    + labs(x="packages pinned", y="Nixpkgs fetched and evaluated")
    + theme(legend_position="top", legend_title=element_blank())
)
plot.width, plot.height = 7.0, 3.6
```

We are able to reduce the number of Nixpkgs revisions fetched from thirty to ten for thirty pins of recent versions. The same thirty package versions, but only ten revisions fetched and evaluated.

> **Tip**
> This matters much less if you are on the [fast path]({% post_url 2026-08-14-nixpkgs-multiverse-fast-mode %}). A pin the store-path index knows costs no fetch at all as it is immediately substituted from [cache.nixos.org](https://cache.nixos.org/).
{: .alert .alert-tip}

## The Receipt

Every revision the sweep places was placed *because* of one specific pin, the one it could not reach. Those pins are pairwise disjoint, meaning they never overlap. **k disjoint pins need k distinct revisions.** 

We expose this information via a "plan" that is viewable from
the `mvs` CLI or the Nix API. It is a certificate that the solution is optimal, and it is also useful for debugging.

```console
$ mvs solve jq@1.6 fd@8.7.0 ripgrep@13.0.0 \
            hello@2.12.1 neovim@0.10.4 helix@25.01.1
2 revisions · minimal
5 of 6 pins served by the store-path index

ATTR     VERSION  REVISION      DATE        MOVED
jq       1.6      6500b4580c2a  2023-09-25
fd       8.7.0    6500b4580c2a  2023-09-25  24 days (9 revs)
ripgrep  13.0.0   6500b4580c2a  2023-09-25  59 days (20 revs)
hello    2.12.1   698214a32beb  2025-03-25  56 days (27 revs)
neovim   0.10.4   698214a32beb  2025-03-25
helix    25.01.1  698214a32beb  2025-03-25  111 days (47 revs)

  minimal: jq 1.6.x and neovim 0.10.4.x never overlapped
```

The sweep might place a particular version earlier than the last revision that shipped it which is highlighted by the `MOVED` column.

## The caveat

The problem is solvable in polynomial time, but only if every pin is contiguous. If a pin has holes in it, the problem becomes NP-Complete.

In practice though versions do have holes. A package gets dropped from Nixpkgs and comes back at the same version albeit very uncommon.[^hole] The sweep above does not know which stretch to use, and it is possible that the wrong choice will force a second revision.

[^hole]: About **1.7%** of all `(attribute, version)` pairs in the index have such holes.

A hole turns one decision into two:

1. **which revisions do we place?**
2. **which stretch of each pin do we aim at?**

For instance, suppose `foo` shipped 1.0, lost it, and got it back later for two stretches. `bar` 2.0 was only ever current during the first of them.

<figure>
<svg viewBox="0 0 760 330" role="img"
     style="display:block;margin-inline:auto;max-width:100%;height:auto;font-family:var(--mono)"
     aria-label="Two pins. foo 1.0 shipped, was dropped, and came back, so it has two stretches; bar 2.0 overlaps only the earlier one. If foo is held to its newest stretch, nothing overlaps and the plan needs two revisions. If foo may use its earlier stretch, one revision serves both. Which stretch foo should use cannot be decided by looking at foo.">
  <text x="20" y="30" fill="currentColor" font-size="15" font-weight="600">foo must use its newest stretch</text>
  <text x="740" y="30" fill="#b1201d" font-size="15" font-weight="600" text-anchor="end">2 revisions</text>

  <g stroke="#b1201d" stroke-width="1.5" stroke-dasharray="4 4" opacity="0.85">
    <line x1="400" y1="48" x2="400" y2="126"/>
    <line x1="660" y1="48" x2="660" y2="126"/>
  </g>
  <g fill="currentColor" font-size="15" text-anchor="end">
    <text x="150" y="79">foo 1.0</text>
    <text x="150" y="115">bar 2.0</text>
  </g>
  <rect x="180" y="68"  width="140" height="12" rx="6" fill="#4c72b0" fill-opacity=".16"
        stroke="#4c72b0" stroke-opacity=".55" stroke-width="1" stroke-dasharray="3 3"/>
  <rect x="500" y="68"  width="160" height="12" rx="6" fill="#4c72b0"/>
  <rect x="230" y="104" width="170" height="12" rx="6" fill="#4c72b0"/>
  <g fill="#b1201d">
    <circle cx="660" cy="74"  r="5"/>
    <circle cx="400" cy="110" r="5"/>
  </g>

  <line x1="20" y1="160" x2="740" y2="160" stroke="currentColor" stroke-width="1" opacity="0.25"/>

  <text x="20" y="196" fill="currentColor" font-size="15" font-weight="600">foo may use its earlier stretch</text>
  <text x="740" y="196" fill="#b1201d" font-size="15" font-weight="600" text-anchor="end">1 revision</text>

  <g stroke="#b1201d" stroke-width="1.5" stroke-dasharray="4 4" opacity="0.85">
    <line x1="320" y1="214" x2="320" y2="292"/>
  </g>
  <g fill="currentColor" font-size="15" text-anchor="end">
    <text x="150" y="245">foo 1.0</text>
    <text x="150" y="281">bar 2.0</text>
  </g>
  <rect x="180" y="234" width="140" height="12" rx="6" fill="#4c72b0"/>
  <rect x="500" y="234" width="160" height="12" rx="6" fill="#4c72b0" fill-opacity=".16"
        stroke="#4c72b0" stroke-opacity=".55" stroke-width="1" stroke-dasharray="3 3"/>
  <rect x="230" y="270" width="170" height="12" rx="6" fill="#4c72b0"/>
  <g fill="#b1201d">
    <circle cx="320" cy="240" r="5"/>
    <circle cx="320" cy="276" r="5"/>
  </g>

  <text x="380" y="320" fill="currentColor" font-size="14" opacity="0.85" text-anchor="middle">nothing about <tspan font-style="italic">foo</tspan> says which stretch to use, only <tspan font-style="italic">bar</tspan> does</text>
</svg>
</figure>

Depending on which stretch of `foo` you choose, the plan is either one or two revisions. The choice of which stretch to use cannot be made by looking at `foo` alone, only by looking at `bar`.

This turns each decision into two, causing the algorithmic complexity to become exponential in the number of holed pins. The problem is NP-Complete, and it is equivalent to [vertex cover](https://en.wikipedia.org/wiki/Vertex_cover).


This is the part I got wrong. I looked at the problem and saw constraints being satisfied, which I pattern-matched to SAT. 

Turns out by by not having a second choice, we get to stay in polynomial time. The fix is to not have a second choice. A pin is defined to take the **newest** of its stretches and only that one which simplifies our problem. Our greedy algorithm is now optimal.

## Minor footgun

Grouping pins pulls some of them *backwards*. From our example above: `helix 25.01.1` is picked earlier than the last revision that shipped it in order to group with `neovim 0.10.4`.

What does this mean in practice?

Although a version is a stretch, it is technically not
the same throughout. Dependencies and build inputs can change, so
the closure of a package at one revision is not guaranteed to be
the same as the closure of that same package at another revision,
even if the version string is identical.

You may be missing improvements or fixes to the closure of a package despite the version string being the same.


## Using it

`mvs solve` answers the fewest revisions necessary to serve a set of pins.

```console?comments=true
# the plan, as JSON, with the certificate
$ mvs solve --json python3@3.8 nodejs@14 | jq .why
"one revision serves every pin"

# if you need exactly one Nixpkgs, assert it -- the plan already knows
$ mvs solve --json python3@3.8 nodejs@14 | jq -e '.revisions == 1'
```

An existing lock file can be optimized in place:

```console?comments=true
$ mvs lock minimize
4 pins · 4 revisions → 1 · minimal

ATTR     VERSION  REVISION      DATE        OLDER BY
fd       8.7.0    6500b4580c2a  2023-09-25  24 days
hello    2.12.1   6500b4580c2a  2023-09-25  603 days
ripgrep  13.0.0   6500b4580c2a  2023-09-25  59 days

  minimal: one revision serves every pin

# report and refuse to write, for CI
$ mvs lock minimize --check
```

On the Nix side, the whole set resolves at once:

```nix
mv.solvePins { ripgrep = "13.0.0"; fd = "8.7.0"; jq = "1.6"; }
# => { ripgrep = <drv>; fd = <drv>; jq = <drv>; }
# all three out of 2023-09-25-6500b4580c2a
```

You can customize this behavior through the modules. It is on by default:

```nix
{
  multiverse.pins = {
    python3 = "3.8.9";
    nodejs = "14.17.3";
  };

  # `plan` is computed from the index without
  # fetching anything, so you can
  # demand a single Nixpkgs and fail the
  # build if you cannot have one.
  assertions = [
    {
      assertion = config.multiverse.plan.revisions == 1;
      message = config.multiverse.plan.why;
    }
  ];
}
```

You can find the full design and API documentation on the [nixpkgs-multiverse website](https://nixmultiverse.com/docs/design#minimising).