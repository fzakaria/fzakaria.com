---
layout: post
title: The Nix sandbox is a hidden input
date: 2026-07-30 21:55 -0700
---

The whole beauty of Nix was that it was incredibly pragmatic to achieve "reproducibility", which is quite an overloaded term. The default model for Nix is the [extensional-model]({% post_url 2025-03-08-demystifying-nix-s-intensional-model %}) which is _input-addressed_: the hash of a store path is derived from the _recipe_ (derivation) that produced it, and not the _bytes_ that came out of it. In that framing Nix achieves _repeatability_. Nix, by default, was never bit-for-bit reproducible.[^1]

[^1]: Nix has a `ca-derivations` feature that makes the output path a hash of the output bytes, which is a _different_ model (_extensional-model_).

For this to work, the derivation must be a **complete description** of the build. Anything missing from the derivation causes the _reproducibility_ to break and Nix no longer to be "reproducible".

In a [previous post]({% post_url 2026-07-30-nix-finally-has-a-source-bootstrapped-openjdk %}) I built a source-bootstrapped OpenJDK and we had to provide some additional flags:

```console
$ nix build .#openjdk \
    --option filter-syscalls false \
    --option sandbox-paths '' \
    ...
```

`--option sandbox-paths` mounts additional paths into the sandbox.

You can see the default sandbox paths on your machine with:

```console
$ nix config show sandbox-paths | tr ' ' '\n'
/bin/sh=/nix/store/zrynrzpsy2993w555ns9a734lbzfff2b-busybox-1.37.0/bin/busybox
/nix/store/cdd109fhy1axl7xb5wisv3v5pd6fawdj-qemu-aarch64-binfmt-P
/run/binfmt
```

Okay so what's the point? 

Turns out that these sandbox-paths are a _hidden input_ to the derivation. The derivation does not mention it, but **it can change** the output meaningfully in its _repeatability_ very subtley. 😬

Let's explore this with a small example.

Here is a derivation with no dependencies. It looks for a file `/truth`. If it finds one, it believes it. If not, it falls back to arithmetic.

```nix
# answer.nix
derivation {
  name = "answer";
  system = "x86_64-linux";
  builder = "/bin/sh";
  args = [ "-c" ''
      if [ -f /truth ]; then read -r x < /truth; else x=4; fi
      echo "2 + 2 = $x" > $out
    '' ];
}
```

`/truth` is not in the store, and the Nix sandbox does not mount it, so an honest build never sees it.

```console
$ nix-instantiate ./answer.nix
/nix/store/xbik44ifqm4jqjp4z7n1031smj08mil7-answer.drv

$ nix-store --realise /nix/store/xbik44…-answer.drv
/nix/store/qba6hdgvdrry4k1z83v2zm5xy714l83m-answer

$ cat /nix/store/qba6…-answer
2 + 2 = 4
```

Our output hash is `qba6hdgvdrry4k1z83v2zm5xy714l83m`.

We now can add an additional sandbox-path which will cause the repeatibility of the builder to break. We will mount a file `/truth` into the sandbox that contains a lie.

```console
$ echo 5 > /tmp/truth

$ nix-store --delete /nix/store/qba6…-answer      # throw away the honest one

$ nix-store --realise /nix/store/xbik44…-answer.drv \
    --option extra-sandbox-paths "/truth=/tmp/truth"
/nix/store/qba6hdgvdrry4k1z83v2zm5xy714l83m-answer

$ cat /nix/store/qba6…-answer
2 + 2 = 5
```

Our output hash **is still** `qba6hdgvdrry4k1z83v2zm5xy714l83m`. 😭 

The derivation (`.drv`) is meant to be the complete recipe. Since the sandbox is configured outside the recipe it now causes the same derivation to be leaky and no longer hermetic. Sandboxing is often a way to enforce hermticity and here it _actively breaks it_.

The `sandbox-paths` are nowhere to found in the derivation.

This is in contrast with `__noChroot`, which is a derivation attribute.
{:.aside}

```console
$ nix derivation show /nix/store/xbik44…-answer.drv
{
  "…-answer.drv": {
    "builder": "/bin/sh",
    "args": ["-c", "if [ -f /truth ]; …"],
    "env": { "out": "…qba6…-answer", "name": "answer", … },
    "inputs": { "drvs": {}, "srcs": [] },
    …
  }
}
```

