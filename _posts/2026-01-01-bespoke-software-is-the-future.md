---
layout: post
title: Bespoke software is the future
date: 2026-01-01 12:00 -0800
---

At Google, some of the engineers would joke, _self-deprecatingly_,  that the software internally was not particularly exceptional but rather Google's dominance was an example of the power of network effects: when software is custom tailored to work well with each other.

This is often cited externally to Google, or similar FAANG companies, as indulgent "NIH" (Not Invented Here) syndrome; where the prevailing practice is to pick generalized software solutions, preferably open-source, off-the shelf.

The problem with these generalized solutions is that, well, they are generalized and rarely fit well together. 🙄  Engineers are trained to be DRY (Don't Repeat Yourself), and love abstractions. As a tool tries to solve more problems, the abstraction becomes leakier and ill-fitting. It becomes a general-purpose tax.

If you only need 10% of a software solution, you pay for the remaining 90% via the abstractions they impose. 🫠

Internally to a company, however, we are taught that unused code is a liability. We often celebrate negative pull-requests as valuable clean-up work with the understanding that smaller code-bases are simpler to understand, operate and optimize.

Yet for our most of our infrastructure tooling, we continue to bloat solutions and tout support despite miniscule user bases.

This is probably one of the areas I am most excited about with the ability to leverage LLM for software creation.

I recently spent time investigating linkers in [previous]({% post_url 2025-12-28-huge-binaries %}) [posts]({% post_url 2025-12-29-huge-binaries-i-thunk-therefore-i-am %}) such as LLVM's [lld](http://lld.llvm.org/).

I found LLVM to be a pretty polished codebase with lots of documentation. Despite the high-quality, navigating the codebase is challenging as it's a mass of interfaces and abstractions in order to support: multiple object file formats, 13+ ISAs, a slough of features (i.e. linker scripts ) and multiple operating systems.

Instead, I leveraged LLMs to help me design and write [µld](https://github.com/fzakaria/uld), a tiny opinionated linker in Rust that only targets ELF, x86_64, static linking and barebone feature-set.

It shouldn't be a surprise to anyone that the end result is a codebase that I can audit, educate myself and can easily grow to support additional improvements and optimizations.

The surprising bit, especially to me, was how easy it was to author and write within a very short period of time (1-2 days).

That means smaller companies, without the coffer of similar FAANG companies, can also pursue bespoke custom tailored software for their needs.

This future is well-suited for tooling such as [Nix](https://nixos.org). Nix is the perfect vehicle to help build custom tooling as you have a playground that is designed to build the world similar to a monorepo.

We need to begin to cut away legacy in our tooling and build software that solves specific problems. The end-result will be smaller, easier to manage and better integrated. Where this might have seemed unattainable for most, LLMs will democratize this possibility.

I'm excited for the bespoke future.