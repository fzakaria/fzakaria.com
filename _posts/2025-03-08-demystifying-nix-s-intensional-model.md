---
layout: post
title: Demystifying Nix's Intensional Model
date: 2025-03-08 17:30 -0800
---

We just wrapped up [PlanetNix2025](https://planetnix.com/) (North America NixCon), and the excitement about all the innovations and use of Nix was palpable. 💆🏻

What was clear though, was there continues to be a growing divide in understanding the breadth of Nix concepts especially those that are new or put simply _further down [Eelco's PhD thesis](https://edolstra.github.io/pubs/phd-thesis.pdf)_.

One such concept that has recently been released as experimental is [the intensional store model](https://edolstra.github.io/pubs/phd-thesis.pdf#page=143.13), better known as _content-addressed_ (CA) derivations.

> To be frank, I had not looked much at CA derivations earlier as I also found it overwhelming in academic jargon in the PhD thesis.

As always, my goal is to understand things from **first principles** as best as I can; let's see what all the fuss is about. 🕵️

What is a content-addressed derivation? 🤔
Content-addressed derivations themselves are not totally new to Nix.

When you've written `fetchurl` and specified the `hash256` that was a content-addressed derivation.

> The fact that it is content-addressed is why `fetchurl` is allowed to break out of the network sandbox.

```nix
fetchurl {
 url = "http://some-url/archive.zip";
 sha256 = "sha256-4MHp7vkf9t8E1z+l6v8T86ArZ5/uFHTlzK4AciTfbfY="
}
```

The **big difference** with the _intensional model_ is that Nix calculates the sha256 for you!

Let's start off with a chain (`parent` & `child`) of two _expensive_ derivations.

```nix
rec { 
child = pkgs.runCommand "child" {} ''
  echo "Building child"
  sleep 15
  echo "Child finished." > $out
'';
parent = pkgs.runCommand "parent" {} ''
  echo "Building parent"
  sleep 15
  cat ${child} > $out
  echo "Parent finished." >> $out
  '';
}
```

As you would expect, building the `parent` derivation takes roughly **30 seconds**.

```console
> time nix build -f ca-example.nix parent --print-out-paths -L
child> Building child
parent> Building parent
/nix/store/g4ycv0bxjw805n111q6qnwfrja400kbx-parent

________________________________________________________
Executed in   31.48 secs      fish           external
   usr time  194.75 millis  429.00 micros  194.32 millis
   sys time  106.01 millis  585.00 micros  105.42 millis
```

In the _extensional model_, what I like to refer to as _pessimistic hashing_, any minor change (even a comment!) to any of the dependencies causes the _whole graph of descendants to rebuild_.

We can demonstrate this by changing the build steps for the `child` derivation.

```patch
@@ -5,7 +5,7 @@
 in
 rec { 
   child = pkgs.runCommand "child" {} ''
-    echo "Building child"
+    echo "Building child again"
     sleep 15
     echo "Child finished." > $out
   '';
```

Building the `parent` derivation again takes a whole **30 seconds**, as both `parent` **and** `child` must rebuild.

> The `/nix/store` path of the `parent` and the `child` in this case will have had changed.

```console
> time nix build -f ca-example.nix parent --print-out-paths -L
child> Building child again
parent> Building parent
/nix/store/7kkfgvmg6zzh2qydaw8az139nwvsny4j-parent

________________________________________________________
Executed in   30.85 secs      fish           external
   usr time  377.05 millis    0.24 millis  376.82 millis
   sys time  186.49 millis    1.14 millis  185.35 millis
```

Let's modify our derivations now to be _content-addressed_.

We enable this very simply by adding `__contentAddressed = true;` to our derivations.

```nix
rec { 
child-ca = pkgs.runCommand "child" {
  __contentAddressed = true;
} ''
  echo "Building child"
  sleep 15
  echo "Child finished." > $out
'';
parent-ca = pkgs.runCommand "parent" {
   __contentAddressed = true;
} ''
  echo "Building parent"
  sleep 15
  cat ${child-ca} > $out
  echo "Parent finished." >> $out
  '';
}
```

At first build, it does take the same **30 seconds** (sorry it's not that _magical_).

```console
> time nix build -f ca-example.nix parent-ca --print-out-paths -L
child-ca> Building child.
parent-ca> Building parent
/nix/store/slqvkr6sklp8a26ql5ra21x77fh1782n-parent-ca

________________________________________________________
Executed in   30.85 secs      fish           external
   usr time  380.73 millis    1.15 millis  379.58 millis
   sys time  190.14 millis    0.18 millis  189.96 millis
```

We now apply **the exact same patch** as above and try to rebuild.

```console
> time nix build -f ca-example.nix parent-ca --print-out-paths -L
child-ca> Building child again.
/nix/store/slqvkr6sklp8a26ql5ra21x77fh1782n-parent-ca

________________________________________________________
Executed in   15.67 secs      fish           external
   usr time  331.65 millis    0.91 millis  330.74 millis
   sys time  191.40 millis    1.90 millis  189.50 millis
```

Aha! It only took **15 seconds** now because we were able to avoid rebuilding our `parent-ca` derivation. 😲

> In this case the **both** `/nix/store` paths of `parent` and `child` are unchanged.

This is ultimately one of the _main benefits_ of content-addressed derivations: early-cutoff optimization.

**Early-cutoff optimization**
: If your dependencies have not changed at all (bit-for-bit), you can avoid rebuilding yourself.

Since the content-addressed (i.e. sha256) of `child` had not changed, rebuilding `parent` was avoided.

> There's also a whole slew of additional benefits about the ability to now trust your `/nix/store` with multiple users that the PhD goes into.

Okay great! This sounds like a total win! What are the downsides?

Well there are a few and they have to do with whether the software itself is not _binary reproducible_.

There's a slough of problems that this can cause. For instance, there may be multiple possible content-addressed paths for the same derivation! 🤯

If your output is not bit-reproducible, there are cases where you might have to rebuild your dependency tree whereas the "pessimistic" model would not have to as the hash calculated there would not have changed.

There's some other potential pitfalls that were also outlined in the original PhD, such as the "two glibc issue", but according to [RFC#0062](https://github.com/tweag/rfcs/blob/cas-rfc/rfcs/0062-content-addressed-paths.md) which outlines the implementation, additional metadata SQLite tables and Nix binary-cache store information is included to avoid these class of problems.

I don't think it's at a state quite yet where I'll be turning it on globally in my `nix.conf` -- but familiarity will be useful for the next entry where we discuss _dynamic-derivations_ which seem to rely and require CA derivations.

_Note to readers:_ I would have loved to calculate by hand the `/nix/store` path as is done in [nix-pills#18](https://nixos.org/guides/nix-pills/18-nix-store-paths.html); however I could not seem to reproduce the hash. If you have insight or a good example, please reach out so I can update the entry. 🙏