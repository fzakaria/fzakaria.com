---
layout: post
title: nixpkgs-multiverse is audacitymaxxing
date: 2026-08-11 08:30 -0700
---

_Every package manager on earth picks one version for you. Nixpkgs picked one too. It never had to._

I shared [nixpkgs-multiverse]({% post_url 2026-08-09-nixpkgs-multiverse-every-version-that-ever-existed %}) recently: one flake input that hands you every version of every package that ever shipped in Nixpkgs.

I love how unbelievable audacious Nix lets me be, _audacitymaxxing_.

As of this writing, you have access to 31,783 packages and
304,484 distinct package version pairs pulled from 1,537 revisions. 🤯

The fact most distributions only give you one version of each package is not a bug. It is often considered a feature: a single self-consistent set of software that boots and runs together.
It falls directly out of a shared global filesystem, the [filesystem hierarchy standard](https://refspecs.linuxfoundation.org/FHS_3.0/fhs/index.html) (FHS), like `/usr`, `/lib` and `/etc`.

The purpose and existence of Nix is to eschew from that convention and allow multiple versions of the same package to coexist. Nixpkgs is a distribution built on that capability, and yet, it has been doing the same thing as every other distribution: picking one version of everything.

[nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse) only supports, _at the moment_, top-level attributes that are packages but already the sheer volume of
installable software dwarfs `nixpkgs-unstable`.[^repology]

[^repology]: The data was fetched from the [Repology](https://repology.org/repositories/graphs) repository size map.

```plotnine
import re

import pandas as pd
from plotnine import *

# Total installable package entries per repository, 2026-08-11, from
# repology.org/repositories/packages -- the "Packages / Total" column.
#
# nixpkgs-multiverse is its own index rather than a repology row: 304,484
# (attribute, version) pairs across 1,537 indexed nixpkgs revisions.
ROWS = (
    "nixpkgs-multiverse:304484 nixpkgs unstable:147500 AUR:117218 "
    "Debian Unstable:42762 Ubuntu 26.04:40697 FreeBSD Ports:38574 "
    "Debian 13:38559 GNU Guix:32956 Fedora 43:30089 Alpine 3.22:26318 "
    "openSUSE Tumbleweed:17108 Arch Linux:15449 Homebrew:12984 "
)

df = pd.DataFrame([(m[0], int(m[1]))
                   for m in re.findall(r"([A-Za-z0-9 .+-]+?):(\d+)", ROWS)],
                  columns=["repo", "entries"])
df = df.sort_values("entries").reset_index(drop=True)
df["repo"] = pd.Categorical(df["repo"], categories=df["repo"], ordered=True)

# Only the last row is the multiverse; everything above it is a snapshot.
df["kind"] = ["one snapshot"] * (len(df) - 1) + ["every snapshot"]

plot = (
    ggplot(df, aes("repo", "entries", fill="kind"))
    + geom_col(width=0.65)
    + geom_text(aes(label="entries"), format_string="{:,}", size=7.5,
                ha="left", nudge_y=4000)
    + coord_flip()
    + scale_y_continuous(limits=(0, 350000), expand=(0, 0),
                         labels=lambda ys: [f"{int(y / 1000)}k" for y in ys])
    + scale_fill_manual(values={"one snapshot": "#4c72b0",
                                "every snapshot": "#b1201d"}, name="")
    + labs(x="", y="installable package entries")
    + theme(legend_position="none")
)
plot.width, plot.height = 7.0, 4.0
```

Nix's answer to the FHS was audacious in 2003 and is still audacious now. A package lives at `/nix/store/<hash>-python3-3.12.10`, where the hash is derived from every input that went into building it: the [intensional model]({% post_url 2025-03-08-demystifying-nix-s-intensional-model %}).

How audacious are we? How about 246 distinct CPython versions, from 2.6.8 forward, all installable side by side, all built and cached, all addressable by version number instead of commit hash.[^python_repology]

[^python_repology]: The data for other distributions was fetched from [Repology](https://repology.org/project/python/versions).

```plotnine
import pandas as pd
from plotnine import *

# Distinct CPython versions per repository, 2026-08-11.
# Repos: repology /api/v1/project/python, counting distinct `version` values.
# multiverse: the union over every `python*` attribute in index/versions.json.
df = pd.DataFrame({
    "repo": ["Debian 13", "Ubuntu 26.04", "Arch", "Alpine 3.22", "GNU Guix",
             "nixpkgs unstable", "Homebrew", "openSUSE Tumbleweed",
             "FreeBSD Ports", "Fedora 43", "AUR", "nixpkgs-multiverse"],
    "n": [1, 1, 1, 1, 4, 5, 6, 6, 8, 14, 21, 246],
})
df = df.sort_values("n").reset_index(drop=True)
df["repo"] = pd.Categorical(df["repo"], categories=df["repo"], ordered=True)
df["kind"] = ["today's snapshot"] * 11 + ["every snapshot"]

# Linear, not log. A log axis would flatter the distros by turning "one" into
# a respectable-looking bar, and the whole point is the ratio.
plot = (
    ggplot(df, aes("repo", "n", fill="kind"))
    + geom_col(width=0.65)
    + geom_text(aes(label="n"), size=7.5, ha="left", nudge_y=4)
    + coord_flip()
    + scale_y_continuous(limits=(0, 270), expand=(0, 0))
    + scale_fill_manual(values={"today's snapshot": "#4c72b0",
                                "every snapshot": "#b1201d"}, name="")
    + labs(x="", y="distinct CPython versions installable")
    + theme(legend_position="none")
)
plot.width, plot.height = 7.0, 3.6
```

To re-iterate, these are distinct versions of CPython, including their transitive dependencies. There is no `glibc` or `openssl` or `zlib` that is shared between them.[^glibc] They work just as reliably as when they were first released, and they are all still installable today and can be substituted from the cache.

[^glibc]: Unless they happen to dedupe due to their hash.

People want to pin to a version. Upgrading software can be disruptive, and some people have to stay on a particular version but that should not impede the rest of the world from moving forward.

The [nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse) helped solve one of the oldest [devenv.sh](https://devenv.sh/) issues, [cachix/devenv#16](https://github.com/cachix/devenv/issues/16),
the desire to pin a specific package.

> "It is not really practical to pin a separate version of nixpkgs for every different version of a tool needed in a dev environment. Normally we have at least 20-30 different tools all with a specific pinned version that we would want to specify." -- [itpropro](https://github.com/cachix/devenv/issues/16#issuecomment-4150126963)

The issue, "Pinning a specific package", was opened on 2022-11-10 and is now closed. devenv [now documents](https://devenv.sh/pinning/#pinning-an-individual-package-version) the multiverse as the solution. 💪

The audacity of the multiverse is not technical. Nix took care of that. There is no clever trick in here; it's 5 MB of JSON, about 200 lines of Nix and a `builtins.fetchTree` behind a memo table.

The audacity is in the premise.

## Odds and ends

Two smaller things landed that I like and which was driven by feedback from the community.

**A soak period.** `daysBehind` gives you the whole of `nixos-unstable` as it stood N days before an anchor, a cooldown window, in the spirit of [Determinate Systems' cooldowns](https://determinate.systems/blog/nixpkgs-cooldown/#reducing-the-risk-with-cooldowns), except the anchor can be any selector `at` takes.

```console
nix-repl> (mv.daysBehind "tip" 7).hello.version
"2.12.3"
nix-repl> (mv.daysBehind "tip" 365).hello.version
"2.12.2"
```

**Provenance.** Every package set carries where it came from, so a `pkgs` you were handed can be interrogated rather than guessed at.

```console
nix-repl> (mv.at "26.05").multiverse
{ build = 7376; date = "2026-08-09"; name = "nixos-26.05.7376.fcb8fcd6bf2d";
  release = "26.05"; rev = "fcb8fcd6bf2d0adecae5bd491afaaaf8311b758d"; }

nix-repl> (mv.at "2022-03-15").multiverse
{ date = "2022-03-14"; label = "2022-03-14-73ad5f9e147c";
  rev = "73ad5f9e147c0d2a2061f1d4bd91e05078dc0b58"; }
```
