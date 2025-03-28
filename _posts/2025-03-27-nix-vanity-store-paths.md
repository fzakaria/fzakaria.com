---
layout: post
title: Nix vanity store paths
date: 2025-03-27 20:26 -0700
---

[Nix](https://nixos.org) is great, but it can be a bit dreary continuously looking at the endless `/nix/store` paths with their varied letters.

Wouldn't it be great if we can inject a little **vanity** into our `/nix/store` paths?

**Vanity Addresses**
: A vanity address is one where we put a desired string (farid) in our `/nix/store` path like `/nix/store/farid8x0yrdpavxxki9vg9spx2xbjb1d-nix-vanity-d915ed2` 

Why would we want to do this? Because we can! 😏

Let's start off with a little demo.

Pick *any* derivation from your `/nix/store`. In my example, I'm picking a derivation I made `/nix/store/cdqs8ir4pzwpl512dp86nk9xhq9bfmcv-vanity-path.drv`

Simply run the tool `nix-vanity`. Let it crunch through a bunch of possible derivations until it emits:

```bash
# n.b. write out the discovered derivation to a file with
# the same name.
> nix-vanity -prefix /nix/store/farid \
  /nix/store/cdqs8ir4pzwpl512dp86nk9xhq9bfmcv-vanity-path.drv \
  > vanity-path.drv
time=2025-03-27T20:40:40.941-07:00 level=INFO msg="Loading base derivation" path=/nix/store/cdqs8ir4pzwpl512dp86nk9xhq9bfmcv-vanity-path.drv
time=2025-03-27T20:40:40.941-07:00 level=INFO msg="Calculating input derivation replacements..."
time=2025-03-27T20:40:40.952-07:00 level=INFO msg="Finished calculating input derivation replacements."
time=2025-03-27T20:40:40.952-07:00 level=INFO msg="Starting workers" count=16
⠙ Searching for prefix... (18104594, 292130 drv/s) [1m0s] time=2025-03-27T20:41:41.189-07:00 level=INFO msg="Prefix found!" seed=18131442 output_name=out path=/nix/store/faridj55f0h38jcnsh89sgp2fsbhv3ws-vanity-path
⠹ Searching for prefix... (18131450, 301001 drv/s) [1m0s] time=2025-03-27T20:41:41.189-07:00 level=INFO msg="Successfully found seed" seed=18131442
time=2025-03-27T20:41:41.189-07:00 level=INFO msg="Writing successful derivation to stdout..."
time=2025-03-27T20:41:41.189-07:00 level=INFO msg="All workers finished."
```

We can now add our _modified_ derivation back to the `/nix/store`

```bash
> nix-store --add vanity-path.drv
/nix/store/mw0ay18bx93r5syyscfmdy1s6jgjxk31-vanity-path.drv
```

Finally, let's _realize_ our modified derivation and validate we have our vanity store path:

```bash
> nix-store --realize /nix/store/mw0ay18bx93r5syyscfmdy1s6jgjxk31-vanity-path.drv
this derivation will be built:
  /nix/store/mw0ay18bx93r5syyscfmdy1s6jgjxk31-vanity-path.drv
building '/nix/store/mw0ay18bx93r5syyscfmdy1s6jgjxk31-vanity-path.drv'...
warning: you did not specify '--add-root'; the result might be removed by the garbage collector
/nix/store/faridj55f0h38jcnsh89sgp2fsbhv3ws-vanity-path
```

Huzzah! `/nix/store/faridj55f0h38jcnsh89sgp2fsbhv3ws-vanity-path` 💥

Very cool! How does this all work? 🤓

The concept is rather _simple_. The `/nix/store` path is calculated from the hash of the derivation.

By injecting a new environment variable `VANITY_SEED` we can attempt different possible store paths.

```bash
> nix derivation show /nix/store/mw0ay18bx93r5syyscfmdy1s6jgjxk31-vanity-path.drv 
{
  "/nix/store/mw0ay18bx93r5syyscfmdy1s6jgjxk31-vanity-path.drv": {
    "args": [
      "-e",
      "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"
    ],
    "builder": "/nix/store/8vpg72ik2kgxfj05lc56hkqrdrfl8xi9-bash-5.2p37/bin/bash",
    "env": {
      "VANITY_SEED": "18131442",
```

Although the idea 💡 was simple, the implementation in code was a bit more arduous.

Thankfully there was a decent starting point with [go-nix](https://github.com/nix-community/go-nix) which I augmented.

You can checkout the command at [https://github.com/fzakaria/go-nix/tree/vanity](https://github.com/fzakaria/go-nix/tree/vanity)

```bash
> go run ./cmd/nix-vanity ...
```

> My next post might go into how exactly the store path is calculated from a derivation file. It was not as straightforward as I had imagined.

Be careful how long of a prefix you pick for your vanity. 🧐

Nix store paths can be any **32** letters from `0123456789abcdfghijklmnpqrsvwxyz` (32 possibilities).

That means if I want a _single letter_ for my prefix, it is a 1/32 probability ~ 3% chance.

For two consecutive letters, there are 32 * 32 total possibilities. If I wanted a single entry that would be 1/(32 * 32) ~ 0.098% chance.

This is exponential and can blow up pretty fast as the search space becomes 32<sup>N</sup>.

| **Prefix Length (N)** | **Expected Attempts** | **Time @ 300,904 drv/s**         |
|:---------------------:|:---------------------:|:--------------------------------:|
| 1                     | 32                    | < 1s                             |
| 2                     | 1,024                 | < 1s                             |
| 3                     | 32,768                | < 1s                             |
| 4                     | 1,048,576             | 3.48 s                           |
| 5                     | 33,554,432            | 111.5 s (≈1.86 minutes)          |
| 6                     | 1,073,741,824         | 3,567 s (≈59.45 minutes)         |
| 7                     | 34,359,738,368        | 114,209 s (≈31.72 hours)         |

I wrote the code in golang with concurrency in mind but even on a machine with 128 cores (AMD Ryzen Threadripper 3990X 64-Core Processor
) it tops out at trying 300904 drv/s.

Either way, for something small like `farid` (5 letters), it's kind of nice to jazz up ✨ the store paths.

You could even build a complete `/nix/store` where every entry is prefixed with a desired vanity string 😈.