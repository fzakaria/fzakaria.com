---
layout: post
title: Nix finally has a source-bootstrapped OpenJDK
date: 2026-07-30 13:44 -0700
---

One of the [earliest requested issues](https://github.com/fzakaria/guixpkgs/issues/3) we had opened on [GuixPkgs](https://github.com/fzakaria/guixpkgs) was to add more packages, specifically OpenJDK.

> "Specifically I would like to see openjdk translated. openjdk is not bootstrapped from source code in nixpkgs" [[issue#3](https://github.com/fzakaria/guixpkgs/issues/3)]

Ever since I learned about the [stage0](https://savannah.nongnu.org/projects/stage0/) bootstrap chain and how Guix [announced full-source](https://guix.gnu.org/en/blog/2023/the-full-source-bootstrap-building-from-source-all-the-way-down/) bootstrap **for all packages** in 2023, I was in awe. They provided a package graph of more than 22,000 nodes rooted in a 357-byte program, including the JDK.[^1]

GuixPkgs can now build OpenJDK 25, which means Nix
now has access to a source-bootstrap build of OpenJDK 🎉

```console
$ nix build .#openjdk \
    --option filter-syscalls false \
    --option sandbox-paths '' \
    --print-out-paths
/nix/store/kihk714ljmvhqh36cigc7mfimv0q0rbr-openjdk-25-guix-wrapped

$ /nix/store/kihk71…-openjdk-25-guix-wrapped/bin/java --version
openjdk 25 2025-09-16
OpenJDK Runtime Environment (build 25+-adhoc.nixbld.source)
OpenJDK 64-Bit Server VM (build 25+-adhoc.nixbld.source, mixed mode, sharing)
```

Does it really work? Let's take it for a spin.

`javac` lives in the `jdk` output, since Guix splits the package.
{:.aside}

```console
$ nix build .#openjdk.unwrapped^jdk
$ cat Hello.java
void main() { IO.println("Hello from a source-bootstrapped JDK"); }

$ ./result-jdk/bin/java Hello.java
Hello from a source-bootstrapped JDK
```

## Why a JDK is a hard package

`javac` is written in Java. `HotSpot` is C++, but the class library it needs is Java, and the compiler that compiles the class library is Java, and it runs on a JVM that needs a class library... and so on. This is a bootstrapping problem.

Nearly every distribution resolves this the same way in practice: download a JDK and use it to build your JDK. Debian [documents the pain](https://wiki.debian.org/PortsDocs/BootstrappingOpenJDK), and the Bootstrappable project has [a whole page](https://www.bootstrappable.org/projects/java.html) on it. They are fun reads, I highly recommend them. What makes JDK special is that there is no actively maintained JDK that can be built from source without a JDK. The authors had to go back quite a few years to find one, and bring it back to life.

> "Unfortunately, most of the software needed for the bootstrap has been abandoned." -- [Bootstrappable](https://www.bootstrappable.org/projects/java.html)

Nixpkgs does the same. `openjdk-25.0.4` is built by `temurin-bin-25.0.3`: a 135 MB prebuilt-tarball.

```console
$ nix-store -qR $(nix eval --raw nixpkgs#openjdk25.drvPath) \
    | grep -iE 'temurin|jdk_x64'
/nix/store/…-OpenJDK25U-jdk_x64_linux_hotspot_25.0.3_9.tar.gz.drv
/nix/store/…-temurin-bin-25.0.3.drv
```

Nixpkgs makes it pretty easy to audit in the [meta.sourceProvenance](https://nixos.org/manual/nixpkgs/unstable/#sec-meta-sourceProvenance) of the package.

```console
$ nix eval --json nixpkgs#temurin-bin-25.meta.sourceProvenance
[{"isSource":false,"shortName":"binaryNativeCode"},
 {"isSource":false,"shortName":"binaryBytecode"}]
```

What does the source provenance of GuixPkgs' `openjdk-25` look like?

It's a little whacky but the overall build chain in Guix is the following:

- **jikes 1.22** (C++) compiles **GNU Classpath 0.93**, a free reimplementation of the Java class library.
- Classpath is enough to bring up **JamVM 1.5.1**, a JVM written in C. Now something can *run* Java.
- Now we can finally use Java tools: **Ant** and **ecj**, the Eclipse Compiler for Java.
- Then it doubles back and rebuilds all of that with the newer versions to get more modern JDK features.
- That stack finally compiles **IcedTea 2.6.13** (OpenJDK 7) → **IcedTea 3.19.0** (OpenJDK 8) → **OpenJDK 9**.
- After which it is one rung at a time: 9 builds 10, 10 builds 11, …, 24 builds 25.

Nineteen complete JDK builds, from a C++ program.

## Analyzing the closure

We can use `nix-store -q --graph` to emit the entire closure as a dot file to visualize the differences.

{:.aside}
I restyled the nodes and edges: dots instead of labelled boxes, and the red to highlight the derivations that exist only because of the JDK bootstrap.

![Two force-directed renderings of complete derivation closures, stacked. The upper panel is nixpkgs' openjdk 25.0.4 with 2758 derivations, and its only red marks are two dots joined by a single short edge. The lower panel is guixpkgs' openjdk 25 with 3556 derivations, visibly wider and denser, with a constellation of 33 red nodes and their connecting edges occupying its lower left.](/assets/images/openjdk-closure-hairballs.png)

The upper panel's entire Java story is those two red dots and the one edge between them: `temurin-bin-25.0.3` → `openjdk-25.0.4`. The lower panel's is the 33-node constellation: the nineteen JDKs, plus the fourteen rungs of jikes, Classpath, JamVM, Ant and ecj that had to exist before anything could compile a JDK at all.

Why is the Nix graph still so big if I claimed it was from a binary distribution?

It turns out that **a JDK closure is mostly not Java.** 

It is a large C++ program that wants X11, cups, fontconfig, freetype, alsa and zlib, sitting on a C toolchain that both sides bootstrap from source. That sub-graph is the same in both and it swamps everything.

I was curious to zoom-in and see the source-bootstrap portion of the derivation graph. Since that shared sub-graph is drowning the signal, I chose to filter it out. 

Which derivations exist in this closure **only** because of how the JDK is bootstrapped? 🤔

That is a reachability query. We delete the Java-provenance nodes from the graph, see what is still reachable from the root, and whatever is left are the derivations that exist only because of the JDK bootstrap.

```python
attributable = reachable(root) - reachable(root, without=java_nodes)
```

| | total closure | sub-graph | exists only for JDK |
| --- | --- | --- | --- |
| nixpkgs `openjdk-25.0.4` | 2758 | 2756 | **2** |
| guixpkgs `openjdk-25` | 3556 | 2680 | **876** |

This lines up with our intuition. Nixpkgs only needs **two** derivations to bootstrap the JDK, while GuixPkgs needs **876**.

![Two pruned graphs, stacked, showing only the derivations that exist because of the JDK bootstrap. A hollow circle marks the openjdk package itself in each. The nixpkgs panel is that circle, one red dot for the prebuilt temurin binary and its tarball, on a single short line. The guixpkgs panel is a cloud of 876 grey dots with the Java packages picked out in red, clustered at two ends of a path that runs through it.](/assets/images/openjdk-java-only-subgraph.svg)

> **Note**
> Interestingly, the bootstrap build for JDK has `rustc` in its closure: IcedTea 8 wants GTK 2, which wants its own Mesa, which wants `rust-bindgen` 😱
{: .alert .alert-note }

The fact that Nix can now build OpenJDK from source is thanks to the amazing work done by Guix developers.

What started off as a fun _art project_, started during [TacoSprint 2026](https://tacosprint.org/), has now found relevance to those interested in bootstraping and reproducible builds.


[^1]: Nixpkgs has made a lot of progress on this front as well, however it is still not fully bootstrapped and relies on plenty of prebuilt binaries.