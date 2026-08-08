---
layout: post
title: "How safe is follows?"
date: 2026-08-31 09:00 -0700
---

I recently wrote about [omniflake]({% post_url 2026-08-28-one-flake-to-rule-them-all %}), accessible via <https://omniflake.com>, which indexes over 12,000 flakes and makes them available
through a single flake input.

One of the earliest requests I had was to support something similar to my tool [nix-auto-follows]({% post_url 2024-07-31-automatic-nix-flake-follows %}) to consolidate every flake's inputs to a single coherent set.

This is the same pattern you see often in every guide to flakes, often highlighting the `follows` attribute without much explanation of what it does or why it is used.

```nix
inputs.disko.url = "github:nix-community/disko";
inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
```


The `follows` attribute consolidates a flake's inputs to a single source, often used for `nixpkgs`. This reduces the number of distinct nixpkgs revisions in the dependency graph, which can speed up evaluation and reduce overall closure size.

Those with _more experience_ with flakes have a strong opinion about `follows`. While it improves evaluation speed and closure size, it can introduce subtle breakages and deviates from the original author's intent which is counter to the philosophy of Nix which deems "reproducibility" as a core principle.

![starship troopers follows meme](/assets/images/starship_troopers_follows_meme.png)

I wanted to dig into the question of how safe it is to use `follows` in practice. The folklore is that it is dangerous, but I wanted to see if that was true. Turns out that <https://omniflake.com> is the perfect tool to try and answer this question.


## Time traveling Nixpkgs

As I mentioned above, `follows` lets you consolidate a flake's inputs to a single source. In the case of nixpkgs, this means that you are asking a flake to build against a nixpkgs revision that its author may never have evaluated it with. This can lead to breakages if the flake relies on specific behavior or attributes of the original nixpkgs revision.

Often the delta between the two revisions is a good measure of how likely it is to break. If the nixpkgs revision you are following is only a few days or weeks newer than the original, it is likely to be safe. If it is several months or years newer, the risk of breakage increases.

We can look at every flake within omniflake and see how old the nixpkgs revision is that it locks. 11,936 flakes are indexed in the omniflake index, 10,754 of them lock a
nixpkgs and between them they name **3,261 distinct nixpkgs revisions**.

Here is every *distinct* revisions, placed by the date it was locked by the number of flakes that pinned it.

```plotnine
import pandas as pd
from plotnine import *

# _data/nixpkgs-pins.csv -- one row per distinct nixpkgs revision that some
# flake in the omniflake index locks, built on 2026-08-31 by the script
# linked at the end of this post. Excludes nim-nix-pkgs; see the aside.
df = pd.read_csv("_data/nixpkgs-pins.csv", parse_dates=["locked"])

# Four revisions predate 2020, because flakes did not exist yet. Three are
# pinned once each; the fourth is 30 flakes from two of the generated
# families the aside describes. They cost three years of axis.
df = df[df["locked"] >= "2020-01-01"]

CHANNELS = ["nixos-unstable", "nixpkgs-unstable", "nixos release",
            "small release", "darwin release", "never a channel"]
df["channel"] = pd.Categorical(df["channel"], categories=CHANNELS, ordered=True)

# One point per (month, flakes, channel); its size is how many revisions
# landed in that cell, so the dense floor reads as dense rather than as one dot.
df["month"] = df["locked"].dt.to_period("M").dt.to_timestamp()
cells = (df.groupby(["month", "flakes", "channel"], observed=True)
           .size().reset_index(name="revisions"))

plot = (
    ggplot(cells, aes("month", "flakes", color="channel", size="revisions"))
    + geom_point(alpha=0.55, stroke=0)
    + scale_y_log10(breaks=[1, 3, 10, 30, 100, 300],
                    labels=["1", "3", "10", "30", "100", "300"])
    + scale_x_datetime(date_breaks="1 year", date_labels="%Y")
    + scale_size_continuous(range=(1.4, 8.0), guide=None)
    + scale_color_manual(values={"nixos-unstable": "#9e3413",
                                 "nixpkgs-unstable": "#c98b2e",
                                 "nixos release": "#3a6ea5",
                                 "small release": "#4f8a6b",
                                 "darwin release": "#8a5fa8",
                                 "never a channel": "#9a9186"}, name="")
    + guides(color=guide_legend(nrow=2, override_aes={"size": 3.5, "alpha": 1}))
    + labs(x="", y="flakes pinning this revision")
    + theme(panel_grid_minor=element_blank(), legend_position="bottom",
            legend_title=element_blank(), legend_text=element_text(size=7))
)
plot.width, plot.height = 7.4, 4.4
```

