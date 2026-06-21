---
layout: post
title: Nix needs relocatable binaries
date: 2026-06-21 10:19 -0700
---

> This is my problem statement and proposal for a [TacoSprint 2026](https://tacosprint.org/) project 🏄.

Nix, or _store-based systems_, are a class of package managers that use a well-defined prefix to store all packages. This can be `/nix/store` for Nix or `/gnu/store` for Guix.

This is simple. It makes _rewriting_ paths to binaries or libraries easy. Derivations only need to `sed` the strings with the full store-path; `/bin/bash` becomes `/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash` for instance.

What if you wanted a different path, one not prefixed at the root `/` ?

This could be desirable if you don't have Nix installed already or are missing necessary permissions -- "rootless Nix".

Well, Nix already lets you specify a different store-path today _but there is a catch!_

Let's take a look at a simple example.
We can build `hello` two different ways.

```bash
> nix build nixpkgs#hello

> nix build --store /tmp/fzakaria/store nixpkgs#hello
```

The first command builds and installs `hello` at `/nix/store/zi2bj2hlavv8q743li2s9diqbcpmrf9b-hello-2.12.3/` and the second at `/tmp/fzakaria/store/nix/store/zi2bj2hlavv8q743li2s9diqbcpmrf9b-hello-2.12.3/` using `chroot` and mount namespaces.

Notice both have the same hash `zi2bj2hlavv8q743li2s9diqbcpmrf9b`.

**This is important.** By keeping the hash the same, we can leverage the precomputed derivations from binary substituters like [https://cache.nixos.org](https://cache.nixos.org).

Ok, so what's missing?

If you are using tools like [Bazel](https://bazel.build/) or [Buck2](https://buck2.build/) they likely already employ their own sandboxing via namespacing for builds. Integrating Nix into these ecosystems becomes incredibly impractical because we run into nested user namespace and mount restrictions.

We can ask `Nix` to use an alternate store prefix, _without chroot and mount namespaces_ but it has a big gap.

```bash
> XDG_CACHE_HOME=/tmp/fzakaria/cache \
nix eval --store 'local?store=/tmp/fzakaria/store&state=/tmp/fzakaria/state&log=/tmp/fzakaria/log' \
--raw nixpkgs#hello.outPath
/tmp/fzakaria/store/qv3fhi1j9gh27fyds5n5b16yia8i6zn5-hello-2.12.3
```

The hash is now `qv3fhi1j9gh27fyds5n5b16yia8i6zn5` 😭

It's even more disastrous. Changing this simple string cascade-invalidates the entire dependency graph. You are now waiting 4 hours for GCC to compile just so you can print "Hello World" from a different folder. 🫠

This means we cannot leverage the public cache. This gap is called out by the [Nix documentation](https://nix.dev/manual/nix/2.24/store/types/local-store) today.

Does it have to be that way?

What if we could install Nix binaries _anywhere_, without using namespacing or `chroot`. Can we have our cake and eat it too? 🍰

Nix needs **relocatable binaries**.

The problem is that the store-prefix is part of the derivation itself so it affects the hash calculation.

We don't have to specify the full store-prefix everywhere. What if we used relative paths ? 🤔

Let's look at one place the full paths are written today in the binary via `RUNPATH`.

```bash
> patchelf $(nix build --no-link --print-out-paths nixpkgs#hello)/bin/hello \
            --print-rpath
/nix/store/57iz36553175g3178pvxjij8z5rcsd4n-glibc-2.42-61/lib
```

When this program runs, the dynamic linker looks at `RUNPATH` to find its shared dependencies.

The loader in Linux however natively supports the variable `$ORIGIN` which translates to "the directory containing the executable." [[ref](https://man7.org/linux/man-pages/man8/ld.so.8.html)]

We could instead write the `RUNPATH` to be `$ORIGIN/../../57iz36553175g3178pvxjij8z5rcsd4n-glibc-2.42-61/lib`.

If we did that then changing the store would cause no hashes to change. No recompilation. 🥳

Okay, so are we done?

Well, like most things the devil is in the details. 😈

Before the dynamic linker can read the `RUNPATH` to find the necessary libraries, the Linux kernel has to load the dynamic linker itself. This path is stored in a different ELF header called `PT_INTERP` (Program Interpreter).

```bash
> patchelf $(nix build --no-link --print-out-paths nixpkgs#hello)/bin/hello \
        --print-interpreter
/nix/store/57iz36553175g3178pvxjij8z5rcsd4n-glibc-2.42-61/lib/ld-linux-x86-64.so.2
```

Unfortunately, the Linux Kernel does not support `$ORIGIN` in this field _as of today_.

We run into the exact same kernel limitation with the shebang line in scripts as well.

```bash
#!/nix/store/gik3rh1vz2jlgnifb9dh6vc6sxwwz9jj-bash-5.3p9/bin/bash
echo "Hello!"
```

When we execute a script, the kernel parses the `#!` (shebang) and expects an absolute path. Support for `$ORIGIN` is also lacking as _as of today_.

We cannot use relative paths reliably here unless they are relative to the current working directory, which breaks the moment you run the script from anywhere else.

### How Do We Get There? 🗺️

To achieve true relocatable binaries, we need to bypass these kernel limitations. `$ORIGIN` historically would never make sense for `PT_INTERP` in the Linux kernel because "Why would you want your dynamic linker to be found relative to the file!?".

Nix has changed that assessment. There are a few ways we could attack this:

1. We could patch the Linux kernel so that `$ORIGIN` is supported in `PT_INTERP` and the shebang.
2. We wrap every binary with a small static binary that computes its own location and then invokes the dynamic linker.
3. We need to replace file locations to also leverage language-specific features for relative paths. For instance, in Python we can leverage `__file__` to access files relative to itself similar to `$ORIGIN`.

I believe augmenting support in the Linux kernel is the right approach. The beauty of Nix is we can even patch the kernel today in any NixOS machine for this support.

As a final cherry on top, we can include additional metadata `relocatable = true;` on every derivation whether it's _relocatable_. 🍒
