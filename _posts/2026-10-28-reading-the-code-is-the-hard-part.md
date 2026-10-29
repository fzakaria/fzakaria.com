---
layout: post
title: 'Reading the code is the hard part'
date: 2026-10-28 10:00 -0700
excerpt_separator: <!--more-->
---

I have been stress testing [Rewind VM](https://rewindvm.dev), a deterministic VM, to work through the kinks, bugs and [dog-fooding](https://en.wikipedia.org/wiki/Eating_your_own_dog_food) the user-experience. Even having developed it myself, I continue to be wild-eye amazed at the magic of what it can do.

<!--more-->

Despite the magic, the ease of claiming to have a bug "reproduced deterministically", and the ease of narrowing it down to a single step, the hard part is still reading the code and understanding why it failed. Rewind can tell you what went wrong, but it cannot read the code.

This is a particular area that is ripe for AI assistance. Agents can already read the code and often find bugs. Unsurprisingly, when given a wealth of reliable data about what went wrong, they can pinpoint the bug in a way that is much more efficient than reading the code alone. The combination of deterministic runs and AI agents is incredibly powerful. 🪄

Finding the bugs in Rewind is easy. `rewind check` replays a test, script, or binary under many different thread schedules until one fails, then narrows the failure down to the single step. That leaves you, though, with a step number and potentially a large codebase, one you are unfamiliar with. The hard part is reading the code and understanding why it failed.


[![Gru's plan meme: "rewind check finds a failing schedule", "It narrows it to step 2682", "Now I read 3,000 lines of git", and Gru staring back at "Now I read 3,000 lines of git?"](/assets/images/rewind_gru_plan_meme.png)](/assets/images/rewind_gru_plan_meme.png)
{: style="--image-width: 22rem"}


Rewind can tell you what went wrong, but it cannot read the code for you. Rewind does however give you, _or an agent_, a lot of information about what went wrong. I pointed [Rewind VM](https://rewindvm.dev) at a cornicopia of tools, and unsurprisingly, it found bugs..._many bugs_. The best part is that it found them in a way that is reproducible and debuggable, which has led to the agents also easily providing the fixes as well.[^bugs]

[^bugs]: You can find all the bugs on the [bugs page](https://rewindvm.dev/bugs.html).


> **Aside:**
> New to Rewind? Start with [a flaky build you only catch once]({% post_url 2026-10-01-rewind-vm-a-flaky-build-you-only-catch-once %}) and [dafuq is a deterministic VM?]({% post_url 2026-10-24-dafuq-is-a-deterministic-vm %})
{: .alert .alert-note }

This is a small example of a bug that Rewind found in git, and how I used Rewind to find the bug and the line of code that caused it. The bug is in `git notes`, which attaches a note to a commit without changing the commit. The bug is that two notes, on two different commits, at the same time, can lose one of the notes.

## The bug

[`git notes`](https://git-scm.com/docs/git-notes) attaches a note to a commit without changing the commit. 

We can start with an idea for a simple test[^test]: create two notes, on two different commits, at the same time concurrently.

[^test]: This test demonstrates the race condition in `git notes` when adding notes concurrently. We can easily build this as a Nix derivation using [`runCommand`](https://nixos.org/manual/nix/stable/#sec-runcommand).

```bash
git notes add -m "note 1" HEAD~0 &
git notes add -m "note 2" HEAD~1 &
wait

# both commands exited 0, so both notes should be there
git notes show HEAD~0 && git notes show HEAD~1
```

```console?comments=true
$ rewind check --all --schedules 32 --property exit-zero .#notes2
schedule   1: exited:1             3167 steps    run e5e5a1ecd0195f8f  violates exit-zero
schedule   2: exited:1             3312 steps    run ea6889e56564e374  violates exit-zero
...
15 of 32 other schedules violated a property

step 2682 decides it: a request to switch threads there makes the run violate exit-zero
```
{: data-mark="5,7"}

When executed by Rewind, fifteen of thirty-two schedules lose a git-note, yet every `git notes add` still exits successfully.[^normal]

[^normal]: On a normal Linux machine, 25 of 30 runs lose one too, so this is not a Rewind-onlybug.

Now what?

## Ask the runs, not the code

A run in Rewind is a full trace of the build: every process, every file it wrote, and any file's contents at any step, that you replay to any point in time. **That is a lot of data**. Rewind does make it a little simpler to comb through the data though that help narrow the culprit.

<figure>
<svg viewBox="0 0 720 150" role="img"
     style="display:block;margin-inline:auto;max-width:44rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="Three boxes in a row joined by arrows. One: what ended differently, a file, an output or an exit status. Two: who wrote it, the process and the step, which rewind blame answers. Three: which line wrote it, which rewind where answers.">
  <style>
    .ch-box { fill: var(--paper-raised, #ebe6da); stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; }
    .ch-hot { fill: var(--accent-wash, #9e34131f); stroke: var(--accent, #9e3413); stroke-width: 1; }
    .ch-t { font-size: 13px; fill: var(--ink, #1a1815); }
    .ch-m { font-size: 11px; fill: var(--ink-muted, #565046); }
    .ch-c { font-size: 11px; fill: var(--ink-muted, #565046); }
    .ch-edge { stroke: var(--ink-faint, #6f685b); stroke-width: 1.25; fill: none; }
    .ch-head { fill: var(--ink-faint, #6f685b); }
  </style>
  <defs>
    <marker id="ch-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" class="ch-head"/>
    </marker>
  </defs>
  <rect x="10" y="20" width="200" height="80" rx="8" class="ch-box"/>
  <text x="110" y="52" text-anchor="middle" class="ch-t">what ended</text>
  <text x="110" y="70" text-anchor="middle" class="ch-t">differently?</text>
  <text x="110" y="124" text-anchor="middle" class="ch-c">rewind diff</text>
  <line x1="210" y1="60" x2="258" y2="60" class="ch-edge" marker-end="url(#ch-arrow)"/>
  <rect x="260" y="20" width="200" height="80" rx="8" class="ch-box"/>
  <text x="360" y="52" text-anchor="middle" class="ch-t">who wrote it,</text>
  <text x="360" y="70" text-anchor="middle" class="ch-t">and what did it read?</text>
  <text x="360" y="124" text-anchor="middle" class="ch-c">rewind blame</text>
  <line x1="460" y1="60" x2="508" y2="60" class="ch-edge" marker-end="url(#ch-arrow)"/>
  <rect x="510" y="20" width="200" height="80" rx="8" class="ch-hot"/>
  <text x="610" y="52" text-anchor="middle" class="ch-t">which line</text>
  <text x="610" y="70" text-anchor="middle" class="ch-t">wrote it?</text>
  <text x="610" y="124" text-anchor="middle" class="ch-c">rewind where</text>
</svg>
</figure>

None of the three knows anything about git, locks or races. They work on any program.

### What ended differently?

`rewind diff --outputs` compares the files the two runs left behind. This is like [diffoscope](https://diffoscope.org/) but on steroids 💉: it can compare any two runs, and it can compare the files at any step in the run, not just the final outputs.[^byte]

[^byte]: I have a [lengthier post]({% post_url 2026-10-23-who-wrote-this-byte %}) about how Rewind can help make your build bit-for-bit reproducible.

```console?comments=true
$ rewind diff --outputs 94c59fdf987c4944 ad0de5aec5a0be2d
3 of the 30 files the runs left behind differ:
  /build/r/.git/logs/refs/notes/commits: 36 of 465 bytes differ, first at byte 351
  /build/r/.git/refs/notes/commits: 36 of 41 bytes differ, first at byte 0
  /nix/store/014fz1lj7hmk5h3rzcaw0w4576md3bg9-git-notes2: only in the right run
```
{: data-mark="4"}

Our clue is that `.git/refs/notes/commits` is the ref that points at the latest notes commit, and it points at different commits in the two runs.

### Who wrote it, and what did it read?

`rewind blame` takes two runs and a file:

```console?comments=true
$ rewind blame 94c59fdf987c4944 ad0de5aec5a0be2d /build/r/.git/refs/notes/commits
commits differs at byte 0. git notes (pid 56) wrote that byte at step
2,751 in run 94c59fdf and at step 2,717 in run ad0de5ae.
...
Likely cause: git notes (pid 56) read /build/r/.git/refs/notes/commits
before git notes (pid 55) changed it at step 2,721 in run 94c59fdf,
and after that change in run ad0de5ae. It read an older version of
the file in run 94c59fdf.
```
{: data-mark="5-8"}

In this example, Rewind has given us pretty close to the smoking gun. The second `git notes add` read the notes before the first one had saved its own, then saved its version over the top: a read-modify-write race.

We can visualize this exact step in the Rewind GUI at the deciding step: both `git notes add` processes are alive (top box), and the first is halfway through saving, with its lock file written but not yet renamed into place (bottom box).

[![The Rewind app at step 2,682 of the failing run: a box around both git notes add processes in the process tree, and a box around refs/notes/commits.lock in the files list](/assets/images/rewind-git-notes-race-crop.png)](/assets/images/rewind-git-notes-race.png)

### Which line wrote it?

If we have access to debug symbols, which Nixpkgs provides,  `rewind where` shows where in git's own code a process was at a step. Here is pid 56 when it wrote the ref:

```console?comments=true
$ rewind where 94c59fdf987c4944 2754 --pid 56 --frames 8
process 56 (git), thread 56, at step 2754
#1 rename_tempfile (tempfile.c:347)
called from #2 commit_lock_file_to (/build/source/lockfile.h:364)
called from #3 commit_lock_file (lockfile.c:358)
called from #4 commit_ref (refs/files-backend.c:1889)
called from #5 files_transaction_finish (refs/files-backend.c:3381)
called from #6 ref_transaction_commit (refs.c:2806)
called from #7 refs_update_ref (refs.c:1592)
called from #8 commit_notes (notes-utils.c:64)
```
{: data-mark="10"}

We can then look at the code at a very specific line, and try to understand why it failed. 
In this case, [`notes-utils.c:64`](https://github.com/git/git/blob/8d1b215c01512b9658d4525c54ff9b9245f9a7e8/notes-utils.c#L64) updates the ref without checking that it still points where it did when the command loaded the notes with a lock.

Three questions, three commands, and I read one line of git. 🤓

## Who reads all of this?

The git notes failure is 2,936 steps and 1,937 events in one run, and `rewind check` made 33 runs. Going through one run is a lot of work, and going through all thirty-three is an unrealistic.

Recently, a friend told me AI has been really useful for parsing the [CAN bus](https://en.wikipedia.org/wiki/CAN_bus) of cars. The CAN bus is a firehose of messages from the car from every sensor, every button, every switch, and every light. LLMs have made managing the firehose of data easier.

I see the same emergence in Rewind. The run is also a firehose of events, and similarly, LLMs can help parse the firehose of events and find the bugs. Telling an LLM to investigate a bug with Rewind has been very effective. Narrowing the bug down to a single step and source lines, is especially helpful for an LLM as it keeps the context small and focused. At that point, the LLM can read the code and understand what went wrong, and very likely suggest a fix.

LLMs have a lot of stochasticity built into them. I have found that pairing them with more deterministic technologies such as [Nix](https://nixos.org/) and Rewind makes them more effective. I'm very optimistic about the
leveraging the combination of deterministic runs and LLMs to find and fix bugs in large codebases.

LLMs induce many of these bugs but now they can also fix them. 🙃