Quite a lot of revisions are pinned by only a single flake.
We can also visualize how old each nixpkgs revision is as of August 31, 2026.

```plotnine
import pandas as pd
from plotnine import *

AS_OF = pd.Timestamp("2026-08-31")

df = pd.read_csv("_data/nixpkgs-pins.csv", parse_dates=["locked"])
df["age"] = (AS_OF - df["locked"]).dt.days

# One entry per flake, by repeating each revision as many times as it was
# pinned.
pins = df.loc[df.index.repeat(df["flakes"]), ["age", "channel"]].reset_index(drop=True)

def cdf(frame, label):
    ages = frame["age"].sort_values().to_numpy()
    return pd.DataFrame({"age": ages,
                         "share": (pd.RangeIndex(1, len(ages) + 1) / len(ages)),
                         "series": label})

CHANNELS = ["nixos-unstable", "nixpkgs-unstable", "nixos release",
            "small release", "darwin release", "never a channel"]
curves = pd.concat(
    [cdf(pins, "all pins")] +
    [cdf(pins[pins["channel"] == c], c) for c in CHANNELS]
)
curves["series"] = pd.Categorical(curves["series"], categories=["all pins"] + CHANNELS,
                                  ordered=True)

plot = (
    ggplot(curves, aes("age", "share", color="series"))
    + geom_step(size=0.8)
    + scale_x_log10(breaks=[7, 30, 90, 365, 730, 1825],
                    labels=["1w", "1mo", "3mo", "1y", "2y", "5y"])
    + scale_y_continuous(labels=lambda ys: [f"{y:.0%}" for y in ys])
    + scale_color_manual(values={"all pins": "#1a1815",
                                 "nixos-unstable": "#9e3413",
                                 "nixpkgs-unstable": "#c98b2e",
                                 "nixos release": "#3a6ea5",
                                 "small release": "#4f8a6b",
                                 "darwin release": "#8a5fa8",
                                 "never a channel": "#9a9186"}, name="")
    + guides(color=guide_legend(nrow=2))
    + labs(x="age of the pinned nixpkgs", y="share of flakes this old or newer")
    + theme(panel_grid_minor=element_blank(), legend_position="bottom",
            legend_title=element_blank(), legend_text=element_text(size=7))
)
plot.width, plot.height = 7.4, 4.2
```

**Half of all flakes are pinned to a nixpkgs older
than 506 days**, nearly a year and a half, and a twentieth are past 1,768 days (five years).

The channels follow the distribution one would largely expect: `nixos-unstable` (red line) pins are the freshest, which is unsurprising for a channel that moves daily. The darwin channel seems scary to replace with `follow`, barely 5% of those pins are under a year old

What does this all mean?

If we consider the median, when you add a `follows` line you are, typically, asking a flake to replace it with a nixpkgs likely a year and a half newer than anything its author ever tested. One time in twenty you are asking it to consolidate across five years. 😬

## Which nixpkgs, though?

Not all nixpkgs are equal. A flake pinned to a nixpkgs that was a channel bump was built by Hydra and therefore received testing and is available for substitution from <https://cache.nixos.org>.

We can audit the nix release archive to determine whether a given nixpkgs was ever a channel bump. Every channel bump ever published is a directory
under `nix-releases`, named for the commit it pointed at:

