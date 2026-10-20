---
layout: post
title: "No quarter for gaps"
date: 2026-10-25 09:00 -0700
---

The advent of large language models has changed the economics of closing gaps in software stacks.

[![a photo of nixpkgs ruby manual showing bundix not working for native gems](/assets/images/nixpkgs_ruby_manual_bundix.png)](/assets/images/nixpkgs_ruby_manual_bundix.png)

This is in the nixpkgs manual, in the Ruby section, under
"Platform-specific gems" [[ref]](https://nixos.org/manual/nixpkgs/unstable/#ruby-platform-specif-gems). The pull request ([PR#68](https://github.com/nix-community/bundix/pull/68)) it points to was opened in October 2019 and closed, unmerged, in August 2026, with: "Closing as stale. I no longer work with bundix. Feel free to take it over." [[cite]](https://github.com/nix-community/bundix/pull/68#issuecomment-5166951772)

> **Aside**
> There are alternatives that have sprung up but they all have unique gaps or are
> not widely communicated as _blessed_ solutions. The manual itself also does
> recommend a workaround for the issue, but in practice I found it to not work in practice.
{: .alert .alert-note }


Every ecosystem has gaps everyone has learned to step around. They survive because there
is just _too much stuff_ to do. We live with these warts and gaps because the cost of fixing them is either too high or there are more important things to do.

That economics is gone.

[![dhh yelling about how little he is doing](/assets/images/dhh_yelling_about_doing_things.png)](/assets/images/dhh_yelling_about_doing_things.png)
{: style="--image-width: 20rem"}

We can have and expect amazing perfectly correct software stacks, because the cost of fixing gaps is now low enough that it is worth doing. The economics of software have changed.


The multiple days of typing are now an afternoon, _or less_, of directing and reading to an AI agent. In the case of Nix and Ruby, I wrote the Nix side of a Bundler lockfile solution, [gemlock.nix](https://github.com/fzakaria/gemlock.nix), within an hour, removing days of misery I hit while running this blog.

While AI generated code _may_ suffer from slop, it is a growing skill how to wield AI to produce correct verifyable code. Nix is amazingly well-suited as it gives the agents a reproducible test-bed with which to verify the correctness of the code they produce. 

The economics of software have changed, and we can now expect to have _no quarter_ for gaps in our stacks.