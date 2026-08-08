---
layout: post
title: 'Nix wrote half of my debugger'
date: 2026-10-07 12:00 -0700
excerpt_separator: <!--more-->
---

A few days ago I wrote about [Rewind VM]({% post_url 2026-10-01-rewind-vm-a-flaky-build-you-only-catch-once %}),
a **deterministic VM** where every run of a Nix build is a pure function of its inputs,
thread schedule included! 

[![Jim Carrey pulling at his hair, going crazy: how I feel about the Nix superpowers nobody else is using](/assets/images/jim_carrey_nix_superpowers.gif)](/assets/images/jim_carrey_nix_superpowers.gif)
{: style="--image-width: 22rem"}

I have been using it to find, reproduce and solve numerous race conditions in Nix builds, but it's been making me feel _a little crazy_. What is this superpower, and why is nobody else using it?

The tool has quickly grown a source panel, stack frames,
bookmarks, a "Compare" tab, a lot more gdb support, thread lanes, which show who held
the CPU at every step, and "Check from here", which helps find the exact step where a race
condition happens.

I went into each new feature thinking it would be a big code-lift but I kept running into the same thing: _the hard part of each feature was already done, and Nix had done it._

A debugger for instance, needs the exact inputs of the program, its debug symbols, its sources, the sources of every library under it, and a way for someone else to get all of that on their
machine. That's exactly what a derivation is, and Nix makes that easy.

<!--more-->

## Two tellers, one account

A classic simple example of a race condition is two threads depositing into one bank account. Each deposit reads the balance, writes a line to the ledger, then stores the balance plus the deposit. If one teller runs between the other's read and store, it writes a stale balance over the other's deposits. 💥

```c
static void deposit(int teller, long amount)
{
  long seen = balance;
  char line[64];
  int n = snprintf(line, sizeof line, 
                   "teller %d: %ld + %ld\n",
                   teller, seen, amount);

  if (write(1, line, n) != n)
      return;
  balance = seen + amount;
}
```

A teller that runs between the other's read and store writes a stale balance
over the other's deposits.[^laptop]

[^laptop]: On my laptop, with 16 cores, `bank` comes up short times in 1,000. Pinned to one CPU with `taskset`, it failed 0 times in 1,000.

<figure>
<svg viewBox="0 0 440 272" role="img"
     style="display:block;margin-inline:auto;max-width:26rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="A sequence diagram of the lost update. Teller 1 reads the balance, 150. Teller 2 reads it too, 150. Teller 1 deposits up to 200. Teller 2 then stores its stale 150 plus 10, 160, over teller 1's 200, and teller 1's five deposits are gone.">
  <defs>
    <marker id="bank-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor"/>
    </marker>
    <marker id="bank-arrow-bad" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="#b1201d"/>
    </marker>
  </defs>
  <text x="70" y="22" font-size="15" font-weight="600" text-anchor="middle" fill="currentColor">teller 1</text>
  <text x="220" y="22" font-size="15" font-weight="600" text-anchor="middle" fill="currentColor">balance</text>
  <text x="370" y="22" font-size="15" font-weight="600" text-anchor="middle" fill="currentColor">teller 2</text>
  <line x1="70" y1="34" x2="70" y2="224" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 4" opacity="0.5"/>
  <line x1="220" y1="34" x2="220" y2="208" stroke="currentColor" stroke-width="3" opacity="0.25"/>
  <line x1="370" y1="34" x2="370" y2="224" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 4" opacity="0.5"/>
  <line x1="216" y1="62" x2="76" y2="62" stroke="currentColor" stroke-width="1.5" marker-end="url(#bank-arrow)"/>
  <text x="145" y="55" font-size="13" text-anchor="middle" fill="currentColor">read 150</text>
  <line x1="224" y1="100" x2="364" y2="100" stroke="#b1201d" stroke-width="1.5" marker-end="url(#bank-arrow-bad)"/>
  <text x="295" y="93" font-size="13" text-anchor="middle" fill="#b1201d">read 150</text>
  <line x1="76" y1="138" x2="216" y2="138" stroke="currentColor" stroke-width="1.5" marker-end="url(#bank-arrow)"/>
  <text x="145" y="131" font-size="13" text-anchor="middle" fill="currentColor">store 200</text>
  <line x1="364" y1="184" x2="224" y2="184" stroke="#b1201d" stroke-width="2" marker-end="url(#bank-arrow-bad)"/>
  <text x="295" y="177" font-size="13" text-anchor="middle" fill="#b1201d">store 150 + 10</text>
  <rect x="186" y="208" width="68" height="26" rx="4" fill="var(--paper, transparent)" stroke="#b1201d" stroke-width="1.5"/>
  <text x="220" y="226" font-size="14" font-weight="600" text-anchor="middle" fill="#b1201d">160</text>
  <text x="220" y="260" font-size="13" text-anchor="middle" fill="#b1201d">teller 1's last deposit is gone</text>
</svg>
</figure>