```console
$ curl -s 'https://nix-releases.s3.amazonaws.com/?delimiter=/&prefix=nixos/unstable/' \
    | grep -o '<Prefix>[^<]*</Prefix>' | tail -1
<Prefix>nixos/unstable/nixos-26.11pre1064949.34ab99075ac4/</Prefix>
```

If we enumerate all 74 channels, every `nixos/*` and `nixpkgs/*-darwin` channel, we discover 30,850 (commit, channel) pairs to check against.[^release-gotcha]

[^release-gotcha]: Earlier releases used shorter revisions and `nixpkgs-unstable` has no channel directory, its releases sit under `nixpkgs/`.

```plotnine
import pandas as pd
from plotnine import *

# channel : distinct revisions pinned : flakes pinning them
ROWS = """
nixos-unstable      697  5033
nixpkgs-unstable    942  2541
nixos_release       307   877
never_a_channel     676   857
small_release       335   749
darwin_release      304   697
"""

df = pd.DataFrame(
    [(a.replace("_", " "), int(b), int(c))
     for a, b, c in (line.split() for line in ROWS.strip().splitlines())],
    columns=["channel", "revisions", "flakes"],
).sort_values("flakes").reset_index(drop=True)
df["channel"] = pd.Categorical(df["channel"], categories=df["channel"], ordered=True)

long = df.melt(id_vars="channel", value_vars=["flakes", "revisions"],
               var_name="measure", value_name="n")
# Only the flakes bar is labelled; two labels on a row collide whenever the
# measures are close, as they are on "never a channel".
long["lab"] = [f"{n:,}" if m == "flakes" else "" for m, n in zip(long["measure"], long["n"])]

plot = (
    ggplot(long, aes("channel", "n", fill="measure"))
    + geom_col(position=position_dodge(width=0.72), width=0.66)
    + geom_text(aes(label="lab"), position=position_dodge(width=0.72),
                size=7.5, ha="left", nudge_y=70)
    + coord_flip()
    + scale_y_continuous(limits=(0, 5600), expand=(0, 0))
    + scale_fill_manual(values={"flakes": "#9e3413", "revisions": "#a89680"}, name="")
    + labs(x="", y="")
    + theme(legend_position="bottom", panel_grid_major_y=element_blank())
)
plot.width, plot.height = 7.0, 3.4
```

The majority of revisions, four in five, were a published channel bump. 
That is better than I expected and means that most flakes are pinned to a nixpkgs that was built by Hydra and therefore received testing and is available for substitution from the cache. Few flakes are pinned to a nixpkgs that was never a channel bump.

The most common revisions that are shared amongst the flakes are relatively recent as well. The top 8 revisions are all from 2026, and the oldest revision in the top 8 is from May 4, 2026.

| revision | locked | flakes | channel |
| --- | --- | ---: | --- |
| `9fbb54b33e91` | 2026-08-26 | 302 | nixos-unstable |
| `2c423e03bbaf` | 2026-08-21 | 98 | nixos-unstable |
| `567a49d1913c` | 2026-06-15 | 72 | nixos-unstable |
| `a62e6edd6d5e` | 2024-05-31 | 70 | 23.11 |
| `56c02bc00adc` | 2026-08-23 | 68 | nixos-unstable |
| `549bd84d6279` | 2026-05-04 | 58 | nixos-unstable |
| `ffb3c9b700e7` | 2026-08-19 | 52 | nixos-unstable |
| `391b592eb448` | 2026-08-20 | 51 | nixpkgs-unstable |

## Nobody pins old nixpkgs

It was good to see that the most common revisions across flakes are relatively recent. Personally, I enjoy running a release or two behind my personal NixOS laptop to avoid unecessary churn while all the kinks are worked out. How common is that?

For each flake, we can take the gap between when the flake was last touched and the date of the nixpkgs it locks. That is how stale the pin was *at the moment its author chose it*, this is very different than the earlier graph which is how stale it is _as of today_.

