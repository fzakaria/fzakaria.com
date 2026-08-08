---
layout: post
title: DEFCON34 wrap-up
date: 2026-08-16 09:15 -0700
---

I recently came back from [DEFCON34](https://defcon.org/html/defcon-34/dc-34-index.html) and the [nix.vegas](https://nix.vegas/) community. The talks I gave are now online if you are interested in watching them. 🙌

Many thanks to all the organizers of DEFCON34 and nix.vegas. This is our, the Nix community and mine specifically, second year at DEFCON34 and it was a blast. To be honest,
I barely interacted with the rest of DEFCON because I was so busy with the Nix community. The talks, the hallway conversations, and the in-chance encounters were all amazing.

One particular story, was that [Carl Dong](https://blog.carldong.me/) happen to be walking by the Nix Vegas village as I was giving my talk on [Guix by Nix]({% post_url 2026-07-29-guix-by-nix %}). He was a Bitcoin core developer and was one of the contributors responsible for the [Bitcoin Core reproducible builds](https://bitcoinops.org/en/topics/reproducible-builds/) project that leverges [Guix](https://guix.gnu.org/).[^bitcoin]

[^bitcoin]: He was pleasantly surprised and happy to hear that Nix also has reproducible builds that start from [stage0](https://savannah.nongnu.org/projects/stage0/).

Kismet. 

## What is nix.vegas?

For those that don't know: [nix.vegas](https://nix.vegas/) is the Nix community that runs within DEF CON in Las Vegas, hosted by the [SoCal NixOS User Group](https://socalnixos.org/) and Distractions, Inc. This was its second year: DEF CON 33 ran under the banner _"Rebuild the World"_, and this year's theme was _"Escape Your Fate"_.

The [full playlist is on YouTube](https://www.youtube.com/playlist?list=PLLa7deZPvzZ4).

> **Note**
> If the sound is a bit off or weird, this year DEF CON 
> experimented with "silent" talks. Each talk was broadcasted and
> attendees had to wear headphones to listen. It was a bit weird
> giving talks to a quiet room. 🤷
{: .alert .alert-note }

## Relocatable Nix Binaries

<iframe src="https://www.youtube.com/embed/jeLJ5ObNKDg" title="Farid Zakaria - Relocatable Nix Binaries" frameborder="0" allowfullscreen></iframe>

**Summary**: Nix's absolute `/nix/store` paths buy us reproducibility, but costs us the ability to put the store anywhere else. You _can_ change the store prefix today, but it changes the hash of every single derivation in the closure down to `bash`, so you get to rebuild the world before you get to run `hello`.

How can we circumvent this?

The talk walks through `$ORIGIN` in `RUNPATH` and upstreaming support in the Linux kernel via a eBPF-based `binfmt_misc` solution.

Further reading: [Linux kernel will support $ORIGIN, sort of]({% post_url 2026-07-20-linux-kernel-will-support-origin-sort-of %}).

## Guix by Nix

<iframe src="https://www.youtube.com/embed/oTsXNxMapj8" title="Farid Zakaria - Guix by Nix: Stealing an entire distro's bootstrap, one .drv at a time" frameborder="0" allowfullscreen></iframe>

**Summary**: What was meant to be a lightning talk on [guix-transfer](https://github.com/fzakaria/guix-transfer) and [GuixPkgs](https://github.com/fzakaria/guixpkgs) but went a little over. This is our project on rewriting Guix derivations into Nix derivations so that every Guix package becomes buildable by Nix. This lets us include their source-bootstrapped JDK for instance, which nixpkgs does not have.

Further reading: [Guix by Nix]({% post_url 2026-07-29-guix-by-nix %}) and [GuixPkgs: every Guix package, as a Nix flake]({% post_url 2026-06-25-guixpkgs-every-guix-package-as-a-nix-flake %})

## How to piss off your Nix friends

<iframe src="https://www.youtube.com/embed/q2-fspvj18U" title="Farid Zakaria - How to piss off your Nix friends" frameborder="0" allowfullscreen></iframe>

**Summary**: This talk is a bit of a rant, but it is given in good faith with a dose of humor. The core claim is that we optimize Nix and nixpkgs for social comfort and broad appeal, and we pay for it in technical ambition.

Further reading: [How to piss off your Nix friends]({% post_url 2026-07-18-how-to-piss-off-your-nix-friends %}).

Looking forward to next year. Three talks in two days was a little ambitious, but I would do it again.

Everything lives on my [talks page](/talks) alongside their slides and the rest of my talks.