Rewind's VM has one CPU, so its first run passes too. `rewind check` runs the
build again under perturbed schedules, each asking the guest kernel to
reschedule at different steps, and narrows the first failure down to one step:

```console
$ rewind check --where github:fzakaria/rewindvm#bank
...
step 3237 decides it: a reschedule there makes the run fail

passing: run 12feb5f832205a72, schedule 0
failing: run c2f1cfac0c288f3e, schedule 1 over steps 3237..3238
the two are the same run until step 3237

where the threads were:
        3237   139/140   deposit (bank.c:24), on the CPU at the deciding step
        3250   139/141   deposit (bank.c:24), at the first event that differs
```

Running this check on my laptop took 11 seconds. The two runs are the same machine, exit for exit, until step 3237, where only the failing one gets a reschedule.

## Free thing one: the inputs

The argument to `check` is a derivation and can be a flake reference. The beauty of Nix is that it knows the inputs of a derivation, so that's all we need to make sure the run is reproducible. The derivation's inputs are the source, the compiler, the libraries, the kernel, and the VM's configuration

`rewind nix` realises the derivation's inputs, packs the closure into a read-only erofs image, and boots the VM on it.

The run's id is a hash of its inputs, the way a store path is, and `rewind show` prints the command that makes it again:

```console
$ rewind show 12feb5f8
rewind nix /nix/store/cr8rl40rjb9cmmcd9sxn9mpdrhvp53jj-bank-0.1.0.drv --epoch 1791331200 --clock branches --name bank-0.1.0  # 12feb5f832205a72
```

When the build succeeds, the guest reports each output's NAR hash, and
`rewind nix` checks it against the host's copy and against every binary cache
Nix substitutes from, by fetching only the `.narinfo`:

```console
$ rewind nix github:fzakaria/rewindvm#bank
...
/nix/store/27a4q7w90jzp4wg5kaaajvb64zll6yqg-bank-0.1.0 dbf0df3de84b7a84  matches your store
```

This helps us validate that the build within the VM is the same as the build on my laptop, and that the VM's run is reproducible by Nix.


## Free thing two: every symbol and every source

Debugging code is much simpler when you are looking at the source. A new panel in the Rewind app or `rewind where` in the terminal shows the source of the program at the playhead, and the stack frames that called it.

[![The Rewind app's source panel at step 3,250 of the failing bank run: bank.c open at line 24, the write in deposit, with the frames below running from __syscall_cancel_arch in glibc's syscall_cancel.S through write.c, deposit, teller and start_thread to clone3](/assets/images/rewind-bank-source-crop.png)](/assets/images/rewind-bank-source.png)
{: style="--image-width: 20rem"}

The debugger needs to know where the sources are, and Nix gives us that for free too.

