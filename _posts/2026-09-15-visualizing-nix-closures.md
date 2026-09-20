---
layout: post
title: 'Visualizing Nix closures'
date: 2026-09-15 20:00 -0700
excerpt_separator: <!--more-->
---

> **tl;dr** [seenix.dev](https://seenix.dev/) lays every byte of a Nix closure out on a map, one pixel per byte, and lets you zoom from a whole NixOS system down to the hex of `libc.so.6`. Try [hello](https://seenix.dev/?path=/nix/store/xl1h9i29pgq2q5cszjhm5wpfxfbbqwyi-hello-2.12.3), [firefox](https://seenix.dev/?path=/nix/store/5l9n8bw1wifj5kdr8gzlrkk1b510dfiv-firefox-155.0.1) or [a GNOME desktop](https://seenix.dev/?path=/nix/store/5ryb0d1a261bgvxqqd436yx8i7j44qlc-nixos-system-nixos-26.11pre1074086.efe6f071ede9&mode=package). Nothing runs on a server.
{: .alert .alert-note }

With the advent of LLMs I keep tugging at any _crazy_ question I ask myself. I know there is the _anti-AI_ crowd and they will happily proclaim anything pursued in this vein as "slop" but I am feeling fortunate to be able to explore these questions.

<!--more-->

My recent _itch_ was to ask "what does a Nix closure look like?" and to answer it in a way that is _interactive_ and _visual_. I wanted to see the bytes, not just the store paths. I had come across [binvis.io](https://binvis.io) on Hacker News and I found it a compelling way to look at data. I personally never found a need for it, but I found it fascinating none-the-less.[^cortesi] 

[^cortesi]: Aldo Cortesi's [writing on visualising binaries](https://corte.si/posts/visualisation/binvis/) is a great resource on this.

The timing for this itch was perfect. I noticed a trending thread on [X](https://x.com/HSVSphere/status/2045193277977100772?s=20) where a Python binary seemingly includes `ffmpeg` and `ruby`. 🤷

[![Photo of the tweet of HSVSphere](/assets/images/remarshal_tweet_hsvsphere.png)](/assets/images/remarshal_tweet_hsvsphere.png)
{: style="--image-width: 25rem"}

I built that tool. You can check it out at [seenix.dev](https://seenix.dev/). It is a single-page web app that runs entirely in your browser, with no server. It fetches the narinfos of a closure and lays them out on a map, one pixel per byte, and lets you zoom in to see the bytes themselves.

We can visualize the closure of that binary, `remarshal`, and see if it really does include those two packages. Turns out it does not. The closure is 41 store paths and 234 MiB, with no `ffmpeg` and no `ruby` among them. Turns out those dependencies are build-time and are not included in the final runtime closure.

[![remarshal 1.3.0's runtime closure in seenix, coloured by package and with remarshal itself pinned: 41 store paths and 234 MiB, with no ffmpeg and no ruby among them](/assets/images/seenix-remarshal-package.png)](/assets/images/seenix-remarshal-package.png)

We can visualize much larger closures. Here is a GNOME desktop: 1,324 store paths and 5.3 GiB, each colour one package.

[![A NixOS GNOME system closure drawn as a map: a patchwork of coloured regions, one per store path, each one connected blob](/assets/images/seenix-gnome-packages.png)](/assets/images/seenix-gnome-packages.png)

That picture needed zero NAR downloads. It was laid out in 3 ms from the narinfos alone. 🤯

# One byte, one pixel

The "trick" I learned to make this visualization possible, is the [Hilbert curve](https://en.wikipedia.org/wiki/Hilbert_curve). A Hilbert curve is a single, unbroken line that folds back and forth such that it completely fills up a flat square. **It is a fractal**.

![gif of the hilbert curve](/assets/images/hilbert_curve.gif)

Every store path in the closure is sorted by name (the root first) and their NARs are concatenated into one long line of bytes. The Hilbert curve folds that line into a square, so byte _n_ is pixel _n_ along the curve.

![Three store paths, hello, glibc and libidn2, laid end to end along an 8 by 8 Hilbert curve. Each path fills one connected region, and the curve continues dashed through the padding after the last byte.](/assets/images/seenix-hilbert-layout.png){: style="--image-width: 24rem"}

The Hilbert curve has two properties that lend itself nicely to visualize binaries and as a result Nix closures:

**Bytes that are near each other in a file stay near each other on the map.** A NAR is a single contiguous range of bytes, so a store path is a single contiguous region on the map. A file inside that store path is a smaller contiguous region, and a section inside that file is smaller still and so forth.

**Squares are just byte ranges.** Here's a tiny 4×4 map. Each number is the byte that lands on that pixel:

```
 0   1  14  15
 3   2  13  12
 4   7   8  11
 5   6   9  10
```

That means we can easily place a store path on the map by knowing its starting byte and its size. That's what makes the map cheap to draw.[^padding]

[^padding]: This is why the world is always a power of four bytes. hello's closure is 36 MiB, which fills a bit over half of a 64 MiB square, and the rest is drawn as background.

The layout only needs each path's `NarSize`, which every narinfo carries, so the whole map exists before a single NAR is downloaded. Hovering already tells you which store path you are pointing at, its size, its _retained size_ (the bytes that would leave the closure without it) and a "why is this here" chain back to the root.

# Zoom and enhance

As you zoom in, the NARs on screen are fetched from the cache and the color fills in. Here is `hello`'s closure, most of which is glibc:

[![hello's closure in bytes mode: speckled regions of black, blue and red where machine code lives, and a large solid blue region of text](/assets/images/seenix-hello-bytes.png)](/assets/images/seenix-hello-bytes.png)

Blue is printable ASCII, red is high bytes, green is control bytes and black is `0x00`. The speckled top is machine code. The big solid blue area at the bottom is glibc's locale data, which is plain text.

Keep zooming and every pixel becomes a byte you can read. Hovering names the file inside the NAR, and for ELF files, the section.

[![A deep zoom where each cell is one byte printed in hex, with a tooltip reading glibc-2.42-84, lib/libc.so.6, .text](/assets/images/seenix-glibc-hex.png)](/assets/images/seenix-glibc-hex.png)

That is `.text` of `libc.so.6`, in your browser tab, fetched from [cache.nixos.org](https://cache.nixos.org), **without any server**. 😈

# Why though?

Does everything need a purpose? Sometimes something is fun to make and to use with no real purpose.

For fun, I even added a Save PNG button, and it saves the view at the canvas's full resolution. The ultimate ricing of your NixOS system: a pixel image of your desktop closure. Can [Omarchy](https://omarchy.org/) do that? 😎

Anything you can export works:

```console
$ nix path-info -r --json /run/current-system > closure.json
```

Drop the file and see the map. You can provide additional Nix binary caches to fetch NARs from as well.

The source is at [github.com/fzakaria/seenix](https://github.com/fzakaria/seenix). [Go look at something big.](https://seenix.dev/?path=/nix/store/5ryb0d1a261bgvxqqd436yx8i7j44qlc-nixos-system-nixos-26.11pre1074086.efe6f071ede9&mode=package)

Build without purpose. Have fun.
