---
layout: post
title: Who does Anubis actually stop?
date: 2026-07-09 12:21 -0700
---

I have been working on a patch to the Linux kernel to support `$ORIGIN` for the interpreter (`PT_INTERP`) via bpf in `binfmt_misc` [[thread](https://lore.kernel.org/linux-mm/20260622043934.179879-1-farid.m.zakaria@gmail.com/T/#t)].

Of course I'm leveraging an LLM to help me do this! To pre-seed the context of the LLM, I asked it to read the [https://lore.kernel.org/](https://lore.kernel.org/) thread.

[![Anubis challenge page](/assets/images/anubis-challenge_50p.png)](/assets/images/anubis-challenge.png)

Uh oh. Looks like they have adopted [Anubis](https://github.com/TecharoHQ/anubis), which is an HTTP proxy that requires _proof-of-work_ before allowing access to the resource.

Did this really do anything?

Unfortunately, no.

My AI diligently came up with **anubis-fetch**, which you can find at [https://github.com/fzakaria/anubis-fetch](https://github.com/fzakaria/anubis-fetch). The tool tries to natively solve the proof of work or, as a last resort, will launch Chromium to visit the URL.

> This tool also impersonates a real Chrome TLS/JA3 fingerprint natively via [req](https://req.cool/) so it clears passive Cloudflare blocking too. ☝️

```console
# HTML to stdout
$ anubis-fetch https://lore.kernel.org/linux-mm/some-thread/T/

# readable plain text
$ anubis-fetch --text https://lore.kernel.org/linux-mm/some-thread/T/
```

So who did we stop?

The exact adversary Anubis targets defeats it trivially.

The whole use of Anubis feels regressive and marginalizes those without access to "good" AI.

For a scraper, solving the Anubis challenge is a one-time, amortized-to-zero cost since the cookie can be cached and reused. For a human, it's seconds of spinner, battery drain on every fresh visit. They can't amortize anything amongst each other.

This "regressive tax" is paid even more so by those with weaker devices or who access the content on their phone. Clients that don't leverage JavaScript (e.g., text browsers (w3m/lynx), screen readers, RSS readers) are completely left out.

Did deploying Anubis stop any of the aforementioned bot-farms or are they mildly inconvenienced when they had to augment their bots to support a new proof of work solution briefly?

The irony is that Anubis's goal is to stop AI but it was incredibly easy for AI to circumvent it and yet the cost to humans and an open web remains.

With the presumption Anubis is now a regressive tax, how much does it cost us?

Every number here is a rough estimate. This is not a environmental argument at all since the bot-farmers and AI tools themselves are using many orders of magnitude more energy. Nevertheless, it's interesting to see how much time is spent doing proof-of-work challenges that marginalize people.

>  Difficulty `d` is the number of leading zero *hex* characters the hash must have, so the expected work per solve is `W = 16^d` hashes.

| Difficulty | Hashes / solve | Go native | Browser JS | Felt wall-clock |
| :--------- | :------------- | :-------- | :--------- | :-------------- |
| **4**      | 65,536         | ~1.3 ms   | ~130 ms    | ~1–5 s          |
| 5          | 1,048,576      | ~20 ms    | ~2 s       | ~5–15 s         |

_Difficulty 4 is the common default. Rates assumed: ~50 MH/s native (Go), ~0.5 MH/s in-browser JS; "felt" wall-clock includes page load, the worker, and the reload._

Let `C` be the number of Anubis challenge-solves per day, worldwide. Assume a felt time of `t = 2 s` and device energy `E = 20 J` per solve (screen + CPU).

- **Human-time / year** = `C × t × 365 / 3.15×10⁷`
- **Energy / year (kWh)** = `C × E × 365 / 3.6×10⁶`

| `C` (solves/day) | Human-time wasted / year | Energy / year |
| :--------------- | :----------------------- | :------------ |
| 1 M              | **~23 person-years**     | ~2 MWh        |
| 10 M             | **~230 person-years**    | ~20 MWh       |
| 100 M            | **~2,300 person-years**  | ~200 MWh      |

Collectively we are wasting an impressive amount of time waiting for access to websites; time we didn't spend before the AI era. As a human, time is precious and finite to me, whereas to a robot it is not.