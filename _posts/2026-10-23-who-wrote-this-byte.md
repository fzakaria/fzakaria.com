---
layout: post
title: 'Who wrote this byte?'
date: 2026-10-23 10:00 -0700
excerpt_separator: <!--more-->
---

_git blame for your build's bytes._ 🔍

A build is _bit reproducible_ when the same inputs give the same bytes. 

Why does reproducibility matter? They provide certainty that software is genuine and has not been tampered with. See [reproducible-builds.org](https://reproducible-builds.org).

Nix is infamously **not** bit reproducible, but rather *input-addressed*: the hash of a package is calculated from the inputs rather than the output.

<!--more-->

We still prefer though to have bit reproducibility, because it allows us to verify that the package we downloaded is the same as the one built from source. It is something many packages aspire to achieve.

When the outputs differ, you want to know why. The first step is to find the bytes that differ, and the second is to find the program that wrote them.

Finding the cause of a difference has traditionally been the challenging part of process making builds reproducible...until now!

I have been building [Rewind VM](https://rewindvm.dev), a deterministic virtual machine that can record and replay builds, and it now has a new command to find the program that wrote a byte that differs between two runs: `rewind blame`.

> **Aside:**
> I wrote about [Rewind VM](https://rewindvm.dev) first in [a flaky build you only catch once]({% post_url 2026-10-01-rewind-vm-a-flaky-build-you-only-catch-once %}), and then about [properties]({% post_url 2026-10-14-always-sometimes-never %}).
{: .alert .alert-note }

Let's see how it works, first with a small example.

## A small build that is not reproducible

Let's start with a made-up library, [`tiles`](https://github.com/fzakaria/rewindvm/tree/main/examples/tiles), that writes its pkg-config file with a short
Python script.[^tiles] The script collects the packages the library links against into a
`set`:

[^tiles]: [nixpkgs](https://github.com/nixos/nixpkgs) sets `PYTHONHASHSEED=0` that circumvents this bug.

```python
requires = set()
for deps in PARTS.values():
    requires.update(deps)

print(f"Requires.private: {', '.join(requires)}")
```

Python iterates a set of strings in an order drawn from its _hash seed_, which is random
for every new process.

In Rewind the seed is an input: `--seed N` decides every random
number the build draws. Let's build `tiles` under eight seeds:

```console
$ rewind check --epoch 1790985600 --seeds 8 --schedules 0 --all --no-narrow \
    github:fzakaria/rewindvm#tiles
rewind: packing 75 store paths for tiles-0.2.0
rewind: 8 random seeds, each run under schedule 0 and 0 other schedules: 8 runs
seed  0 schedule   0: exited:0       4035 steps  d20b5efd388d  run 8d29a01cc44264b4
seed  1 schedule   0: exited:0       4035 steps  b4501793e383  run c4bd9260b7719942
seed  2 schedule   0: exited:0       4035 steps  0cd5db6c5c2c  run a5448b8d2ca19c18
seed  3 schedule   0: exited:0       4035 steps  24f18f09c329  run b03811e63cc68d97
seed  4 schedule   0: exited:0       4035 steps  b4501793e383  run ed28383bea49e84f
seed  5 schedule   0: exited:0       4035 steps  5e1f0a457cbe  run f5e8d2ac2c4b7782
seed  6 schedule   0: exited:0       4035 steps  d20b5efd388d  run af24df10ae7ac1e8
seed  7 schedule   0: exited:0       4035 steps  b4501793e383  run b5268e20063c5a9e
6 of 7 other runs ended differently
```

The third column from the end is the start of the output's hash (i.e. `d20b5efd388d`), and the last is the run id. 

We did eight builds and got five different outputs. 😬
Our build is not reproducible.

`rewind diff` shows what differs between two runs, without leaving Rewind:

```console
$ rewind diff --file /build/tiles/tiles.pc 8d29a01c c4bd9260
tiles.pc differs, first at line 7.
...
  Name: tiles
  Description: Tile a large image into small ones
  Version: 0.2.0
- Requires.private: pixman-1, libpng, zlib
+ Requires.private: zlib, pixman-1, libpng
  Libs: -L${libdir} -ltiles
```

You could ascertain this from tools like [diffoscope](https://diffoscope.org/) but would be left to figure out what program wrote the differing bytes. `rewind blame` does that for you.

[![Drake meme. Drake turns away from "diffoscope: the two files differ" and points approvingly at "rewind blame: python3 wrote that byte at step 2,909".](/assets/images/rewind_drake_blame_meme.png)](/assets/images/rewind_drake_blame_meme.png)
{: style="--image-width: 22rem"}

## rewind blame

`rewind blame` takes two runs and a file, and names the program that wrote the first byte
that differs:

```console
$ rewind blame 8d29a01c c4bd9260 \
    /nix/store/ihhhzc5q...-tiles-0.2.0/lib/pkgconfig/tiles.pc
tiles.pc differs at byte 178. python3 (pid 112) wrote that byte at step
2,909 in run 8d29a01c and at step 2,909 in run c4bd9260.

22 of 227 bytes differ. The bytes from byte 178:
  8d29a01c  70 69 78 6d 61 6e 2d 31 2c 20 6c 69 62 70 6e 67  |pixman-1, libpng|
  c4bd9260  7a 6c 69 62 2c 20 70 69 78 6d 61 6e 2d 31 2c 20  |zlib, pixman-1, |

Who wrote the file in run 8d29a01c, from the last writer back:
  install (pid 122) copied it from /build/tiles/tiles.pc, starting at
    step 3,157. Its source already differs, so the copy did not cause
    the difference.
  bash (pid 112) wrote /build/tiles/tiles.pc, starting at step 2,796. It
    is the first writer, and the file already differs when it is done.
Run c4bd9260 made the file the same way, with the same programs.

In both runs, one write of 227 bytes, from byte 0, set byte 178.

python3 ran with the same command line in both runs, so the difference
comes from something it read or from randomness.

What python3 read:
  1 file that the build made, all the same in both runs:
    /build/tiles/gen-pc.py.
  31 other files that the build did not make, such as programs and
    libraries.

Likely cause: something inside python3 (pid 112), such as randomness or
the order its threads ran in. Its command line and the files the build
made that it read are the same in both runs.
```


The output is a little long, but it is all relevant and the first line has the answer: `python3` wrote that byte at step 2,909.[^wrapped] 

[^wrapped]: The output is real, with long lines wrapped to fit and the store path shortened.

The rest of the text is how the tool determined the provenance of the byte change.


1. The file in `$out` was copied there by `install`. The file it copied from already
   differed, so the copy is not to blame.
2. That file, `/build/tiles/tiles.pc`, was first written by pid 112. It was still `bash`
   when it opened the file for the `>` redirect, and then became `python3`. One write of
   227 bytes set byte 178.
3. `python3` had the same command line in both runs, and the only file from the build it
   read, `gen-pc.py`, was the same in both runs.

The tool highlights that the difference was made _inside_ python3, and we know that the seed is the one input that changed. 🎯

<figure>
<svg viewBox="0 0 620 330" role="img"
     style="display:block;margin-inline:auto;max-width:38rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="The chain blame follows for tiles. tiles.pc in the output differs at byte 178. install copied it at step 3,157 from /build/tiles/tiles.pc, which already differed, so the copy is not the cause. python3 gen-pc.py wrote /build/tiles/tiles.pc at step 2,909 and was the first writer. python3 had the same command line and read the same gen-pc.py in both runs, so the difference comes from inside python3: its hash seed.">
  <defs>
    <marker id="wb-up" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor"/>
    </marker>
  </defs>
  <rect x="10" y="10" width="250" height="44" rx="6" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="135" y="37" font-size="14" text-anchor="middle" fill="currentColor">$out/…/tiles.pc</text>
  <text x="280" y="37" font-size="13" fill="currentColor" opacity="0.75">differs at byte 178</text>
  <line x1="135" y1="108" x2="135" y2="60" stroke="currentColor" stroke-width="1.5" marker-end="url(#wb-up)"/>
  <text x="150" y="80" font-size="13" fill="currentColor">install copied it, step 3,157</text>
  <text x="150" y="98" font-size="13" fill="currentColor" opacity="0.6">its source already differed: not the cause</text>
  <rect x="10" y="112" width="250" height="44" rx="6" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="135" y="139" font-size="14" text-anchor="middle" fill="currentColor">/build/tiles/tiles.pc</text>
  <line x1="135" y1="210" x2="135" y2="162" stroke="#b1201d" stroke-width="2" marker-end="url(#wb-up)"/>
  <text x="150" y="182" font-size="13" fill="#b1201d" font-weight="600">python3 wrote byte 178, step 2,909</text>
  <text x="150" y="200" font-size="13" fill="currentColor" opacity="0.6">the first writer: the difference starts here</text>
  <rect x="10" y="214" width="250" height="44" rx="6" fill="none" stroke="#b1201d" stroke-width="2"/>
  <text x="135" y="241" font-size="14" text-anchor="middle" fill="currentColor">python3 gen-pc.py</text>
  <text x="280" y="234" font-size="13" fill="currentColor" opacity="0.75">same command line</text>
  <text x="280" y="252" font-size="13" fill="currentColor" opacity="0.75">same gen-pc.py in both runs</text>
  <text x="10" y="300" font-size="14" fill="#b1201d" font-weight="600">→ the cause is inside python3: its hash seed</text>
</svg>
</figure>

The fix is straightforward, we wrap the list with `sorted()`, and every seed then builds the same `tiles.pc`. 🙌

```diff
-print(f"Requires.private: {', '.join(requires)}")
+print(f"Requires.private: {', '.join(sorted(requires))}")
```

## How it knows

How can the command deduce the lineage of a byte?

The trick is that blame does not have to _search_ for the write. The run already recorded
it.😯

Every Rewind run records each program's starts, exits, opens for writing and renames,
each at its step.[^step] For `blame`, the guest's Linux kernel also keeps two kinds
of record:

[^step]: A _step_ is a moment the virtual machine stops and hands control to Rewind, such as when a program starts or writes to the terminal. Step 2,909 is the same moment every time you replay the run.

- a _write record_ for every write to a file: which thread, which file, where in the file
  and how many bytes;
- an _open record_ for every file a program opens, for reading or for writing.

The records are written to a buffer in the guest kernel's memory, a 1MiB buffer, and Rewind copies them into `trace.bin` at the intervals it has stop the VM anyways. This keeps the runs identical and performant.

<figure>
<svg viewBox="0 0 620 230" role="img"
     style="display:block;margin-inline:auto;max-width:38rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="A timeline of a build. Programs write and open files between steps, and each write or open adds a record to a buffer in the guest kernel's memory. At each step Rewind already takes, it copies the buffer into trace.bin and empties it. No step is added for the records.">
  <defs>
    <marker id="wb-down" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor"/>
    </marker>
  </defs>
  <circle cx="16" cy="24" r="6" fill="#b1201d"/>
  <text x="28" y="28" font-size="13" fill="currentColor" opacity="0.75">write</text>
  <circle cx="86" cy="24" r="6" fill="none" stroke="#b1201d" stroke-width="2"/>
  <text x="98" y="28" font-size="13" fill="currentColor" opacity="0.75">open</text>
  <line x1="10" y1="60" x2="610" y2="60" stroke="currentColor" stroke-width="1" opacity="0.4"/>
  <circle cx="60" cy="60" r="6" fill="#b1201d"/>
  <circle cx="95" cy="60" r="6" fill="none" stroke="#b1201d" stroke-width="2"/>
  <circle cx="130" cy="60" r="6" fill="#b1201d"/>
  <circle cx="250" cy="60" r="6" fill="#b1201d"/>
  <circle cx="285" cy="60" r="6" fill="#b1201d"/>
  <circle cx="320" cy="60" r="6" fill="none" stroke="#b1201d" stroke-width="2"/>
  <circle cx="355" cy="60" r="6" fill="#b1201d"/>
  <circle cx="470" cy="60" r="6" fill="none" stroke="#b1201d" stroke-width="2"/>
  <circle cx="505" cy="60" r="6" fill="#b1201d"/>
  <line x1="190" y1="36" x2="190" y2="150" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 4"/>
  <line x1="410" y1="36" x2="410" y2="150" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 4"/>
  <line x1="580" y1="36" x2="580" y2="150" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 4"/>
  <text x="190" y="28" font-size="12" text-anchor="middle" fill="currentColor">step</text>
  <text x="410" y="28" font-size="12" text-anchor="middle" fill="currentColor">step</text>
  <text x="580" y="28" font-size="12" text-anchor="middle" fill="currentColor">step</text>
  <rect x="40" y="76" width="110" height="20" rx="3" fill="currentColor" opacity="0.08"/>
  <text x="95" y="91" font-size="11" text-anchor="middle" fill="currentColor" opacity="0.75">buffer</text>
  <rect x="230" y="76" width="140" height="20" rx="3" fill="currentColor" opacity="0.08"/>
  <text x="300" y="91" font-size="11" text-anchor="middle" fill="currentColor" opacity="0.75">buffer</text>
  <rect x="450" y="76" width="80" height="20" rx="3" fill="currentColor" opacity="0.08"/>
  <text x="490" y="91" font-size="11" text-anchor="middle" fill="currentColor" opacity="0.75">buffer</text>
  <line x1="190" y1="150" x2="190" y2="174" stroke="currentColor" stroke-width="1.5" marker-end="url(#wb-down)"/>
  <line x1="410" y1="150" x2="410" y2="174" stroke="currentColor" stroke-width="1.5" marker-end="url(#wb-down)"/>
  <line x1="580" y1="150" x2="580" y2="174" stroke="currentColor" stroke-width="1.5" marker-end="url(#wb-down)"/>
  <rect x="10" y="180" width="600" height="34" rx="6" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="310" y="202" font-size="13" text-anchor="middle" fill="currentColor">trace.bin: the records, saved with the run</text>
</svg>
</figure>

_I measured the cost of the records in Rewind 0.9.0, and it is small enough to leave them on for every run._

With the records, blame finds the write that set the byte by reading the trace, without
replaying either run. It only replays to read a file's contents at a step.

## In the app

The Rewind app shows the same thing visually. Open the two runs side by side:

```console
$ rewind open 8d29a01c --compare c4bd9260
```

The _Compare_ tab now lists the files that differ between the two runs:

[![The Rewind app's Files that differ tab for seed 0's and seed 1's tiles runs: 2 of the 5 files the runs left behind differ, /build/tiles/tiles.pc and the installed copy, each with 22 of 227 bytes differing, first at byte 178](/assets/images/rewind-repro-files-crop.png)](/assets/images/rewind-repro-files.png)
{: style="--image-width: 30rem"}

We can also click a file to see it from both runs. Here that is step 2,909, with `python3 gen-pc.py` in the process tree and its command in the build log:

[![The Rewind app at step 2,909: the process tree with python3 gen-pc.py, pid 112, under bash and make, and tiles.pc from both runs one under the other, with this run's Requires.private line in amber and the other run's in blue](/assets/images/rewind-repro-write-crop.png)](/assets/images/rewind-repro-write.png)

At that moment, we can explore the complete VM state: the files as they were, the process tree, a fork, or gdb. The app shows the same information as `rewind blame`, but visually and interactively.

## Beyond seeds

In order to capture possibilities of non-determinism, we need to vary any input that can change the output.  The seed decides random numbers. `rewind check` also varies the _schedule_, the order threads take turns, which is how parallel `make` and `ninja` end up with different
outputs. 

Turns out there is a third input that can change the output: the order of directories. The order of files in a directory is not guaranteed to be the same across machines, or even across runs on the same machine although many builds assume it to be.

We can also vary the order of directories in Rewind which helps catch even more non-determinism with `--dirents`. This is useful for builds that depend on the order of files in a directory.

The [`plugins`](https://github.com/fzakaria/rewindvm/tree/main/examples/plugins) example writes an index of the plugins it ships, in the order `os.listdir` returns. The example builds the same output under every seed, but not under every directory order:[^plugins]

[^plugins]: It is the second example in the [reproducible builds tutorial](https://rewindvm.dev/tutorials/repro.html).

```console
$ rewind check --epoch 1790985600 --seeds 1 --schedules 0 --all --no-narrow \
    --dirents 3 github:fzakaria/rewindvm#plugins
dirents  0 schedule   0: exited:0       3885 steps  77b96f07540a  run 8d64b8b46c5c8b68
dirents  1 schedule   0: exited:0       3885 steps  3d555b541296  run e4c221b26df20a9c
dirents  2 schedule   0: exited:0       3885 steps  925dde4ef23a  run 593a9430de55e469
dirents  3 schedule   0: exited:0       3885 steps  abd7877043a8  run 067e05c27c9ceb09
3 of 3 other runs ended differently
```

We have four directory orders, and four different outputs. Each one lists the same five plugins in another order:

<figure>
<svg viewBox="0 0 620 184" role="img"
     style="display:block;margin-inline:auto;max-width:38rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="The order plugins.txt lists the five plugins in. Stock order: sharpen, rotate, resize, crop, blur. Under rewind.dirents=1: sharpen, crop, blur, rotate, resize. Under rewind.dirents=2: sharpen, resize, crop, rotate, blur. With sorted(): blur, crop, resize, rotate, sharpen, under every key.">
  <text x="0" y="28" font-size="13" fill="currentColor" opacity="0.75">stock order</text>
  <rect x="150" y="8" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="192" y="28" font-size="13" text-anchor="middle" fill="currentColor">sharpen</text>
  <rect x="244" y="8" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="286" y="28" font-size="13" text-anchor="middle" fill="currentColor">rotate</text>
  <rect x="338" y="8" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="380" y="28" font-size="13" text-anchor="middle" fill="currentColor">resize</text>
  <rect x="432" y="8" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="474" y="28" font-size="13" text-anchor="middle" fill="currentColor">crop</text>
  <rect x="526" y="8" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="568" y="28" font-size="13" text-anchor="middle" fill="currentColor">blur</text>
  <text x="0" y="72" font-size="13" fill="currentColor" opacity="0.75">dirents=1</text>
  <rect x="150" y="52" width="84" height="30" rx="5" fill="none" stroke="#b1201d" stroke-width="1.5"/>
  <text x="192" y="72" font-size="13" text-anchor="middle" fill="#b1201d">sharpen</text>
  <rect x="244" y="52" width="84" height="30" rx="5" fill="none" stroke="#b1201d" stroke-width="1.5"/>
  <text x="286" y="72" font-size="13" text-anchor="middle" fill="#b1201d">crop</text>
  <rect x="338" y="52" width="84" height="30" rx="5" fill="none" stroke="#b1201d" stroke-width="1.5"/>
  <text x="380" y="72" font-size="13" text-anchor="middle" fill="#b1201d">blur</text>
  <rect x="432" y="52" width="84" height="30" rx="5" fill="none" stroke="#b1201d" stroke-width="1.5"/>
  <text x="474" y="72" font-size="13" text-anchor="middle" fill="#b1201d">rotate</text>
  <rect x="526" y="52" width="84" height="30" rx="5" fill="none" stroke="#b1201d" stroke-width="1.5"/>
  <text x="568" y="72" font-size="13" text-anchor="middle" fill="#b1201d">resize</text>
  <text x="0" y="116" font-size="13" fill="currentColor" opacity="0.75">dirents=2</text>
  <rect x="150" y="96" width="84" height="30" rx="5" fill="none" stroke="#1f5fa8" stroke-width="1.5"/>
  <text x="192" y="116" font-size="13" text-anchor="middle" fill="#1f5fa8">sharpen</text>
  <rect x="244" y="96" width="84" height="30" rx="5" fill="none" stroke="#1f5fa8" stroke-width="1.5"/>
  <text x="286" y="116" font-size="13" text-anchor="middle" fill="#1f5fa8">resize</text>
  <rect x="338" y="96" width="84" height="30" rx="5" fill="none" stroke="#1f5fa8" stroke-width="1.5"/>
  <text x="380" y="116" font-size="13" text-anchor="middle" fill="#1f5fa8">crop</text>
  <rect x="432" y="96" width="84" height="30" rx="5" fill="none" stroke="#1f5fa8" stroke-width="1.5"/>
  <text x="474" y="116" font-size="13" text-anchor="middle" fill="#1f5fa8">rotate</text>
  <rect x="526" y="96" width="84" height="30" rx="5" fill="none" stroke="#1f5fa8" stroke-width="1.5"/>
  <text x="568" y="116" font-size="13" text-anchor="middle" fill="#1f5fa8">blur</text>
  <text x="0" y="160" font-size="13" fill="currentColor" opacity="0.75">sorted()</text>
  <rect x="150" y="140" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="192" y="160" font-size="13" text-anchor="middle" fill="currentColor" font-weight="600">blur</text>
  <rect x="244" y="140" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="286" y="160" font-size="13" text-anchor="middle" fill="currentColor" font-weight="600">crop</text>
  <rect x="338" y="140" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="380" y="160" font-size="13" text-anchor="middle" fill="currentColor" font-weight="600">resize</text>
  <rect x="432" y="140" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="474" y="160" font-size="13" text-anchor="middle" fill="currentColor" font-weight="600">rotate</text>
  <rect x="526" y="140" width="84" height="30" rx="5" fill="none" stroke="currentColor" stroke-width="1.5"/>
  <text x="568" y="160" font-size="13" text-anchor="middle" fill="currentColor" font-weight="600">sharpen</text>
</svg>
</figure>

The fix is the same as before: `sorted(os.listdir(directory))`, and every key builds the same index.

Look closely and both examples are the same bug. Python iterates a set in hash order, and ext4 lists a directory in hash order. Change the seed behind the hash and the order changes with it.

[![meme about hash order for directories](/assets/images/rewind_always_hash_order_meme.png)](/assets/images/rewind_always_hash_order_meme.png)
{: style="--image-width: 22rem"}

## Try it

Finding the cause of a difference has traditionally been the challenging part of process making builds reproducible. Many [tools](https://reproducible-builds.org/tools/#tools-to-compare-build-artifacts-andor-detect-nondeterminism) exist to help detect nondeterminism but few actually give you the root cause.

Lowering the barrier to making builds reproducible is a goal of Rewind VM, and `rewind blame` is a step in that direction. Rewind VM is purpose built to work in the Nix ecosystem and helping make more Nix packages reproducible is a worthy goal.

```console
$ curl -fsSL https://rewindvm.dev/install | sh
$ rewind check --seeds 8 --schedules 0 --all --no-narrow \
    github:fzakaria/rewindvm#tiles
```

If you want a deeper dive on this subject, check out the [reproducible builds tutorial](https://rewindvm.dev/tutorials/repro.html), which walks through
both examples step by step, including the directory-order one.

If you maintain a package that does not reproduce and you do not know why, try blame on
it, and tell me what it finds. I would love to add it to the
[leaderboard](https://rewindvm.dev/bugs.html). 🏆
