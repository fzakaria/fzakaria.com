---
layout: post
title: A TacoSprint 2026 Retrospective
date: 2026-06-29 07:46 -0700
---

This is my retrospective of [TacoSprint 2026](https://tacosprint.org/) that took place in June 2026 at La Saladita, Guerrero, Mexico.

For a while now, I have watched from the sidelines as Nixers around the world gathered for sprints: [OceanSprint](https://oceansprint.org/), [ThaigerSprint](https://thaigersprint.org/), [SaltSprint](https://saltsprint.org/), [TransylvaniaSprint](https://transylvaniasprint.org/), [AuroraSprint](https://aurorasprint.com/) and [NixCamp](https://nix.camp/).

> Wow, we Nixers sure do like our sprints! All of them also happen to be in Europe or East-Asia.

With an upcoming fourth baby on the way, I figured it was now-or-never to put words into action. I messaged [@domen](https://github.com/domenkozar), who organizes OceanSprint every year, and asked if he'd be interested in helping me set up the first sprint in North America. Domen is an avid surfer, a recurring theme in his OceanSprint, so I appealed to his inner-surfer and we spec'd out some places in North America that were both cost-effective _and_ had ample, amazing surf 🏄.

I had already been to the [Troncones](https://www.bontraveler.com/troncones-mexico/) and the [La Saladita](https://thesurfatlas.com/surfing-mexico/playa-la-saladita/) area, so my prior experience removed a large vector of the unknown. It seemed like a no-brainer. Domen was already going to be in South America in June, so the timing lined up nicely (+ summer is the swell season there!).

We set to work standing up a website and trying to attract sponsorship and attendees.

🦗

This was probably the hardest part of organizing a brand-new sprint. We had far lower turnout for registration and sponsorship than I foresaw. Several people responded on our application form, or directly that they were unsure about the safety of visiting Mexico, since the US Department of State had it under a travel advisory. Despite my best efforts to soothe everyone's fears, it remained a real hindrance.

> **Note**
> For those still on the fence for next year: the area felt extremely safe. We rented a house in a fairly secluded stretch that caters almost entirely to surfers. At no point did anyone feel uncomfortable or unsafe.
{: .alert .alert-note }

Getting there was its own small adventure. Flights were unusually challenging to book thanks to the World Cup soaking up demand across the region. The most dramatic casualty was Alex ([@adeci](https://github.com/adeci)), who managed to completely miss his connecting flight and arrived a three days late. To his credit, he showed up in great spirits and slotted right back in to hacking with the group like nothing happened.


Once everyone was settled, we fell into a rhythm that I can only describe as _suspiciously sustainable_:

```c
while (sprint) {
  surf();       // ~6am – 9am
  breakfast();
  hack();
  lunch();
  hack();
  surf();       // ~5pm – 8pm
  dinner();
  hack();
  sleep();
}
```

It was amazing to bookend each day with a surf at La Saladita's left point break. Surfing for me let's me enter _flow state_ very similar to when I am deep in thought hacking-away. It helped clear through a lot of built-up gunk and I often returned back with a clear itention or solution to a problem I had been working on.

One of the more unexpected wonderful part of the trip was the meal preparation from Gladys, our local cook, who pretty much cooked for us three times a day. We were extremely well-fed, which let us focus on the Nix-hacking and motivated me to make sure I kept up with the surfing to put off any weight gain 🫠.

The website will be updated to have a more formal summary of every contribution we managed to put forward and their current status however it was amazing to see how much work a group of nine people can put forward in a single week with a combined mission and passion for an ecosystem. Our work spanned dynamic linking, package relocatability, peer-to-peer remote builds, faster module systems in OCaml and cross-distribution packaging.

A few of my own threads, if you want to go deeper:

* [GuixPkgs: every Guix package, as a Nix flake]({% post_url 2026-06-25-guixpkgs-every-guix-package-as-a-nix-flake %})
* [Hijacking ELF entry points for NixOS compatibility, or wtf is wrap-buddy]({% post_url 2026-06-22-hijacking-elf-entry-points-for-nixos-compatibility-or-wtf-is-wrap-buddy %})
* [Nix needs relocatable binaries]({% post_url 2026-06-21-nix-needs-relocatable-binaries %})

LLM-based agents featured prominently throughout. We were fortunate to have [Geoff Huntley](https://ghuntley.com/) with us, who is quite the _AI-mazimizer_, spiritually guiding us and offering us some STOA insight in how we might want to explore leveraging AI.

Alan ([@alurm](https://github.com/alurm)), had the greatest idea for us to put together an academic style trip report. We worked together on the paper and the result is _Attention, Nix and Tacos Is All You Need_, a loving parody of a certain famous paper.

An arXiv submission is coming, but in the meantime you can read it below or [download it here](/assets/pdfs/Attention_Nix_and_Tacos_is_All_You_Need.pdf).

<object data="/assets/pdfs/Attention_Nix_and_Tacos_is_All_You_Need.pdf" type="application/pdf" width="100%" height="600px">
  <p>Your browser doesn't support embedded PDFs. You can <a href="/assets/pdfs/Attention_Nix_and_Tacos_is_All_You_Need.pdf">download it here</a> instead.</p>
</object>


We already agreed to organize the same sprint next year. I can't wait. This was **literally** the most enjoyable thing I've ever done as it combined my two passions (surfing & hacking) in a way I honestly did not think was possible all why producing a ton of value to the Nix ecosystem.

For a different vantage point, please check out the retrospectives from my fellow attendees!

* [Alan Urmancheev](https://alurm.github.io/blog/2026-06-26-tacosprint.html)
* [Jared Siegel](https://jrdsgl.com/nix-taco-sprint-2026/)
