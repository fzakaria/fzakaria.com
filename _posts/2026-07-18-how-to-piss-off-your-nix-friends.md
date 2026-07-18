---
layout: post
title: How to piss off your Nix friends
date: 2026-07-18 15:45 -0700
---

> **Warning**
> If you are **pissed off** reading this blog post, I guess, mission accomplished ? Try not to take life too seriously. Unfortunately, there's a lot worse things in life than my opinions on Nix.
{: .alert .alert-warning }

Seems like it's all too easy to get people in Nix flustered, angry and out with their pitchforks. All it takes is [someone proposing a markdown file](https://github.com/NixOS/nixpkgs/pull/534657) for the community to lose its mind.

Having been a member, exposed to and part of the Nix/NixOS community for many years, I thought I would share some _personal opinions_, some which are self-evident and others that are purely philosophical.

![nix pitch fork](/assets/images/nix_pitch_fork.png)

Nix is brilliant _and_ deeply flawed. Both things are true at the same time. The documentation is infamously terrible (although getting better!), the language is foreign to read for many and there are still growing pains from the governance changes. You should be free to say all of this and yet still believe Nix to be the best idea in the industry, at least this decade.

_The emperor has no clothes._

## Nix isn't for everyone.

> "If we just fix the documentation and the onboarding, then there's no stopping Nix & NixOS" - _Most Nix users_

