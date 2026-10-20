---
layout: post
title: 'Dafuq is a deterministic VM?'
date: 2026-10-24 10:00 -0700
excerpt_separator: <!--more-->
---

_The life of a system call inside Rewind VM._

Since I started writing about [Rewind VM](https://rewindvm.dev), the question I get most from friends is not "does it work?" but "how does it _actually_ work?" 🤔

D'uh! <u>It is a virtual machine that only gets interrupted when it asks to be</u>.

<!--more-->

[![Dafuq did I just read meme: Samuel Johnson squints at a book that says "It is a VM that only gets interrupted when it asks to be", then looks up, baffled: "Dafuq did I just read"](/assets/images/rewind_dafuq_meme.png)](/assets/images/rewind_dafuq_meme.png)
{: style="--image-width: 18rem"}

That seems to not have helped much, so let's go deeper.

We will follow a tiny C program through the machine and, at each step, look at where non-determinism would have crept in and what Rewind does about it.

> **Aside:**
> If you have not seen Rewind before, start with [a flaky build you only catch once]({% post_url 2026-10-01-rewind-vm-a-flaky-build-you-only-catch-once %}).
{: .alert .alert-note }

## Life is deterministic

CPUs must be deterministic. If they were not, we would have a very bad time trusting them to do anything.

Give a CPU the same registers, the same memory and the same instructions, and it computes the same result.

What does change? Why are machines not deterministic?

They are not closed systems. They interact with the outside world and that interaction is not deterministic. A timer interrupt can land at any instruction or a disk read can complete at any time.

> **Aside:**
> Computers can't actually make random numbers. A deterministic machine can only fake it with _pseudo_-randomness: run the same algorithm from the same seed and you get the same numbers back. The real stuff has to come from the physical world. My favorite example is how Cloudflare keeps [a wall of 100 lava lamps](https://www.cloudflare.com/learning/ssl/lava-lamp-encryption/) in its San Francisco office with a camera pointed at it, feeding its encryption keys.
{: .alert .alert-note }


If we could capture all external influences, we could replay the external world and get the same run again. That is what Rewind does.

Every source from the outside world is either removed or replaced with a value derived from a stored seed. Time, for instance, is a clock managed by Rewind. Interrupts arrive only at points we choose. ⏱️

One more outside influence is easy to miss: other CPUs. On two cores, which thread wins a race comes down to cache misses and pipeline stalls, so Rewind provides a single virtual CPU and the threads take turns on it.

<figure>
<svg viewBox="0 0 720 190" role="img"
     style="display:block;margin-inline:auto;max-width:44rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="Left: two cores run thread A and thread B at the same time, both reach the same lock at nearly the same moment, and which one wins depends on cache timing. Right: Rewind's single virtual CPU runs A, then B, then A, switching only at exits, in the same order every run.">
  <style>
    .cp-a { fill: var(--accent-wash, #9e34131f); stroke: var(--accent, #9e3413); stroke-width: 1; }
    .cp-b { fill: var(--paper-raised, #ebe6da); stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; }
    .cp-h { font-size: 13px; font-weight: 600; fill: var(--ink, #1a1815); }
    .cp-l { font-size: 11px; fill: var(--ink-muted, #565046); }
    .cp-t { font-size: 11.5px; fill: var(--ink, #1a1815); }
    .cp-r { font-size: 11px; fill: var(--accent, #9e3413); }
    .cp-lock { stroke: var(--accent, #9e3413); stroke-width: 1.25; stroke-dasharray: 4 3; }
    .cp-tick { stroke: var(--ink, #1a1815); stroke-width: 2; }
    .cp-rule { stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; }
  </style>

  <text x="10" y="24" class="cp-h">two cores</text>
  <text x="62" y="74" text-anchor="end" class="cp-l">core 0</text>
  <rect x="72" y="58" width="258" height="24" rx="4" class="cp-a"/>
  <text x="90" y="74" class="cp-t">thread A</text>
  <text x="62" y="118" text-anchor="end" class="cp-l">core 1</text>
  <rect x="72" y="102" width="258" height="24" rx="4" class="cp-b"/>
  <text x="90" y="118" class="cp-t">thread B</text>
  <line x1="240" y1="48" x2="240" y2="136" class="cp-lock"/>
  <text x="240" y="40" text-anchor="middle" class="cp-r">lock</text>
  <text x="200" y="158" text-anchor="middle" class="cp-l">both reach the lock at once</text>
  <text x="200" y="176" text-anchor="middle" class="cp-r">the winner depends on the cache</text>

  <line x1="360" y1="12" x2="360" y2="180" class="cp-rule"/>

  <text x="380" y="24" class="cp-h">Rewind: one vCPU</text>
  <text x="430" y="96" text-anchor="end" class="cp-l">vCPU</text>
  <rect x="440" y="80" width="90" height="24" rx="4" class="cp-a"/>
  <text x="485" y="96" text-anchor="middle" class="cp-t">A</text>
  <rect x="530" y="80" width="80" height="24" rx="4" class="cp-b"/>
  <text x="570" y="96" text-anchor="middle" class="cp-t">B</text>
  <rect x="610" y="80" width="90" height="24" rx="4" class="cp-a"/>
  <text x="655" y="96" text-anchor="middle" class="cp-t">A</text>
  <line x1="530" y1="72" x2="530" y2="112" class="cp-tick"/>
  <line x1="610" y1="72" x2="610" y2="112" class="cp-tick"/>
  <text x="570" y="64" text-anchor="middle" class="cp-l">exits</text>
  <text x="570" y="158" text-anchor="middle" class="cp-l">threads switch only at an exit</text>
  <text x="570" y="176" text-anchor="middle" class="cp-r">the same order every run</text>
</svg>
</figure>

## A step is a VM exit

To control the outside world, Rewind needs moments where the software stops and Rewind can step in. At those moments it writes down what just happened, hands over the current time, or delivers an interrupt. So how do you stop the software at the same place on every run?

One answer is to make the hardware do it. CPUs have performance counters that can interrupt after a set number of instructions. 
Unfortunately, the interrupt may arrive a few instructions late, and the amount varies.[^intel]

[^intel]: Intel's counter is good enough that you can single-step the rest of the way to the exact instruction. I have an AMD laptop. 🙃 


Rewind uses a _cooperative_ approach: let the software tell us when something happens!

Rewind runs the guest under KVM, the hypervisor built into Linux. The guest's code runs directly on the real CPU until it touches a device. The CPU then stops the guest and hands control to the program running the VM, Rewind's monitor (`rewind-vmm`). That hand-off is a _VM exit_.

Rewind patches the guest kernel so that whenever it needs something only the outside world has, such as the time, a timer, or "I have nothing to do", it makes an exit and asks the monitor. Reporting what happened, like a process starting or a line of output, is an exit too.

Each exit the guest makes is called a **step**, and they are numbered starting from boot.

If we **assume** the guest is deterministic up to step _N_, step _N_ happens at the same instruction on every run.

The monitor's loop, sketched in Python:

```python
step, clock, deadline = 0, 0, None

while True:
    # The guest runs natively until it exits.
    exit = vcpu.run()

    # The host's own business: not a step, and nothing is sent.
    if exit.reason == HOST_INTERRUPT:
        continue

    # An exit the guest made. Time moves only here.
    step += 1
    clock += QUANTUM

    # Read the clock, arm a timer, log an event...
    deadline = handle(exit, step)

    # Interrupts go in only here, with the guest stopped.
    if deadline is not None and clock >= deadline:
        vcpu.inject(TIMER_INTERRUPT)
        deadline = None
```

<figure>
<svg viewBox="0 0 720 330" role="img"
     style="display:block;margin-inline:auto;max-width:44rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="Two runs of the same guest in a normal VM and two in Rewind, each drawn as a line of guest instructions with the guest's exits at the same five places. In the normal VM the timer interrupt lands between exits, at a different instruction in each run. In Rewind the interrupt is delivered at an exit, the same step in the recording and in the replay.">
  <style>
    .ex-track { stroke: var(--ink-faint, #6f685b); stroke-width: 1.25; fill: none; }
    .ex-tick { stroke: var(--ink, #1a1815); stroke-width: 2; }
    .ex-irq { fill: var(--accent, #9e3413); }
    .ex-head { fill: var(--ink-faint, #6f685b); }
    .ex-h { font-size: 13px; font-weight: 600; fill: var(--ink, #1a1815); }
    .ex-l { font-size: 11.5px; fill: var(--ink-muted, #565046); }
    .ex-n { font-size: 10.5px; fill: var(--accent, #9e3413); }
    .ex-r { font-size: 11.5px; fill: var(--accent, #9e3413); }
    .ex-rule { stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; }
  </style>
  <defs>
    <marker id="ex-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" class="ex-head"/>
    </marker>
  </defs>

  <text x="10" y="24" class="ex-h">normal VM</text>
  <text x="690" y="24" text-anchor="end" class="ex-r">a different instruction each run</text>
  <text x="170" y="68" text-anchor="end" class="ex-l">run 1</text>
  <line x1="185" y1="64" x2="690" y2="64" class="ex-track" marker-end="url(#ex-arrow)"/>
  <line x1="240" y1="57" x2="240" y2="71" class="ex-tick"/>
  <line x1="330" y1="57" x2="330" y2="71" class="ex-tick"/>
  <line x1="410" y1="57" x2="410" y2="71" class="ex-tick"/>
  <line x1="520" y1="57" x2="520" y2="71" class="ex-tick"/>
  <line x1="620" y1="57" x2="620" y2="71" class="ex-tick"/>
  <path d="M359,44 L371,44 L365,55 z" class="ex-irq"/>
  <text x="375" y="52" class="ex-n">timer</text>
  <text x="170" y="112" text-anchor="end" class="ex-l">run 2</text>
  <line x1="185" y1="108" x2="690" y2="108" class="ex-track" marker-end="url(#ex-arrow)"/>
  <line x1="240" y1="101" x2="240" y2="115" class="ex-tick"/>
  <line x1="330" y1="101" x2="330" y2="115" class="ex-tick"/>
  <line x1="410" y1="101" x2="410" y2="115" class="ex-tick"/>
  <line x1="520" y1="101" x2="520" y2="115" class="ex-tick"/>
  <line x1="620" y1="101" x2="620" y2="115" class="ex-tick"/>
  <path d="M456,88 L468,88 L462,99 z" class="ex-irq"/>
  <text x="472" y="96" class="ex-n">timer</text>

  <line x1="10" y1="135" x2="710" y2="135" class="ex-rule"/>

  <text x="10" y="160" class="ex-h">Rewind</text>
  <text x="690" y="160" text-anchor="end" class="ex-r">step N, every run</text>
  <text x="170" y="204" text-anchor="end" class="ex-l">run 1 (recording)</text>
  <line x1="185" y1="200" x2="690" y2="200" class="ex-track" marker-end="url(#ex-arrow)"/>
  <line x1="240" y1="193" x2="240" y2="207" class="ex-tick"/>
  <line x1="330" y1="193" x2="330" y2="207" class="ex-tick"/>
  <line x1="410" y1="193" x2="410" y2="207" class="ex-tick"/>
  <line x1="520" y1="193" x2="520" y2="207" class="ex-tick"/>
  <line x1="620" y1="193" x2="620" y2="207" class="ex-tick"/>
  <path d="M404,180 L416,180 L410,191 z" class="ex-irq"/>
  <text x="420" y="188" class="ex-n">step N</text>
  <text x="170" y="248" text-anchor="end" class="ex-l">run 2 (replay)</text>
  <line x1="185" y1="244" x2="690" y2="244" class="ex-track" marker-end="url(#ex-arrow)"/>
  <line x1="240" y1="237" x2="240" y2="251" class="ex-tick"/>
  <line x1="330" y1="237" x2="330" y2="251" class="ex-tick"/>
  <line x1="410" y1="237" x2="410" y2="251" class="ex-tick"/>
  <line x1="520" y1="237" x2="520" y2="251" class="ex-tick"/>
  <line x1="620" y1="237" x2="620" y2="251" class="ex-tick"/>
  <path d="M404,224 L416,224 L410,235 z" class="ex-irq"/>
  <text x="420" y="232" class="ex-n">step N</text>

  <line x1="200" y1="292" x2="200" y2="306" class="ex-tick"/>
  <text x="212" y="303" class="ex-l">an exit the guest made: one step</text>
  <path d="M454,291 L466,291 L460,302 z" class="ex-irq"/>
  <text x="474" y="303" class="ex-l">the monitor's interrupt</text>
  <text x="200" y="324" class="ex-l">each line is the guest's instructions, left to right</text>
</svg>
</figure>

This is true on the first run too. Nothing gets recorded, and a replay just runs the same inputs again.

Three pieces make this work, and your program doesn't need to know about any of them.

**A patched Linux kernel.** The guest kernel is the piece that cooperates. A [small patch](https://github.com/fzakaria/rewindvm/blob/main/guest/linux/rewind-guest.patch) teaches it to take its clock, its timer and its idle loop from the monitor instead of from hardware, and to report what processes do: exec, exit, output, files written. The monitor also hides the CPU features that would leak the outside world in, such as the hardware cycle counter and the random number instruction, so the kernel never uses them.

**rewind-init.** The special PID 1 is a small program that mounts the input image (a Nix closure or a root filesystem), runs the command, reports its exit status and powers the machine off. The image is mapped straight into guest memory, so reading a file is reading memory, and there is no disk to finish a read at a random moment.

**rewind-vmm.** The monitor owns time, decides when interrupts go in, and keeps the trace of everything the kernel reports.

<figure>
<svg viewBox="0 0 680 600" role="img"
     style="display:block;margin-inline:auto;max-width:40rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="Rewind VM's architecture. Inputs, a Nix closure or a root filesystem packed as erofs, go into the guest VM: one vCPU on stock KVM, running natively on the real CPU. Inside it are the build or test processes, rewind-init as PID 1, and a patched Linux kernel with the Rewind platform, whose clock, timer, idle and events go through the host. Each VM exit is one step down to the host's rewind-vmm, which owns time, ordering and memory: a virtual clock from exits and the branch count, an event trace, keyframes in a deduplicated page store, and seeded randomness, so the same inputs and seed give the same run. The monitor sends its interrupt back up only at an exit.">
  <style>
    .ar-box { fill: var(--paper-raised, #ebe6da); stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; }
    .ar-guest { fill: var(--accent-wash, #9e34131f); stroke: var(--accent, #9e3413); stroke-width: 1; }
    .ar-host { fill: currentColor; fill-opacity: 0.05; stroke: var(--ink-faint, #6f685b); stroke-width: 1; }
    .ar-t { font-size: 13px; fill: var(--ink, #1a1815); }
    .ar-m { font-size: 10.5px; fill: var(--ink-muted, #565046); }
    .ar-h { font-size: 14px; font-weight: 600; fill: var(--accent, #9e3413); }
    .ar-hh { font-size: 14px; font-weight: 600; fill: var(--ink, #1a1815); }
    .ar-edge { stroke: var(--ink-faint, #6f685b); stroke-width: 1.25; fill: none; }
    .ar-head { fill: var(--ink-faint, #6f685b); }
  </style>
  <defs>
    <marker id="ar-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" class="ar-head"/>
    </marker>
  </defs>

  <rect x="200" y="20" width="280" height="56" rx="8" class="ar-box"/>
  <text x="340" y="43" text-anchor="middle" class="ar-t">Inputs</text>
  <text x="340" y="63" text-anchor="middle" class="ar-m">Nix closure or rootfs → erofs</text>
  <line x1="340" y1="76" x2="340" y2="106" class="ar-edge" marker-end="url(#ar-arrow)"/>

  <rect x="40" y="110" width="600" height="200" rx="16" class="ar-guest"/>
  <text x="340" y="138" text-anchor="middle" class="ar-h">Guest VM · 1 vCPU on stock KVM</text>
  <text x="340" y="156" text-anchor="middle" class="ar-m">Code runs natively on the real CPU</text>
  <rect x="60" y="172" width="270" height="56" rx="8" class="ar-box"/>
  <text x="195" y="195" text-anchor="middle" class="ar-t">Build / test processes</text>
  <text x="195" y="215" text-anchor="middle" class="ar-m">nix build, make check</text>
  <rect x="350" y="172" width="270" height="56" rx="8" class="ar-box"/>
  <text x="485" y="195" text-anchor="middle" class="ar-t">rewind-init</text>
  <text x="485" y="215" text-anchor="middle" class="ar-m">PID 1, mounts erofs</text>
  <rect x="60" y="240" width="560" height="56" rx="8" class="ar-box"/>
  <text x="340" y="263" text-anchor="middle" class="ar-t">Patched Linux + Rewind platform</text>
  <text x="340" y="283" text-anchor="middle" class="ar-m">Clock, timer, idle and events go through the host</text>

  <line x1="160" y1="312" x2="160" y2="376" class="ar-edge" marker-end="url(#ar-arrow)"/>
  <text x="172" y="340" class="ar-m">VM exit = one step</text>
  <line x1="520" y1="376" x2="520" y2="312" class="ar-edge" marker-end="url(#ar-arrow)"/>
  <text x="508" y="352" text-anchor="end" class="ar-m">Interrupt only at an exit</text>

  <rect x="40" y="380" width="600" height="200" rx="16" class="ar-host"/>
  <text x="340" y="408" text-anchor="middle" class="ar-hh">Host: rewind-vmm</text>
  <text x="340" y="426" text-anchor="middle" class="ar-m">Owns time, ordering and memory</text>
  <rect x="60" y="442" width="180" height="56" rx="8" class="ar-box"/>
  <text x="150" y="465" text-anchor="middle" class="ar-t">Virtual clock</text>
  <text x="150" y="485" text-anchor="middle" class="ar-m">exits + branch count</text>
  <rect x="250" y="442" width="180" height="56" rx="8" class="ar-box"/>
  <text x="340" y="465" text-anchor="middle" class="ar-t">Event trace</text>
  <text x="340" y="485" text-anchor="middle" class="ar-m">processes, files, output</text>
  <rect x="440" y="442" width="180" height="56" rx="8" class="ar-box"/>
  <text x="530" y="465" text-anchor="middle" class="ar-t">Keyframes</text>
  <text x="530" y="485" text-anchor="middle" class="ar-m">dedup page store</text>
  <rect x="60" y="510" width="560" height="56" rx="8" class="ar-box"/>
  <text x="340" y="533" text-anchor="middle" class="ar-t">Seeded randomness</text>
  <text x="340" y="553" text-anchor="middle" class="ar-m">Same inputs + seed → same run</text>

</svg>
</figure>


## The life of a system call

Here is the program. It reads the clock, draws a random number, prints both with the address of a stack variable, sleeps for a second, then reads the clock again.

```c
#include <stdio.h>
#include <sys/random.h>
#include <time.h>
#include <unistd.h>

int main(void) {
  struct timespec ts;
  unsigned int r;

  clock_gettime(CLOCK_REALTIME, &ts);
  getrandom(&r, sizeof r, 0);
  printf("time=%ld.%09ld random=%u stack=%p\n", ts.tv_sec, ts.tv_nsec, r, (void *)&r);
  fflush(stdout);

  sleep(1);

  clock_gettime(CLOCK_REALTIME, &ts);
  printf("time=%ld.%09ld\n", ts.tv_sec, ts.tv_nsec);
  return 0;
}
```

On my laptop every run prints something new. In Rewind, every run prints the same thing, down to the nanosecond, until you change the seed:

```console?comments=true
$ rewind run --root root -- /bin/hello
time=1792886400.001006990 random=166963147 stack=0x7fff2bad5e4c
time=1792886401.001132684
rewind: run 85a03383f7d917d9 exited:0 after 432 steps, 1.002s virtual, 1.139s wall (poweroff)

$ rewind run --root root -- /bin/hello
time=1792886400.001006990 random=166963147 stack=0x7fff2bad5e4c
time=1792886401.001132684
rewind: run 85a03383f7d917d9 exited:0 after 432 steps, 1.002s virtual, 0.394s wall (poweroff)

# a different seed is a different input, so a different run
$ rewind run --root root --seed 1 -- /bin/hello
time=1792886400.001006990 random=2117056732 stack=0x7ffdd58e5bdc
time=1792886401.001132680
rewind: run 59c7da84895c210a exited:0 after 432 steps, 1.002s virtual, 0.848s wall (poweroff)
```

[![They're the same picture meme: Pam holds up two papers labelled "the run that failed on CI" and "rewind replay of that run", and says "They're the same picture."](/assets/images/rewind_same_picture_meme.png)](/assets/images/rewind_same_picture_meme.png)
{: style="--image-width: 22rem"}

Same inputs, same run id, same 432 steps. Oh, and the program slept for a second, yet the whole VM finished in 0.39 seconds. 🤓

Normally, reading the time never enters the kernel: a bit of code in every process reads a hardware counter directly. Rewind hides that counter, so the read goes to the kernel, and the kernel asks the monitor.

<figure>
<svg viewBox="0 0 760 470" role="img"
     style="display:block;margin-inline:auto;max-width:44rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="A sequence diagram of clock_gettime in Rewind across four lanes: hello in user space, the guest kernel, KVM in the host kernel, and rewind-vmm on the host. hello makes a system call because there is no hardware counter to read. The guest kernel reads the clock port, which makes KVM exit to rewind-vmm. The monitor counts a step, adds 5 microseconds plus the work done to its clock, leaves the time in memory the guest can read, and sends an interrupt if a timer is due. It resumes the guest, and the kernel returns the time to hello.">
  <style>
    .ls-head { fill: var(--paper-raised, #ebe6da); stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; }
    .ls-under { fill: var(--paper, #f4f1ea); }
    .ls-step { fill: var(--accent-wash, #9e34131f); stroke: var(--accent, #9e3413); stroke-width: 1; }
    .ls-life { stroke: var(--rule-strong, #c2b9a6); stroke-width: 1; stroke-dasharray: 4 4; }
    .ls-split { stroke: var(--ink-faint, #6f685b); stroke-width: 1; stroke-dasharray: 2 5; }
    .ls-edge { stroke: var(--ink-faint, #6f685b); stroke-width: 1.25; fill: none; }
    .ls-arrowhead { fill: var(--ink-faint, #6f685b); }
    .ls-t { font-size: 12.5px; fill: var(--ink, #1a1815); }
    .ls-m { font-size: 10.5px; fill: var(--ink-muted, #565046); }
    .ls-a { font-size: 11.5px; fill: var(--ink, #1a1815); }
    .ls-o { font-size: 12px; font-weight: 600; fill: var(--accent, #9e3413); }
  </style>
  <defs>
    <marker id="ls-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" class="ls-arrowhead"/>
    </marker>
  </defs>

  <line x1="350" y1="8" x2="350" y2="450" class="ls-split"/>
  <text x="340" y="464" text-anchor="end" class="ls-m">guest</text>
  <text x="360" y="464" class="ls-m">host</text>

  <rect x="10" y="14" width="140" height="38" rx="6" class="ls-head"/>
  <text x="80" y="30" text-anchor="middle" class="ls-t">hello</text>
  <text x="80" y="45" text-anchor="middle" class="ls-m">user space</text>
  <rect x="190" y="14" width="140" height="38" rx="6" class="ls-head"/>
  <text x="260" y="30" text-anchor="middle" class="ls-t">guest kernel</text>
  <text x="260" y="45" text-anchor="middle" class="ls-m">Rewind platform</text>
  <rect x="370" y="14" width="140" height="38" rx="6" class="ls-head"/>
  <text x="440" y="30" text-anchor="middle" class="ls-t">KVM</text>
  <text x="440" y="45" text-anchor="middle" class="ls-m">host kernel</text>
  <rect x="570" y="14" width="140" height="38" rx="6" class="ls-head"/>
  <text x="640" y="30" text-anchor="middle" class="ls-t">rewind-vmm</text>
  <text x="640" y="45" text-anchor="middle" class="ls-m">host process</text>

  <line x1="80" y1="52" x2="80" y2="445" class="ls-life"/>
  <line x1="260" y1="52" x2="260" y2="445" class="ls-life"/>
  <line x1="440" y1="52" x2="440" y2="445" class="ls-life"/>
  <line x1="640" y1="52" x2="640" y2="445" class="ls-life"/>

  <line x1="80" y1="85" x2="258" y2="85" class="ls-edge" marker-end="url(#ls-arrow)"/>
  <text x="170" y="79" text-anchor="middle" class="ls-a">syscall</text>
  <text x="170" y="99" text-anchor="middle" class="ls-m">no hardware counter</text>

  <line x1="260" y1="130" x2="438" y2="130" class="ls-edge" marker-end="url(#ls-arrow)"/>
  <text x="350" y="124" text-anchor="middle" class="ls-a">read the clock</text>
  <text x="350" y="144" text-anchor="middle" class="ls-m">an I/O port</text>

  <line x1="440" y1="175" x2="638" y2="175" class="ls-edge" marker-end="url(#ls-arrow)"/>
  <text x="540" y="169" text-anchor="middle" class="ls-a">VM exit</text>
  <text x="540" y="189" text-anchor="middle" class="ls-m">made by the guest</text>

  <rect x="545" y="200" width="200" height="98" rx="8" class="ls-under"/>
  <rect x="545" y="200" width="200" height="98" rx="8" class="ls-step"/>
  <text x="560" y="222" class="ls-o">count a step</text>
  <text x="560" y="243" class="ls-a">clock += 5 µs + work</text>
  <text x="560" y="263" class="ls-a">leave the time in memory</text>
  <text x="560" y="283" class="ls-a">timer due? interrupt</text>

  <line x1="640" y1="320" x2="442" y2="320" class="ls-edge" marker-end="url(#ls-arrow)"/>
  <text x="540" y="314" text-anchor="middle" class="ls-a">run the guest again</text>

  <line x1="440" y1="365" x2="262" y2="365" class="ls-edge" marker-end="url(#ls-arrow)"/>
  <text x="350" y="359" text-anchor="middle" class="ls-a">resume the guest</text>

  <line x1="260" y1="410" x2="82" y2="410" class="ls-edge" marker-end="url(#ls-arrow)"/>
  <text x="170" y="404" text-anchor="middle" class="ls-a">return the time</text>
  <text x="170" y="424" text-anchor="middle" class="ls-m">…400.001006990</text>
</svg>
</figure>


Rewind hides the CPU's random number instruction, so the only thing
available to the guest kernel is the seed Rewind passes at boot. The kernel's random number generator is seeded with that value, so every run of the same program with the same seed gets the same random numbers.

Most system calls never leave the guest. The few that need the outside world make an exit, and the monitor writes down what happened. The guest kernel also reports when it is idle, so the monitor can jump its clock to the next timer interrupt.[^sleep]

[^sleep]: `sleep(N)` costs no real time. The monitor jumps its clock straight to the deadline and delivers the timer interrupt.

Control those few doors and the guest is deterministic: the outside world shows up at the same step on every run.

So, dafuq is a deterministic VM? Like I said at the start, it's a VM that only gets interrupted when it asks to be. Hopefully that makes a bit more sense now. 😅

[![Expanding brain meme: "Re-run the flaky test until it passes", "Add sleep(1) before the assert", "Record where every interrupt landed and replay it", and, brightest, "Only take an interrupt when the guest asks for one"](/assets/images/rewind_expanding_brain_meme.png)](/assets/images/rewind_expanding_brain_meme.png)
{: style="--image-width: 22rem"}
