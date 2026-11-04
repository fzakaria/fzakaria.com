---
layout: post
title: 'What if every Nix build were bit-reproducible?'
date: 2026-11-09 10:00 -0800
excerpt_separator: <!--more-->
---

The holy grail of build systems and package managers is bit-reproducible[^bit] builds. This is such a desired trait that nearly every Linux distribution has a [reproducible builds project](https://reproducible-builds.org/who/projects/) to track the progress and validity of their builds.

[^bit]: It's lame that I have to keep clarifying it as "bit" reproducible but the term is overloaded.

Why is bit-reproducibility so important? Trust. You can trust that the software you are running has not been tampered with and is the same as what the developers intended if you can verify that when built from source, the output is identical.

Making software bit-reproducible though is hard. There are a lot of ways that can introduce non-determinism into a build: timestamps, random seeds, thread scheduling, and more. Most distributions that have achieved "reproducible builds" have done so for only a subset of their packages, usually those that comprise the core of the ISO or distribution.

Nix's default model, the [extensional model]({% post_url 2025-03-08-demystifying-nix-s-intensional-model %}) (input-addressed), famously works around the need for bit-reproducibility by hashing the inputs to a build and using that hash as the store path. This lets the build be repeatable even if the output is not bit-for-bit identical. It is an incredibly pragmatic solution to making builds repeatable, but it does not solve the problem of trust. We are still trusting the outputs uploaded to [cache.nixos.org](https://cache.nixos.org) have not been tampered with.

Nix also has an experimental [content-addressed model]({% post_url 2025-03-08-demystifying-nix-s-intensional-model %}) (intensional model) where the `/nix/store` paths are based on the content of the output, but crucially, it does not guarantee that the builds are bit-reproducible.

This leaves us with an undesirable situation regardless of the model. For the extensional model, the smallest change in the inputs changes the store path which causes a cascade of rebuilds. For the intensional model, a single derivation can produce multiple different outputs.

<figure>
<svg viewBox="0 0 680 300" role="img"
     style="display:block;margin-inline:auto;max-width:40rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="Two panels. On the left, the extensional model: a chain of four packages, glibc, zlib, openssl and curl, each depending on the one before. One byte changes in glibc, and the store path under every package in the chain is struck out and replaced with a new one. On the right, the intensional model: one derivation, hello.drv, built from the same inputs, fans out to three outputs with three different store paths, built at three different times.">
  <defs>
    <marker id="mm-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor"/>
    </marker>
    <marker id="mm-arrow-red" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" fill="#b1201d"/>
    </marker>
  </defs>

  <!-- divider between the two models -->
  <line x1="340" y1="14" x2="340" y2="286" stroke="currentColor" stroke-opacity="0.35" stroke-width="1" stroke-dasharray="4 4"/>

  <!-- left panel: the extensional model -->
  <text x="170" y="24" font-size="13" font-weight="700" text-anchor="middle" fill="currentColor">Extensional model</text>
  <text x="170" y="40" font-size="11" text-anchor="middle" fill="currentColor" fill-opacity="0.65">input-addressed</text>

  <g transform="translate(0,20)">
  <text x="14" y="78" font-size="11" fill="#b1201d">one byte changes</text>
  <line x1="30" y1="84" x2="30" y2="100" stroke="#b1201d" stroke-width="1.6" marker-end="url(#mm-arrow-red)"/>

  <g font-size="12" text-anchor="middle">
    <rect x="14" y="104" width="62" height="34" rx="3" fill="#fbf7ee" stroke="#b1201d" stroke-width="1.8"/>
    <text x="45" y="125" fill="#222">glibc</text>
    <rect x="98" y="104" width="62" height="34" rx="3" fill="#fbf7ee" stroke="#b1201d" stroke-width="1.8"/>
    <text x="129" y="125" fill="#222">zlib</text>
    <rect x="182" y="104" width="62" height="34" rx="3" fill="#fbf7ee" stroke="#b1201d" stroke-width="1.8"/>
    <text x="213" y="125" fill="#222">openssl</text>
    <rect x="266" y="104" width="62" height="34" rx="3" fill="#fbf7ee" stroke="#b1201d" stroke-width="1.8"/>
    <text x="297" y="125" fill="#222">curl</text>
  </g>

  <g stroke="currentColor" stroke-width="1.6" marker-end="url(#mm-arrow)">
    <line x1="78" y1="121" x2="96" y2="121"/>
    <line x1="162" y1="121" x2="180" y2="121"/>
    <line x1="246" y1="121" x2="264" y2="121"/>
  </g>

  <!-- the old store paths, struck out, and the new ones -->
  <g font-size="10" text-anchor="middle" fill="currentColor" fill-opacity="0.5">
    <text x="45" y="162">x7mq2v…</text>
    <text x="129" y="162">9kd0zl…</text>
    <text x="213" y="162">p3vn8a…</text>
    <text x="297" y="162">c1rw5y…</text>
  </g>
  <g stroke="currentColor" stroke-opacity="0.5" stroke-width="1">
    <line x1="24" y1="159" x2="66" y2="159"/>
    <line x1="108" y1="159" x2="150" y2="159"/>
    <line x1="192" y1="159" x2="234" y2="159"/>
    <line x1="276" y1="159" x2="318" y2="159"/>
  </g>
  <g font-size="10" text-anchor="middle" fill="#b1201d">
    <text x="45" y="178">ba4ks1…</text>
    <text x="129" y="178">h0wq7f…</text>
    <text x="213" y="178">6jtm9d…</text>
    <text x="297" y="178">rz2pl8…</text>
  </g>
  <g font-size="10" text-anchor="middle" fill="#b1201d" fill-opacity="0.75">
    <text x="45" y="196">rebuilt</text>
    <text x="129" y="196">rebuilt</text>
    <text x="213" y="196">rebuilt</text>
    <text x="297" y="196">rebuilt</text>
  </g>

  </g>
  <text x="170" y="262" font-size="13" text-anchor="middle" fill="currentColor">One input changes,</text>
  <text x="170" y="280" font-size="13" text-anchor="middle" fill="currentColor">every path downstream changes</text>

  <!-- right panel: the intensional model -->
  <text x="510" y="24" font-size="13" font-weight="700" text-anchor="middle" fill="currentColor">Intensional model</text>
  <text x="510" y="40" font-size="11" text-anchor="middle" fill="currentColor" fill-opacity="0.65">content-addressed</text>

  <text x="406" y="124" font-size="11" text-anchor="middle" fill="currentColor" fill-opacity="0.65">same inputs</text>
  <rect x="364" y="132" width="84" height="38" rx="3" fill="#fbf7ee" stroke="currentColor" stroke-width="1.8"/>
  <text x="406" y="156" font-size="12" text-anchor="middle" fill="#222">hello.drv</text>

  <g fill="none" stroke="currentColor" stroke-width="1.6" marker-end="url(#mm-arrow)">
    <path d="M450,151 C494,151 496,83 540,83"/>
    <line x1="450" y1="151" x2="540" y2="151"/>
    <path d="M450,151 C494,151 496,219 540,219"/>
  </g>

  <g text-anchor="middle">
    <rect x="542" y="64" width="124" height="38" rx="3" fill="#fbf7ee" stroke="currentColor" stroke-width="1.8"/>
    <text x="604" y="80" font-size="10" fill="#b1201d">/nix/store/q7xm…</text>
    <text x="604" y="95" font-size="10" fill="#222" fill-opacity="0.65">built Mon 14:02</text>
    <rect x="542" y="132" width="124" height="38" rx="3" fill="#fbf7ee" stroke="currentColor" stroke-width="1.8"/>
    <text x="604" y="148" font-size="10" fill="#b1201d">/nix/store/d04c…</text>
    <text x="604" y="163" font-size="10" fill="#222" fill-opacity="0.65">built Tue 09:48</text>
    <rect x="542" y="200" width="124" height="38" rx="3" fill="#fbf7ee" stroke="currentColor" stroke-width="1.8"/>
    <text x="604" y="216" font-size="10" fill="#b1201d">/nix/store/9f2k…</text>
    <text x="604" y="231" font-size="10" fill="#222" fill-opacity="0.65">built Wed 17:31</text>
  </g>

  <text x="510" y="262" font-size="13" text-anchor="middle" fill="currentColor">One derivation,</text>
  <text x="510" y="280" font-size="13" text-anchor="middle" fill="currentColor">many different outputs</text>
</svg>
</figure>

What if every build could be bit-reproducible? What would that mean for Nix and the extensional model?

I have been working on [Rewind](https://rewindvm.dev), a deterministic virtual machine. It runs builds in a deterministic environment, which so far has mostly been used to investigate bugs. I have been thinking about what else a platform that runs builds deterministically makes possible.

I started this thought by exploring how to [make profile-guided optimization reproducible]({% post_url 2026-11-07-making-profile-guided-optimization-reproducible %}) but I was just scratching the surface.

## The machine is an input

When we try to make a build bit-reproducible, we usually go hunting for the sources of non-determinism: timestamps, random seeds, thread order. These are inputs the derivation does not account for, so they are not hashed into the store path.

A simpler approach is to run the whole build inside a deterministic machine.

<figure>
<svg viewBox="0 0 680 300" role="img"
     style="display:block;margin-inline:auto;max-width:40rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="On the left a die, an alarm clock and a tangle of thread tumble around loose, labelled as what a build implicitly depends on. An arrow leads to the right, where the same three objects sit still inside a parcel of bubble wrap with a shipping label that reads epoch 1790985600, seed 0, schedule 0, to /nix/store. The parcel is labelled making the implicit explicit.">
  <defs>
    <marker id="bw-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor"/>
    </marker>
    <pattern id="bw-bubbles" width="24" height="42" patternUnits="userSpaceOnUse">
      <circle cx="12" cy="10.5" r="9.5" fill="#8fbbe0" fill-opacity="0.28" stroke="currentColor" stroke-opacity="0.45" stroke-width="1"/>
      <path d="M6.5,7.5 a6.5,6.5 0 0 1 5,-3.5" fill="none" stroke="#ffffff" stroke-opacity="0.9" stroke-width="1.6" stroke-linecap="round"/>
      <circle cx="0" cy="31.5" r="9.5" fill="#8fbbe0" fill-opacity="0.28" stroke="currentColor" stroke-opacity="0.45" stroke-width="1"/>
      <circle cx="24" cy="31.5" r="9.5" fill="#8fbbe0" fill-opacity="0.28" stroke="currentColor" stroke-opacity="0.45" stroke-width="1"/>
      <path d="M18.5,28.5 a6.5,6.5 0 0 1 5,-3.5" fill="none" stroke="#ffffff" stroke-opacity="0.9" stroke-width="1.6" stroke-linecap="round"/>
    </pattern>
    <g id="bw-die">
      <path d="M0,-30 L28,-16 L0,-2 L-28,-16 z" fill="#fbf7ee" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
      <path d="M-28,-16 L0,-2 L0,30 L-28,16 z" fill="#efe8d8" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
      <path d="M28,-16 L0,-2 L0,30 L28,16 z" fill="#e2d9c4" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>
      <ellipse cx="0" cy="-16" rx="4.5" ry="2.6" fill="#b1201d"/>
      <ellipse cx="-20" cy="-2" rx="2.2" ry="3.4" fill="#222"/>
      <ellipse cx="-8" cy="18" rx="2.2" ry="3.4" fill="#222"/>
      <ellipse cx="8" cy="6" rx="2.2" ry="3.4" fill="#222"/>
      <ellipse cx="14" cy="14" rx="2.2" ry="3.4" fill="#222"/>
      <ellipse cx="20" cy="-2" rx="2.2" ry="3.4" fill="#222"/>
      <ellipse cx="8" cy="20" rx="2.2" ry="3.4" fill="#222"/>
      <ellipse cx="20" cy="10" rx="2.2" ry="3.4" fill="#222"/>
    </g>
    <g id="bw-clock">
      <path d="M-20,-22 a9,9 0 0 1 14,-8" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round"/>
      <path d="M20,-22 a9,9 0 0 0 -14,-8" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round"/>
      <line x1="-14" y1="20" x2="-20" y2="29" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>
      <line x1="14" y1="20" x2="20" y2="29" stroke="currentColor" stroke-width="3" stroke-linecap="round"/>
      <circle r="24" fill="#fbf7ee" stroke="currentColor" stroke-width="2.2"/>
      <line x1="0" y1="0" x2="0" y2="-15" stroke="#222" stroke-width="2.4" stroke-linecap="round"/>
      <line x1="0" y1="0" x2="11" y2="6" stroke="#222" stroke-width="2.4" stroke-linecap="round"/>
      <circle r="2.4" fill="#b1201d"/>
    </g>
    <g id="bw-thread" fill="none" stroke="#3f9a9f" stroke-width="2.2" stroke-linecap="round">
      <path d="M-30,6 C-34,-24 6,-34 18,-14 C30,6 -6,28 -18,10 C-28,-6 4,-22 14,-4 C22,10 -2,20 -10,8 C-16,-2 2,-10 8,0"/>
      <path d="M-26,-12 C-6,-30 30,-22 26,4 C22,26 -14,30 -24,12"/>
      <path d="M18,-14 C34,-26 40,-8 46,-20"/>
      <path d="M-18,10 C-30,22 -40,14 -46,24"/>
    </g>
    <path id="bw-parcel" d="M408,74 C440,44 548,40 590,78 C626,112 624,190 590,222 C548,258 438,256 404,224 C372,194 374,106 408,74 z"/>
  </defs>
  <g transform="translate(72,92) rotate(-18)"><use href="#bw-die"/></g>
  <g transform="translate(176,74) rotate(14)"><use href="#bw-clock"/></g>
  <g transform="translate(124,178) rotate(-8)"><use href="#bw-thread"/></g>
  <g fill="none" stroke="currentColor" stroke-opacity="0.55" stroke-width="1.6" stroke-linecap="round">
    <path d="M30,56 q-10,10 -6,24"/>
    <path d="M22,70 q-8,8 -5,18"/>
    <path d="M216,50 q10,8 9,22"/>
    <path d="M226,66 q7,7 6,16"/>
    <path d="M70,206 q-6,10 2,20"/>
    <path d="M184,200 q8,8 2,20"/>
  </g>
  <text x="124" y="262" font-size="13" text-anchor="middle" fill="currentColor">What a build</text>
  <text x="124" y="280" font-size="13" text-anchor="middle" fill="currentColor">implicitly depends on</text>
  <line x1="262" y1="148" x2="356" y2="148" stroke="currentColor" stroke-width="1.8" marker-end="url(#bw-arrow)"/>
  <text x="309" y="136" font-size="13" text-anchor="middle" fill="currentColor">inRewind</text>
  <g transform="translate(446,118) scale(0.86)"><use href="#bw-die"/></g>
  <g transform="translate(556,112) scale(0.86)"><use href="#bw-clock"/></g>
  <g transform="translate(446,198) scale(0.78)"><use href="#bw-thread"/></g>
  <use href="#bw-parcel" fill="url(#bw-bubbles)" stroke="currentColor" stroke-width="2"/>
  <g transform="translate(84,32) rotate(-4 510 176)">
    <rect x="428" y="150" width="150" height="62" rx="3" fill="#fbf7ee" stroke="#222" stroke-width="1.4"/>
    <text x="438" y="168" font-size="11" fill="#222">epoch    1790985600</text>
    <text x="438" y="183" font-size="11" fill="#222">seed 0   schedule 0</text>
    <line x1="436" y1="190" x2="570" y2="190" stroke="#222" stroke-width="0.8" stroke-dasharray="3 2"/>
    <text x="438" y="205" font-size="11" font-weight="700" fill="#b1201d">TO: /nix/store</text>
  </g>
  <text x="500" y="280" font-size="13" text-anchor="middle" fill="currentColor">Making the implicit explicit</text>
</svg>
</figure>


[Eelco's thesis](https://edolstra.github.io/pubs/phd-thesis.pdf) says outright that the extensional model assumes the builder is impure (§5.7).

> Build operations in general are not pure: the contents that a builder stores in the output path can depend on impure factors such as the system time. [...] Thus, while any derivation can have a potentially infinite set of output path contents that can be produced by an execution of its builder, we view the elements of that set as interchangeable.
>
> But this is a model—an assumption about builders.

Running a build within [Rewind](https://rewindvm.dev) captures all of the implicit inputs to a build and makes them explicit, which makes any build bit-reproducible. 🤯

> **Aside:**
> New to Rewind? Start with [a flaky build you only catch once]({% post_url 2026-10-01-rewind-vm-a-flaky-build-you-only-catch-once %}) and [dafuq is a deterministic VM?]({% post_url 2026-10-24-dafuq-is-a-deterministic-vm %})
{: .alert .alert-note }

We can wrap any derivation in Rewind with a Nix function. [`inRewind`](https://github.com/fzakaria/rewindvm/blob/main/nix/lib.nix) takes the machine's inputs and a derivation, and returns the same derivation with its builder running inside Rewind:[^kvm]

[^kvm]: Rewind is a KVM-based virtual machine, so it requires a host with KVM support. It also requires the `rewind-amd` or `rewind-intel` system feature to be advertised by the host.

```nix
let
  inherit (rewind.lib.x86_64-linux) inRewind;
  deterministic = inRewind {
    epoch = 1790985600;
    seed = 0;
    schedule = 0;
  };
in
deterministic pkgs.hello
```

It works on any derivation and the resulting derivation is bit-reproducible every time.[^guarantee]

[^guarantee]: On the same Rewind version and the same CPU vendor. Fixed-output derivations are refused, because they need the network and the VM has none.

Let's look at a simple example of a build that is not bit-reproducible, and how when wrapped in Rewind, it becomes bit-reproducible.

Here is a simple C program that prints a greeting and depends on a library. The derivation adds a build id and a build time to the output similar to what release builds often do to "stamp" their builds. The build id and build time are two common sources of non-determinism in builds.

```nix
let
  build =
    if machine == "rewind" then
      inRewind { epoch = 1790985600; seed = 0; schedule = 0; }
    else
      (drv: drv);
  extra = lib.optionalAttrs ca { __contentAddressed = true; };
in
rec {
  greet = build (
    pkgs.runCommandCC "greet" extra ''
      cp ${./greet.h} greet.h; cp ${./greet.c} greet.c
      mkdir -p $out
      cc -c greet.c -o $out/greet.o \
        -DBUILD_ID="\"$(cat /proc/sys/kernel/random/uuid)\"" \
        -DBUILT_AT="\"$(date -u +%FT%TZ)\""
    ''
  );

  hello = build (
    pkgs.runCommandCC "hello" extra ''
      cp ${./greet.h} greet.h; cp ${./main.c} main.c
      mkdir -p $out/bin
      cc main.c ${greet}/greet.o -o $out/bin/hello
    ''
  );
}
```

We have wrapped the derivation in a function to control whether the build runs in Rewind or not, and whether the build is content-addressed or not.
{: .aside}


Built on the host under the input-addressed model, `greet` fails `--check`:

```console
$ nix-build -A greet --arg ca false --check
error: derivation '/nix/store/2hm8ram0…-greet.drv' may not be deterministic:
output "/nix/store/kjx5rzjk…-greet" differs
```

Built in Rewind, the same derivation passes:

```console
$ nix-build -A greet --arg ca false --argstr machine rewind
building '/nix/store/bxh3c25a…-greet.drv'...
inRewind: run c7be39a9ea6be3de exited:0 after 2157 steps
/nix/store/lrx579rx…-greet

$ nix-build -A greet --arg ca false --argstr machine rewind --check
checking outputs of '/nix/store/bxh3c25a…-greet.drv'...
inRewind: run c7be39a9ea6be3de exited:0 after 2157 steps
/nix/store/lrx579rx…-greet

$ nix-build -A hello --arg ca false --argstr machine rewind
building '/nix/store/1bkqfsg3…-hello.drv'...
inRewind: run 54b543a1c6b65b46 exited:0 after 2439 steps
/nix/store/y8r98q35…-hello

$ ./result/bin/hello
hello, world
build aabe0f2b-f5d1-477f-b3b8-3e7f1755dc0f at 2026-10-03T00:00:00Z
```
{: data-mark="3,4,8,9,18"}

The UUID still comes from the kernel's random pool and the time still comes from the clock. They are the same on every build because the pool's seed and the clock's start are initialized from the same values.
{: .aside}

Nice! We just got a build that is bit-reproducible even if it's not content-addressed.

You can find more details of the library and even making Rewind a Nix `external-builder` on [Rewind's Nix build reference](https://rewindvm.dev/nix-builds.html).

What does that mean for the content-addressed model?

Since the outputs are not bit-reproducible, the same derivation gets a different `/nix/store` path on each rebuild.[^two]

[^two]: Two stores are used to illustrate buids on different machines.

```console
$ nix-build -A hello --arg ca true --store ./store-a
resolved derivation: '/nix/store/5v566cv6…-hello.drv' -> '/nix/store/83qn27rk…-hello.drv'...
/nix/store/rwaisri0…-hello

$ nix-build -A hello --arg ca true --store ./store-b
resolved derivation: '/nix/store/5v566cv6…-hello.drv' -> '/nix/store/0rjbw8s8…-hello.drv'...
/nix/store/wvy9zby9…-hello

$ nix realisation info -f . greet --arg ca true --store ./store-a
rbzv0mbw…-greet.drv^out -> bryxd8dy…-greet

$ nix realisation info -f . greet --arg ca true --store ./store-b
rbzv0mbw…-greet.drv^out -> hh2v12cs…-greet
```
{: data-mark="3,7,10,13"}

Producing multiple variants is problematic and the thesis notes the consequence (§6.4.1): you can end up with a closure that contains more than one variant of the same derivation.

> The fact that a derivation can resolve to any number of output paths due to impurity, leads to the problem that we might end up with a closure that contains more than one element from the output equivalence class of a derivation.

With `inRewind`, both stores build the same bytes and print the same path:[^nix-version]

```console
$ nix-build -A hello --arg ca true --argstr machine rewind --store ./store-a
inRewind: run 4d9de4235038d6d0 exited:0 after 2158 steps
inRewind: run 3a2797f47898d7ce exited:0 after 2438 steps
/nix/store/daqfk0jm…-hello

$ nix-build -A hello --arg ca true --argstr machine rewind --store ./store-b
inRewind: run 4d9de4235038d6d0 exited:0 after 2158 steps
inRewind: run 3a2797f47898d7ce exited:0 after 2438 steps
/nix/store/daqfk0jm…-hello

$ nix realisation info -f . greet --arg ca true --argstr machine rewind --store ./store-a
q6i384y2…-greet.drv^out -> kvjqc292…-greet

$ nix realisation info -f . greet --arg ca true --argstr machine rewind --store ./store-b
q6i384y2…-greet.drv^out -> kvjqc292…-greet
```
{: data-mark="4,9,12,15"}

One derivation, one path, in every store.

[^nix-version]: Nix 2.35 changed how it hashes an output that mentions its own path, so the content address of such an output depends on the Nix version.

Bit-reproducible outputs also mean cache hits across machines. If the bytes are the same, the content address is the same, and a path one machine built is a hit for every other: early cutoff optimization ftw!

## Both panels collapse

When we make every build bit-reproducible, the two models collapse into one. What does this mean for the extensional model?

The extensional model was a wonderful pragmatic solution to a world where determinism was not guaranteed but it came at a cost: a single change in the inputs cascades through every downstream derivation. Adoption to content-addressed derivations has been slow similarly because producing multiple outputs makes it hard to reason about the closure of a derivation. When we have guaranteed bit-reproducibility, both problems disappear.

Having a stable platform with which to build software reproducibly might completely change the toil of working to make software reproducible and change the economics of whether to leverage content-addressed derivations.

The usefulness of a reproducible environment is not well explored and I think there are other interesting use cases for it. One that I'm exploring is to use it to make the act of performing a benchmark reproducible.

> **Aside**
> The cost is that the machine is now an input, Rewind included. Upgrade Rewind and every wrapped derivation rebuilds. Build on an Intel machine and you get a different, equally reproducible, output than on AMD. 
{: .alert .alert-note }

A tool that was designed for bug investigation and reproducibility of builds might have a larger impact on the software ecosystem than I had originally thought. It is a tool that can be used to make software more trustworthy, and all the wonderful beefits that come with it.