```plotnine
import pandas as pd
from plotnine import *

# quantile,days-when-chosen,days-old-today over the 10,207 indexed flakes whose
# lock their own author wrote. 200 points is indistinguishable from the full
# step curve at this size. Built 2026-08-31; see the script at the end.
ROWS = """0.000,0,0 0.005,0,1 0.010,0,3 0.015,0,4 0.020,0,5 0.025,0,5 0.030,1,5 0.035,1,5 0.040,1,5 0.045,1,5 0.050,1,6 0.055,1,8 0.060,1,9 0.065,1,9 0.070,1,9 0.075,1,11 0.080,1,11 0.085,1,12 0.090,1,13 0.095,1,15 0.100,1,18 0.105,1,20 0.110,2,23 0.115,2,25 0.120,2,27 0.125,2,29 0.130,2,30 0.135,2,32 0.140,2,36 0.145,2,39 0.150,2,42 0.155,2,44 0.160,2,47 0.165,2,51 0.170,2,56 0.175,2,58 0.180,2,61 0.185,2,63 0.190,2,69 0.195,2,76 0.200,2,77 0.205,3,82 0.210,3,86 0.215,3,91 0.220,3,92 0.225,3,97 0.230,3,100 0.235,3,108 0.240,3,112 0.245,3,116 0.250,3,118 0.255,3,122 0.260,3,129 0.265,3,134 0.270,3,138 0.275,3,144 0.280,4,151 0.285,4,154 0.290,4,163 0.295,4,168 0.300,4,174 0.305,4,180 0.310,4,185 0.315,4,194 0.320,4,199 0.325,4,206 0.330,5,209 0.335,5,216 0.340,5,223 0.345,5,227 0.350,5,232 0.355,5,241 0.360,6,241 0.365,6,249 0.370,6,259 0.375,6,266 0.380,6,272 0.385,6,277 0.390,7,286 0.395,7,299 0.400,7,304 0.405,7,319 0.410,8,329 0.415,8,342 0.420,8,356 0.425,9,369 0.430,9,382 0.435,9,395 0.440,10,399 0.445,10,411 0.450,11,419 0.455,11,427 0.460,12,433 0.465,12,443 0.470,13,452 0.475,14,463 0.480,14,470 0.485,15,480 0.490,16,486 0.495,16,497 0.500,17,506 0.505,18,513 0.510,19,523 0.515,19,529 0.520,20,540 0.525,21,547 0.530,22,559 0.535,23,571 0.540,24,582 0.545,25,594 0.550,26,606 0.555,27,609 0.560,28,622 0.565,30,630 0.570,31,638 0.575,32,650 0.580,34,660 0.585,36,670 0.590,37,682 0.595,38,693 0.600,40,704 0.605,42,717 0.610,43,726 0.615,46,737 0.620,48,750 0.625,50,761 0.630,51,771 0.635,54,783 0.640,56,792 0.645,58,803 0.650,60,812 0.655,63,821 0.660,65,822 0.665,69,828 0.670,71,834 0.675,74,848 0.680,78,858 0.685,80,870 0.690,83,876 0.695,85,885 0.700,89,895 0.705,91,908 0.710,94,918 0.715,98,931 0.720,101,943 0.725,106,953 0.730,109,961 0.735,113,971 0.740,117,974 0.745,121,990 0.750,126,1000 0.755,131,1009 0.760,136,1026 0.765,141,1040 0.770,146,1059 0.775,152,1072 0.780,156,1089 0.785,162,1104 0.790,168,1115 0.795,174,1138 0.800,178,1152 0.805,184,1165 0.810,191,1179 0.815,196,1190 0.820,205,1217 0.825,213,1239 0.830,220,1254 0.835,226,1265 0.840,235,1279 0.845,243,1292 0.850,253,1317 0.855,263,1335 0.860,271,1351 0.865,278,1369 0.870,289,1385 0.875,303,1407 0.880,318,1422 0.885,333,1447 0.890,348,1477 0.895,363,1497 0.900,379,1510 0.905,391,1537 0.910,402,1556 0.915,417,1581 0.920,437,1618 0.925,460,1642 0.930,483,1664 0.935,507,1676 0.940,536,1700 0.945,572,1735 0.950,601,1768 0.955,640,1797 0.960,683,1815 0.965,724,1855 0.970,776,1893 0.975,813,1916 0.980,842,1963 0.985,924,2029 0.990,1073,2107 0.995,1256,2203 1.000,3379,3441"""

df = pd.DataFrame([tuple(float(x) for x in r.split(",")) for r in ROWS.split()],
                  columns=["share", "chosen", "today"])
# A pin chosen the same day is 0 days old, which a log axis cannot place.
df[["chosen", "today"]] = df[["chosen", "today"]].clip(lower=0.5)

long = df.melt(id_vars="share", value_vars=["chosen", "today"],
               var_name="moment", value_name="days")
MOMENTS = ["when its author chose it", "today"]
long["moment"] = pd.Categorical(
    long["moment"].map({"chosen": MOMENTS[0], "today": MOMENTS[1]}),
    categories=MOMENTS, ordered=True)

plot = (
    ggplot(df, aes(x="share"))
    # the drift: every pin's own journey from the day it was chosen to now
    + geom_ribbon(aes(ymin="chosen", ymax="today"), fill="#9e3413", alpha=0.10)
    + geom_line(aes("share", "days", color="moment"), data=long, size=0.9)
    + scale_y_log10(breaks=[1, 7, 30, 90, 365, 730, 1825],
                    labels=["1d", "1w", "1mo", "3mo", "1y", "2y", "5y"])
    + scale_x_continuous(labels=lambda xs: [f"{x:.0%}" for x in xs])
    + scale_color_manual(values={"when its author chose it": "#4f8a6b",
                                 "today": "#9e3413"}, name="")
    + coord_flip()
    + labs(x="share of flakes", y="age of the pinned nixpkgs")
    + theme(panel_grid_minor=element_blank(), legend_position="bottom",
            legend_title=element_blank(), legend_text=element_text(size=8))
)
plot.width, plot.height = 7.0, 4.0
```