Two people can evaluate a bit-identical `.drv`, run **different actual build steps**, and Nix create the same output hash.

You may be thinking "Well, a derivation could have always relied on `/dev/random` or `date`, so what's new?". True, this is a form of [non-determinism](https://manual.determinate.systems/advanced-topics/diff-hook.html). The difference is those are more evident in the derivations to discover and audit for. The act of checking for the existence of a file is extremely subtle and not something that is easy to discover.

In fact, your derivation may appear to even be byte-reproducible on your machine with the `--check` flag, but it may not be on someone else's machine.

How problematic is this?

The _default_ value of `sandbox-paths` is not a constant baked into the source. It is a **compile-time property of your particular Nix binary**. Two people running `nix --version` that prints the same number can have different sandboxes before either of them touches a flag.

The `/bin/sh` entry is not in my `nix.conf`. It is the default, and it comes from here in the Nix source [src/libstore/globals.cc](https://github.com/NixOS/nix/blob/7362ff0a5883ad122e1a98b20e9bb204e2882c75/src/libstore/globals.cc#L91):

{% raw %}
```cpp
#if (defined(__linux__) || defined(__FreeBSD__)) && defined(SANDBOX_SHELL)
    sandboxPaths = {{"/bin/sh", {.source = SANDBOX_SHELL}}};
#endif
```
{% endraw %}

There are at least two different baselines you can build Nix with, none of them visible to any derivation:

- Built with `sandbox-shell` set to a path and binary with hopefully the same semantics.
- Built without `sandbox-shell` such that the option is empty. No `/bin/sh` at all.

Nix's [own documentation](https://nix.dev/manual/nix/2.35/command-ref/conf-file.html?highlight=sandbox#conf-sandbox-paths) describes this possibility.

> Depending on how Nix was built, the default value for this option may be empty or provide `/bin/sh` as a bind-mount of `bash`.

Although that itself is not true since [Nixpkgs builds Nix](https://github.com/NixOS/nixpkgs/blob/aabe13f270b979709d79f6e29cc9d8f05989d5e8/pkgs/tools/package-management/nix/modular/src/libstore/package.nix#L84) with busybox not bash.

```nix
(lib.mesonOption "sandbox-shell" "${busybox-sandbox-shell}/bin/busybox")
```

Given that Flakes have made Nix become incredibly more decentralized, causing us to rely on _multiple binary caches_, there is no way now to guarantee that the builds are repeatable despite the fact that you can download the binary from the cache.


Is this a bug? 🤔

This is tough to say. Including the `sandbox-paths` in the derivation would make Nix completely unusable. Suppose you did fold `sandbox-paths` into the output hash by having it in the derivation. My busybox is `busybox-1.37.0` at one store path; yours is a different version at a different path. The _same derivation_ would then hash to different outputs on our two machines, and binary-cache sharing across would collapse.

The property that lets us _share_ builds is the same property that lets us _poison_ them.

None of this is hypothetical and this is how it comes back to the OpenJDK from the top. I hit this hidden input building the OpenJDK via [GuixPkgs](https://github.com/fzakaria/guixpkgs), which translates Guix's derivations into Nix and builds them with the Nix daemon.

Guix was forked from Nix much earlier than [the commit](https://github.com/NixOS/nix/commit/a2d92bb20e82a0957067ede60e91fab256948) that introduced `--option sandbox-paths` and as a result `guix-daemon`'s build container has no `/bin` at all, so there is no `/bin/sh`.

Guix packages are built on the assumption that `/bin/sh` does not exist.
As a result when building the OpenJDK, one of the build scripts failed to have it's shebang patched and it was expected to fail. Guix tolerates the failure and carries on. Nix, on the other hand, has `/bin/sh` and the script runs instead of failing, and the build quietly takes a different path which turns out to cause a broken output.

I opened [an issue](https://codeberg.org/guix/guix/issues/10255) on Guix about this accidental behavior.
{:.aside}

Making matters worse, I had already uploaded this broken output to my binary cache. Even when I discovered the `sandbox-paths` was the issue, I kept generating the same `.drv` and thus the same output hash, and was substituting the broken output.

Since `sandbox-paths` is a trusted user setting, I could have maliciously poisoned my own binary cache anyways by signing a broken input. This is only worse in that I did it unknowingly.

>  You can't trust code that you did not totally create yourself.
> — Ken Thompson, [Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/1283920.1283940)
