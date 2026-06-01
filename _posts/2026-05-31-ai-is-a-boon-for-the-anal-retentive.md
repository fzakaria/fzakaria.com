---
layout: post
title: AI is a Boon for the Anal-Retentive
date: 2026-05-31 20:15 -0700
---

I guess it's my turn to write an "AI article". 🫠

It's Saturday evening and I'm late into my 3rd project, one where I would never have gotten so far without the help of recent advancements in AI, all thanks to LLMs. The realization that I've been able to accomplish personal projects that evaded me for so long was really remarkable and I feel fortunate...at least for now. I can see the knobs slowly dialing back, the amount of tokens we are given pro bono is quickly diminishing.

A typical project, B.O. (Before Opus 4.6), was one where I think of an idea that inevitably needs a frontend component. I then spend 3-7 days researching the latest on frontend build patterns, frameworks and trends. I'm then mired in choice and complexity only to lose focus, or lose interest in bit-twiddling CSS (something I never quite truly learned).

My latest project, [Zephyr](https://zephyr.exe.xyz/), is my attempt to build a weather wind station powered by battery & solar that can send me updates via cellular network.

[![zephyr breadboard](/assets/images/zephyr_breadboard_50p.jpg)](/assets/images/zephyr_breadboard.jpg)

The project involves: writing firmware via Rust `nostd` to an ESP32 board, sending commands to the modem to initiate the HTTPS requests, connecting the anemometer and wind vane to the device, working with a breadboard (I can do hardware now too!) and writing a frontend website to display the results.

To say this project is outside of my wheelhouse is _an understatement_.

However, I have been able to get surprisingly far asking for advice and guidance, and leaning on the LLM to bootstrap some code. I have had to be incredibly thoughtful in guiding it to relevant schematics, examples and manuals since writing the firmware for the board was incredibly tricky with all the various knobs that can be tuned.

The project prior to that was one dedicated to recording surfing entries: [http://surfing.exe.xyz/](http://surfing.exe.xyz/). The project prior to that was [https://checkthisdealforme.com/](https://checkthisdealforme.com/), a small website where you can quickly appraise items you either want to buy or sell.

> You might notice a theme that all these projects leverage [https://exe.dev/](https://exe.dev/). It's a platform I've enjoyed that has similarly taken all the infrastructure molasses out when working on small projects.

All these projects would never have made it this far. I'm far too anal-retentive. That quality is part of my personality. It has often been a strength when dealing with the mire of complexity at $DAYJOB$ but has been a burden for things whose complexity I am happy to relinquish.

Thank you, large language models, for freeing me of my anal-retentiveness when necessary.
While others use the term "slop" as a form of insult, here it's been a boon and a welcomed one.