[nixpkgs](https://github.com/NixOS/nixpkgs) builds the packages with `separateDebugInfo`, and the debug info is cached on [cache.nixos.org](https://cache.nixos.org) as a `debug` output. We can leverage [debuginfod](https://fedoraproject.org/wiki/Debuginfod) to fetch the debug info and the sources by build ID, so we can see the source of any binary in the VM, including the Linux kernel! 😲

```console
$ rewind where c2f1cfac 3250
process 139 (bank), thread 141, at step 3250
#4 deposit (bank.c:24)
      22  	int n = snprintf(line, sizeof line, "teller %d: %ld + %ld\n", teller, seen, amount);
      23
>     24  	if (write(1, line, n) != n)
      25  		return;
      26  	balance = seen + amount;
called from #5 teller (bank.c:34)
called from #6 start_thread (pthread_create.c:454)
```

## gdb, on a fork of any step

Sometimes though, the source is not enough, and we need to see the state of the program. `rewind gdb` opens gdb on a fork of the run at the playhead, with every thread of the process. The debugger can set breakpoints, watchpoints, and inspect memory, registers and variables.

At step 3249, just before teller 2 gets the CPU back, we can watch the `balance` variable and continue until it changes. Nothing gdb does changes the recording, and we can rewind to the same step and fork again, or fork at any other step, and gdb will see the same state.


[![The Rewind app with a gdb pane at step 3,249: watch balance, continue, and thread 3 hits the hardware watchpoint with old value 200 and new value 160 in deposit, teller=2, at bank.c:26](/assets/images/rewind-bank-gdb-crop.png)](/assets/images/rewind-bank-gdb.png)

If gdb is not enough, `rewind shell --with nixpkgs#strace` opens a shell in the
VM at a step with any package from nixpkgs on its `PATH`. It is one more closure packed into one more image.

## Compare two runs

Rewind makes it very easy to compare two runs. The Compare tab in the app, or `rewind compare` in the terminal, shows the last shared events of both runs, and the first event that differs.

[![The Rewind app at step 3,250 of the failing run, compared with the passing run: the divergence card says the two runs are the same until step 3,237, where only this run has a reschedule, and that at step 3,250 thread 3 writes "teller 2: 150 + 10" where the passing run writes "teller 2: 200 + 10"](/assets/images/rewind-bank-divergence-crop.png)](/assets/images/rewind-bank-divergence.png)
{: style="--image-width: 20rem"}

The Compare tab puts both runs' events side by side from just before they part,
with what differs marked. Teller 2 starts from 150 in the failing run and from
200 in the passing one:

[![The Rewind app's Compare tab: both runs' last shared events, teller 1's writes, then the failing run's teller 2 writing 150, 160, 170 beside the passing run's 200, 210, 220](/assets/images/rewind-bank-compare-crop.png)](/assets/images/rewind-bank-compare.png)
{: style="--image-width: 22rem"}

## Who had the CPU

Rewind's VM has one CPU, so at any step exactly one thread is running. A race
is a question of order: which thread ran when. 

The trace does not answer that directly. It records what threads did, a write, an open, a fork, an exit, a signal, but not who was running in the gaps between those events.

Rewind can fill in the gaps without recording anything new. Every run replays
exactly, so it can walk any stretch of a run one step at a time and, at each
step, ask the guest kernel which thread is on the CPU.

In the failing run, teller 1 (Thread 140) is interrupted at step 3238, halfway through a
deposit: it has read the balance but not stored it. Teller 2 (Thread 141) gets the CPU for
a single step, 3239, long enough to read the balance, and then teller 1 gets
it back and finishes.[^orange]

[^orange]: It is a little hard to see since the event from Teller 2 is tucked underneath the Orange bar.

[![The Rewind app's Threads tab on the bank runs: a lane per thread, with thread 141's one-step bar at 3,239 in the failing run, and lines marking the first step another thread held the CPU, where the runs part, and the playhead](/assets/images/rewind-bank-threads-crop.png)](/assets/images/rewind-bank-threads.png)
{: style="--image-width: 22rem"}


## Check from here

Finding one bad interleaving raises the next question: how likely is it? Is the
passing run the normal case, or did it get lucky?

`rewind check` normally answers that by building the whole derivation again
under many schedules. With `--run`, it starts from a run you already have
instead, at _any_ step you pick_. It forks the run there once per schedule, each
fork taking a different order of threads from that step on, and counts how
many end differently. Everything before the step stays exactly as it was.

We can apply this technique to the bank example, starting from the step where the two runs diverged, 3,221. When we run 16 schedules from there, all 16 lose money[^check]:

[^check]: Schedule 0 is the run itself, which passed. Every other line is a fork, and `exited:2` is `make check` failing because the balance came up short.

```console
$ rewind check --run 12feb5f8 --schedule-from 3221 --schedules 16 --all --no-narrow
schedule   0: exited:0       4528 steps  dbf0df3de84b  run 12feb5f832205a72
schedule   1: exited:2       3313 steps    run f6eb462913dce489
schedule   2: exited:2       3328 steps    run 388cef73a9c545fa
schedule   3: exited:2       3312 steps    run 4d42012072d11537
...
schedule  16: exited:2       3314 steps    run 63f7817972a90273
16 of 16 perturbed schedules ended differently
```

We can do the same thing from the Rewind App with "Check from here" in the context menu of the playhead. It forks the run at the playhead and runs each fork under a different schedule, counting how many end differently.

[![The Rewind app after Check from here at step 3,221 of the passing run: a card saying 16 of 16 schedules ended differently, with 16 blue cells](/assets/images/rewind-bank-check-crop.png)](/assets/images/rewind-bank-check.png)
{: style="--image-width: 22rem"}


## Bookmarks

`b` bookmarks the playhead's step with a note. Bookmarks are kept with the run,
and they travel in its `.rwd` export, so the person I hand the run to opens it
with my notes on the timeline:

[![The Rewind app's Bookmarks tab with two notes: step 3,239, teller 2 reads balance = 150, then loses the CPU, and step 3,250, teller 2 stores 160 over teller 1's 200](/assets/images/rewind-bank-bookmarks-crop.png)](/assets/images/rewind-bank-bookmarks.png)

## Other examples to try

Each one is a derivation in the flake, with one bug and one fix:

- `philosophers`: the deadlock from the last post.
- `bank`: the lost update above.
- `waiter`: a SIGCHLD that arrives between a flag check and `pause`, so the
  parent sleeps until `make check`'s ten second timeout kills it.
- `config-reload`: one process rewrites a config file in place while another
  rereads it. On many cores it fails nearly every time; on one CPU only some
  schedules land the reader between the truncate and the last write.

```console
$ rewind check github:fzakaria/rewindvm#waiter
```

## Nix is a superpower

Most of the hard work of a debugger is already done by Nix. Rewind adds a little more, but the rest is already there: the inputs, the sources, the debug symbols, and a way for someone else to get all of that on their machine.

When you start with something hermetic like a Nix derivation, you can get a debugger for free.


```console
$ nix run github:fzakaria/rewindvm -- check github:fzakaria/rewindvm#bank
```