Nix is "having a moment". Growth on any measurable metric is growing. [There](https://gg-solutions.hashnode.dev/linux-the-silent-revolution) [are](https://ryanrasti.com/blog/why-nix-will-win/) [endless](https://determinate.systems/blog/the-nix-moment/) posts about it.

[![nix growth chart](/assets/images/nix_growth_chart_50p.png)](https://gg-solutions.hashnode.dev/linux-the-silent-revolution)

Part of human nature is the desire to win. As a result, there is a persistent fantasy that if we _just_ fix the documentation, _just_ smooth the onboarding, _just_ ship a friendlier installer and so on, then everyone, <u>even your grandmother</u>, can be using NixOS.

[![grandmother nix meme](/assets/images/grandma_nix_ifd_meme_50p.png)](/assets/images/grandma_nix_ifd_meme.png)

Nix is not meant for everyone.

Nix is a power tool. Power tools have a learning curve and can occasionally take a finger. I continue to use a non-NixOS Linux machine in addition and guess what, it works well enough. It is surprisingly stable and despite what Nix leads us to believe, not everything is on fire.

Our obsession with mass adoption has warped priorities and diluted the amazing possibilities Nix could allow by having to make it more palatable for broader appeal.

## Being American is perceived to be a problem.

Nix originated in Europe. It should be no surprise that it skews heavily European. We can easily affirm this from the [2025 community survey](https://nixos.org/surveys/community/2025/#people).

![nix survey results](/assets/images/nix_survey_2025_geography.svg)

Europeans are different from Americans. We hold different cultural values and priorities. Both have traits that I wish the other emulated. Unfortunately, where they clash however is often a point of contention.

Americans are capitalist maximalists. The idea of the "American dream" is tied to it. We also have the largest military budget in the world. You're rarely more than a degree or two from a through-line between a business and the military. This clashes with much of the European worldview.

As a result, there's a bit of an undercurrent where being an American or an American corporation is problematic in the community. Your position is suspect from the start, assumed to carry ulterior motives and it curdles into a purity test.


## AI is useful.

I am clearly in the "AI is useful" camp. I have [written before]({% post_url 2026-05-31-ai-is-a-boon-for-the-anal-retentive %}) about how much LLMs have unlocked for me personally.

[![ai is slop meme](/assets/images/ai_is_slop_meme_50p.png)](/assets/images/ai_is_slop_meme.png)

The Nix ecosystem is probably the best poised for the AI-wave. I have found a newfound joy and love for my NixOS machine now with LLMs. All those weird quirks that bugged me I have been able to resolve, **and declaratively reproduce** for future generations. One-off AI written tools can be written and stored in my NixOS configuration with a sense of assurance that they will not collide or interfere with the rest of the system.

Unfortunately there's a loud contingent that treats AI output at best as technically unsound and at worst as some moral failing of the user. Despite nixpkgs offering AI tools, an [AGENTS.md](https://github.com/NixOS/nixpkgs/pull/534657) file was seen as heresy.

I particularly enjoyed Linus Torvalds, [on a kernel mailing list](https://lore.kernel.org/linux-media/CAHk-=wi4zC+Ze8e+p3tMv8TtG_80KzsZ1syL9anBtmEh5Z40vg@mail.gmail.com/) articulating better than me Linux's position on AI:

> AI is a tool, just like other tools we use. And it's clearly a useful one. [...] Anybody who doubts that clearly hasn't actually used it.

These are tools we can use to push Nix & nixpkgs further.

## BDFL is undervalued.

The democratic process is great for society but a software project originated from _someone_. Someone had the vision, birthed the idea, worked tirelessly on it and then attracted others to contribute to their ongoing vision. In the case of Nix, Eelco created Nix in 2003 as part of his PhD research. The NixOS foundation didn't exist until 2015. That is over a decade of work towards a project driven by his own vision as the _Benevolent Dictator for <s>Life</s>_ (BDFL).

A non-democratic model works especially well in open-source because you are free to fork the software and try your hand at your own ideas if you disagree -- the same cannot be said for our shared geography.

A clear vision, whether you agree with it or not, is refreshing. Someone who can say yes or no and is not simply stonewalled by design-by-committee. DHH had said it poignantly well: _"Using open source software does not entitle you to a vote on the direction of the project."_ [[cite](https://world.hey.com/dhh/open-source-is-neither-a-community-nor-a-democracy-606abdab)].

## Abandon macOS and definitely Windows.

Every hour spent making Nix pleasant on macOS is an hour not spent making Nix _extraordinary_ on Linux. You would never catch an iOS developer working on Linux and yet it pains me to see those who target the Linux platform working on a Mac.

[![drake macos meme](/assets/images/drake_macos_meme_50p.png)](/assets/images/drake_macos_meme.png)

For Nix, Darwin support is a bottomless tax. Closed toolchains, an SDK that shifts under you every release, a sandbox that fights you. All to chase an OS whose entire philosophy (opaque, proprietary, convention over purity) is the antithesis of Nix.

When we have to target solutions that cover wildly different platforms, the end result is muddled and limited. Beauty, elegance and innovation emerge when you apply constraints and restrict a problem.

## Flakes are meh.

Flakes are here to stay and yet their adoption is constantly [brought up](https://determinate.systems/blog/experimental-does-not-mean-unstable/) in order to validate its existence. I default to using it for my new projects, mostly because it's easier at this point and it seems annoyingly tied to the new CLI format.

Upon reflection though, I don't feel like I have gained anything really over `npins` or `niv`. Subjectively my `nix` evaluations feel slower as now I'm fetching many more `nixpkgs` or jump through hoops to make every flake follow each other defeating the whole purpose of separate trees.

## single-user install is great.

Unless you are sharing a laptop with your family or are using a mainframe from 1980, you won't have more than a single user on your machine. Despite this, the default installation we guide users towards is one designed for multiple users.

The multiple-user install adds unnecessary complexity many don't need or won't understand: a build daemon, pool of `nixbld` users, systemd service, etc... 

In contrast, the single-user install is radically simpler to run, operate and triage. I don't have to remember whether I am setting configuration for my "client" or the "daemon" and that there is a difference.

Multi-user is the right default for a shared build farm. It is _overkill_ for the single human it's actually installed on the majority of the time.


## Think bigger.

Nix is the closest thing we have to a solution where we can rebuild the entire world reproducibly. It is used by the Software Heritage Foundation as a way to reliably collect, preserve, and share all software that is publicly available in source code form [[cite](https://docs.softwareheritage.org/user/software-origins/nixguix.html)].

[![midwit nix meme](/assets/images/midwit_nix_meme_50p.png)](/assets/images/midwit_nix_meme.png)

Some of the most amazing technology that exists in this world exists when one can make changes at multiple layers throughout the stack. This is the _secret sauce_ to many of the hyperscalers of today. This is table-stakes for NixOS. You can implement a solution that requires new: application, compiler, library, runtime and kernel all within a **single commit**.

Despite the ability to wildly diverge from traditional distributions, innovate and differentiate, we largely replicate the status-quo -- albeit more reproducible. Whether it's constraints imposed by needing to accommodate alternate platforms (e.g. macOS) or fearing alienating more novice-users we limit the potential of what Nix could do.

Are you pissed off? Let us still be friends.