The original stateleness is depicted by the green line. It is the age of Nixpkgs the day it was written whereas red is the same pin today. Half of every flake in the index picked a nixpkgs less than three week old, and a quarter picked one inside three days!

The shades region is simply time passing. It is how stale the pin has become over time. It is a frequency of how often a flake is updated.

| | when chosen | today |
| --- | ---: | ---: |
| **p25** | 3 days | 118 days |
| **p50** | 17 days | 506 days |
| **p75** | 126 days | 1,000 days |
| **p95** | 601 days | 1,768 days |


So essentially nobody deliberately pins an old nixpkgs. They run `nix flake
update`, get whatever was current that week, **and stop**. The ecosystem's
year and a half median is the result of a year and a half of neglect on each flake.

## Did we answer anything?

Not realy but it was fun to look at the data. 

[omniflake](https://omniflake.com) includes an easy way to [unify all flake inputs](https://omniflake.com/docs/unification). We could use it to see how many flakes would break if we replaced their nixpkgs with a single revision, but that would only tell us whether it could evaluate. A flake can evaluate perfectly and then fail to build. That's a lot harder to measure.

For now, I still recommend being mindful when you use `follows`. It is a powerful primitive that can improve evaluation speed and closure size, but it can also introduce subtle breakages, especially if you rely on `nix-darwin`. 🤫

The data for this post came from omniflake's own index, joined against the release archive. It is [one file, on a
gist](https://gist.github.com/fzakaria/311cc4a8af63308d827c2d69f46f9c4f) using a `nix` shebang and the standard library, so it needs nothing installed.

> Beware of bugs in the above code; I have only proved it correct, not tried it
> -- Donald Knuth