---
layout: post
title: 'A build graph that rolls dice'
date: 2026-09-20 18:00 -0700
---

We are right around the corner from [NixCon 2026](https://2026.nixcon.org/). Another year where I sadly won't be present. 

I looked at the lineup and saw quite a few talks on dynamic derivations, along with some recent other posts on the topic such as [cargo-dyndrv](https://blog.obsidian.systems/cargo-dyndrv-a-beginning/) which had me thinking about revisting the topic since my [earlier]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}) [posts]({% post_url 2025-03-11-nix-dynamic-derivations-a-practical-application %}) on the subject.

I wanted to better understand the implications of dynamic derivations and how they change the build graph. Originally, I was focused on how it could replace the _lang2nix_ style of build graph generation, but I realized that the implications are much broader than that.

The graph does not need to be known up front. It can be defined as the build progresses. 🧐

What do I mean?

Traditionally, Nix requires you to ask it to build anything and it will tell you exactly the steps it will take ahead of time as the "derivations" that comprise the build graph.

```console
$ nix-store -q --requisites \
    $(nix-instantiate '<nixpkgs>' -A hello) | grep -c '\.drv$'
196
```

This is an important property of Nix. It is what makes it possible to reason about builds without running them by understanding what *will* be built.

Many Nix tools rely on this property via `nix build --dry-run`. 
For instance, [nix-diff](https://github.com/Gabriella439/nix-diff) tells you why two closures differ **without building either**.

Why does dynamic derivations change this?


## Applicative, monadic, bind

In functional languages it's very easy to get abstract and use _fancy_ words like "applicative" and "monadic" to describe the difference between types of computation. The difference is subtle, but it is profound.

Nix traditionally was an "applicative" build system. Dynamic derivations make it a "monadic" build system. The difference is that in an applicative build system, the entire build graph is known up front, while in a monadic build system, the graph can be defined as the build progresses.[^carte]

[^carte]: The paper [Build Systems à la Carte](https://www.microsoft.com/en-us/research/uploads/prod/2018/03/build-systems.pdf) is the defacto read on this topic.


One way to think about the difference is to look at the type signatures of the two operations that define them:

```haskell
<*> apply :: f (a -> b) -> f a          -> f b
>>= bind  :: m a        -> (a -> m b)   -> m b
```


`apply` (applicative) takes `f a` a value known ahead of time and returns the result `f b`. You can see the entire graph before you run it. 

`bind` (monadic) takes `(a -> m b)`, a *function*, to return `m b`. You cannot see the entire graph before you run it.


**Applicative** can be thought of writing the shopping list before you leave the house. You read the recipe, you write down every ingredient, you drive to the store once. The list is a function of the recipe and nothing else.

**Monadic** is a recipe with a step that says *taste it, and if it is too salty, go buy a potato*. You cannot write that shopping list up front. Whether the potato is on it depends on the saltiness, and the saltiness does not exist until you have already done some of the cooking.

Nix used to be solely the former, dynamic derivations add the latter.

## Actually, nix always had bind

[![always has been bind meme](/assets/images/always_has_been_bind_meme.png)](/assets/images/always_has_been_bind_meme.png)
{: style="--image-width: 20rem"}

Okay, I guess I should have said "Nix is now monadic in the scheduler". Nix has always had bind in the evaluator. We have been doing monadic builds for years. We call it
[import from derivation]({% post_url 2020-10-20-nix-parallelism-import-from-derivation %}).

```nix
let
  inner = pkgs.runCommand "inner" {} "sleep 10; echo hi > $out";
in
  pkgs.runCommand "outer" {} "echo ${builtins.readFile inner} > $out"
```

`builtins.readFile` on a derivation output is a **bind** in exactly the sense above: what to build next is a function of a value that does not exist yet. The Nix evaluator cannot produce the graph without that value, and the only way to get it is to stop evaluating and run a builder. 


Unfortunately, this has a lot of footguns, such as causing
[`nix-instantiate` to take ten seconds]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}),
and why nixpkgs _bans the technique outright_.

Whereas _import from derivation_ is a bind in the evaluator, dynamic derivations now adds bind in the scheduler. The difference is that the scheduler can run builders in parallel, and it can ship them to remote machines, and it can substitute their results from a cache. The evaluator cannot do any of that.

Dynamic derivations do not add the bind. The bind was always there. What
changes is which layer performs it:

## Let's roll some dice

Many of the examples of dynamic derivations have been focused on build graph generation via _lang2nix_ tooling, but I wanted to explore the implications of dynamic derivations in a more general sense.

In the true _monadic_ sense, the build graph can be defined as the build progresses. The next step in the build graph can depend on the result of a previous step.

Here is a really simple example, `chain.nix` & `step.sh`, that rolls a die and either stops or continues the chain by adding a new derivation step to the build graph. The depth of the chain is random, and the result of the build is how deep we got.

<details markdown="1">
<summary>Show chain.nix</summary>

```nix
{ depth ? 1
, pkgs ? import <nixpkgs> { }
, bash ? pkgs.bash
, coreutils ? pkgs.coreutils
, nix ? pkgs.nixVersions.latest
, chain ? ./chain.nix
, step ? ./step.sh
}:
let
  roller = derivation {
    name = "step-${toString depth}.drv";
    system = builtins.currentSystem;
    builder = "${bash}/bin/bash";
    args = [ "-e" "${step}" ];

    DEPTH = toString depth;
    BASHPKG = "${bash}";
    COREUTILS = "${coreutils}";
    NIXPKG = "${nix}";
    CHAIN = "${chain}";
    STEP = "${step}";
    PATH = "${coreutils}/bin:${nix}/bin";

    # The builder instantiates derivations, so it needs a store to talk to.
    requiredSystemFeatures = [ "recursive-nix" ];

    # This derivation's output is a .drv file. That is what makes it dynamic.
    __contentAddressed = true;
    outputHashMode = "text";
    outputHashAlgo = "sha256";
  };
in
builtins.outputOf roller.outPath "out"
```

</details>

<details markdown="1">
<summary>Show step.sh</summary>

```bash
set -eu
export NIX_CONFIG='experimental-features = nix-command ca-derivations dynamic-derivations'

roll=$(( $(od -An -N1 -tu1 < /dev/urandom) % 6 + 1 ))
echo "depth $DEPTH rolled a $roll"

if [ "$roll" -eq 6 ]; then
  # Six. Stop. The answer is how deep we got.
  cat > answer.nix <<NIX
let bash = builtins.storePath $BASHPKG; in
derivation {
  name = "dice-result";
  system = builtins.currentSystem;
  builder = "\${bash}/bin/bash";
  args = [ "-c" "echo $DEPTH > \$out" ];
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
}
NIX
else
  # Not a six. My answer is whatever the next level answers.
  cat > answer.nix <<NIX
let
  bash = builtins.storePath $BASHPKG;
  coreutils = builtins.storePath $COREUTILS;

  # This is the bind. Asking chain.nix for the next depth neither builds it
  # nor evaluates it here: it yields a placeholder standing for "whatever
  # depth $(( DEPTH + 1 )) eventually answers".
  inner = import (builtins.storePath $CHAIN) {
    inherit bash coreutils;
    depth = $(( DEPTH + 1 ));
    nix = builtins.storePath $NIXPKG;
    chain = builtins.storePath $CHAIN;
    step = builtins.storePath $STEP;
  };
in
derivation {
  name = "dice-passthrough";
  system = builtins.currentSystem;
  builder = "\${bash}/bin/bash";
  args = [ "-c" "cp \$inner \$out" ];
  PATH = "\${coreutils}/bin";
  inherit inner;
  __contentAddressed = true;
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
}
NIX
fi

cp "$(nix-instantiate answer.nix)" "$out"
```

</details>

The general idea of this derivation is:

- **roll a six** and we write a derivation that echoes the depth. Ordinary, nothing dynamic about it. This terminates the build graph.
- **roll anything else** and we write a *passthrough*: a derivation whose only job is `cp $inner $out`, where `inner` is `import chain.nix { depth = n + 1; }`.

Either way the file copied into `$out` is a `.drv`, so `builtins.outputOf` worksthe same on a chain that stopped and a chain that kept going.[^depth]

[^depth]: We actually need a depth parameter to avoid infinite recursion and so that the store-path of the derivations are different since they are content-addressed.

We can see the build graph grow in the denominator as the build progresses.


![A terminal running nix build on the dice chain. The progress counter starts at one derivation and climbs past fifty as each level emits the next one.](/assets/images/nix-dyndrv-dice.gif)


If we try to introspect the graph with `--dry-run` or `nix-store -q --tree`, we get nothing. Since the graph is not known yet, our tools cannot see it.

```console
$ nix build --store /tmp/dice -f ./default.nix --dry-run
warning: Ignoring dynamic derivation /nix/store/vnm4l32g…-step-1.drv.drv^out
while querying missing paths; not yet implemented
```
Dynamic derivations introduce a second graph that exists only after the build, and the ecosystem has no
way to introspect it yet.

I ran the build 900 times and logged the length of the chain. Rolling a six-sided die is one of the most classic ways to simulate geometric decay and we can see the results in the histogram below. The mean is 6.18, median 4, longest 46.

```plotnine
import pandas as pd
from plotnine import *

# 893 chains against fresh stores. `nix build --store /tmp/dicebench/$i`,
# eight at a time; the result file holds the chain length.
counts = {1: 165, 2: 113, 3: 100, 4: 70, 5: 93, 6: 58, 7: 45, 8: 40, 9: 24,
          10: 27, 11: 29, 12: 16, 13: 20, 14: 14, 15: 18, 16: 9, 17: 8, 18: 7,
          19: 5, 20: 4, 21: 5, 22: 3, 23: 1, 24: 1, 25: 5, 28: 1, 29: 3,
          30: 1, 31: 2, 33: 1, 37: 1, 38: 1, 43: 1, 45: 1, 46: 1}
n = sum(counts.values())

df = pd.DataFrame({"length": list(counts), "runs": list(counts.values())})
# A byte from /dev/urandom mod 6 is very slightly unfair: 42 of 256 bytes
# roll a six, not 42.67, so the mean is 6.10 rather than 6.
p = 42 / 256
geo = pd.DataFrame({"length": range(1, 47)})
geo["runs"] = n * (1 - p) ** (geo.length - 1) * p

plot = (
    ggplot(df, aes("length", "runs"))
    + geom_col(fill="#b1201d", width=0.8)
    + geom_line(geo, aes("length", "runs"), color="#e08a45", size=0.9)
    + labs(x="derivations in the chain", y="runs out of 900")
)
plot.width, plot.height = 7.0, 3.4
```
{: title="Distribution of chain lengths over 893 builds against fresh stores: a geometric decay from 165 runs of length one out to a single run of length 46, with the theoretical geometric curve overlaid"}

 _The math maths._

## Beyond lang2nix

Every dynamic derivations demo so far, mine included, has been a build system:
[MakeNix](https://github.com/fzakaria/MakeNix) for C,
[NpmNix](https://github.com/fzakaria/NpmNix) for node,
[cargo-dyndrv](https://github.com/obsidiansystems/cargo-dyndrv) for Rust,
[nix-ninja](https://github.com/pdtpartners/nix-ninja) for ninja. That is a reasonable place to start but it does not capture the full power of the primitive. What other ideas can we explore?

**Mario.** In [Super Mario Derivations]({% post_url 2026-08-05-super-mario-derivations %})
the attribute path is the button sequence and I have to supply the press count.
The dynamic version emulates until Mario dies. The stopping condition is data,
discovered mid-build, and the run is however long it turns out to be.

**Searching a state space.** Swap the die for a predicate and you have a search
where each frontier node is a derivation. Model checking, puzzle solvers, a
fuzzer that only expands inputs which found new coverage. States you reach twice
collapse onto one store path, and they survive a reboot.

**Crawling.** Fetch a page, parse the links, emit one derivation per link. The
frontier is discovered rather than declared, the crawl resumes because the store
remembers every page already fetched, and the dependency graph of the result is
the link graph.

What are the bounds of this primitive? I don't know.

The size of the graph now is only limited by whether Nix stops emitting successors. There is no depth limit for the store layer, no `max-call-depth` equivalent. My longest honest chain was in the die-roll was 46 deep, and I had rigged examples that went to 500.

I am so brainwashed to thinking about making a plan before I start for my build systems, that the idea of making it up as I go is a little scary. 😨