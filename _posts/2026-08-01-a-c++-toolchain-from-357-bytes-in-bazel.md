---
layout: post
title: A C++ toolchain from 357 bytes, in Bazel
date: 2026-08-01 14:10 -0700
---
I have been fascinated and amazed by [stage0](https://savannah.nongnu.org/projects/stage0/) for a while now ever since I learnt about it via Guix [using it](https://guix.gnu.org/en/blog/2023/the-full-source-bootstrap-building-from-source-all-the-way-down/) to provide twenty two thousand packages source-bootstrapped from the 357-byte seed.

What is stage0?

It is a chain of compilers and assemblers that can be built from source, starting from **a 357-byte** program that can eventually build a recent GCC.[^gcc]

[^gcc]: Once you can reach a recent-enough GCC, you can build any C/C++ program and beyond easily.

Since then, [NixOS](https://discourse.nixos.org/t/a-full-source-bootstrap-for-nixos/74801) and [other distributions](https://github.com/fosslinux/live-bootstrap) have also adopted the same approach to minimize their binary seed which makes it possible to onboard new architectures and platforms much simpler.

What's always _frustrated_ me as a [Bazel](https://bazel.build/) (& [Buck](https://buck2.build/)) user is the reliance on prebuilt toolchains even for things that should be built from source [easily like protoc]({% post_url 2024-11-28-bazel-knowledge-protobuf-is-the-worst-when-it-should-be-the-best %}).

Bazel has given up trying to provide a hermetic C++ toolchain and the upstream [rules_cc](https://github.com/bazelbuild/rules_cc) ruleset just points you elsewhere:

> Configuring a hermetic toolchain makes your build more deterministic. rules_cc itself does not yet offer a hermetic toolchain distribution

I had attempted to provide a stage0 hermetic C++ toolchain in [October 2024](https://github.com/fzakaria/stage0-bazel/tree/d22d6b050f66a93c1b843c24b8f17dc519dd4802) via [https://github.com/fzakaria/stage0-bazel](https://github.com/fzakaria/stage0-bazel). I made substantial process through the bootstrap process but I did not make it far enought to be usabale.

To be honest, I was also a little disheartened that no one else in the community thought it was the greatest thing since slice bread. Everyone seems to be content with using prebuilt toolchains as they go deeper into [MODULE.bzl madness]({% post_url 2024-07-02-reproducibility-in-disguise %}).

I had put it aside for a while, but I have been thinking about it again recently. The steps are mechanical and the process imitates existing distributions, so this became a perfect project for me to throw at an LLM to finish.[^llm]

[^llm]: Consider this the disclosure that I used an LLM to help me write the remainder of the toolchain.

You can now leverage the toolchain to build `cc_binary` in Bazel and have it compiled by a toolchain whose **entire ancestry** is in the repository from that same **357-byte seed**. 🎆

How complete is this toolchain?

I pointed the toolchain at [Abseil](https://abseil.io/) and [GoogleTest](https://github.com/google/googletest) straight from the Bazel Central Registry **without any patches**.

```python
bazel_dep(name = "stage0-bazel", version = "0.1.0")
bazel_dep(name = "abseil-cpp", version = "20260107.1")
bazel_dep(name = "googletest", version = "1.17.0.bcr.2")


register_toolchains(
    "@stage0-bazel//toolchain:clang",
    "@stage0-bazel//toolchain:cc",
)
```

We then can build and run their testsuite to provide a sanity check that the toolchain is working correctly.

```console
$ bazel test --target_pattern_file=absl-tests.txt
Executed 236 out of 236 tests: 236 tests pass
```

We use a `--target_pattern_file` to filter tests that require `google_benchmark`. Abseil marks `google_benchmark` as a `dev_dependency`, and Bzlmod drops dev dependencies of non-root modules.
{:.aside}

That is us building Abseil and GoogleTest, from the registry, unpatched, compiled by a toolchain that began as 357 bytes of hex.


```graphviz
digraph bootstrap {
  rankdir=TB;
  fontname="Helvetica";
  node [fontname="Helvetica", fontsize=11, shape=rect,
        style="filled,rounded", color="#4C78A8", fillcolor="#DCE6F1"];
  edge [fontname="Helvetica", fontsize=9, color="#666666", arrowsize=0.7];
  nodesep=0.3; ranksep=0.4; pad=0.3;

  seed [label=<<b>hex0</b> &nbsp;<font point-size="9">357 bytes</font>>,
        fillcolor="#F6D5D5", color="#D62728", penwidth=2];

  stage0 [label=<hex1 → hex2 → M0 → cc_x86<br/><font point-size="9">M2-Planet, kaem, M1</font>>];
  mes    [label=<<b>GNU Mes</b> &nbsp;<font point-size="9">mescc</font>>];
  tccmes [label="tcc-mes"];
  tcc    [label=<<b>tinycc</b> &nbsp;<font point-size="9">self-hosted</font>>];
  musl   [label="musl"];
  bin    [label="binutils"];
  gcc46  [label="GCC 4.6.4"];
  gcc10  [label=<<b>GCC 10.4.0</b> &nbsp;<font point-size="9">C++17</font>>, penwidth=2];

  extras [label=<tar, findutils<br/><font point-size="9">Linux UAPI headers</font>>,
          fillcolor="#EFEFEF", color="#999999"];

  llvm [label=<<b>clang 22.1.8</b> &nbsp;+&nbsp; <b>lld 22.1.8</b>>,
        fillcolor="#CFE3D4", color="#2CA02C", penwidth=2];

  absl [label=<<b>Abseil + GoogleTest</b><br/><font point-size="9">236 tests pass</font>>,
        shape=note, fillcolor="#FFF6D5", color="#BF9000"];

  seed -> stage0 -> mes -> tccmes -> tcc -> musl -> bin -> gcc46 -> gcc10;
  gcc10 -> extras [style=dashed];
  extras -> llvm [style=dashed];
  gcc10 -> llvm;
  llvm -> absl [color="#BF9000"];

  { rank=same; gcc10; extras; }
}
```
{: style="--graphviz-height: 40rem"}

How can I be so sure this is a hermetic toolchain?

The toolchain includes an _audit report_ that uses Bazel's [aspects](https://bazel.build/extending/aspects) to inspect every action in the build graph and verify that it only executes programs built by the toolchain itself. The report is generated by running `bazel build //:trust-report` and will fail if any action executes a program outside of the Bazel output tree.[^1]

[^1]: We also set `BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1` to disable Bazel's built-in C++ host toolchain detection.

The report is two lines long:

```
Bootstrap trust report

Every action in the checked graph runs a program built by this
repository, except for these audited seed binaries:

external/+_repo_rules+hex0-seeds/POSIX/x86/hex0-seed
/nix/store/…-bash-interactive-5.3p3/bin/bash
```

Unfortunately, since `genrule` runs a shell it takes as an absolute system path that is also listed as a seed binary. `sh_toolchain`'s `path` attribute is a string, and the shell is not a declared input of the action, so no artifact this repository built can provide it.

Building toolchains from bootstrap seeds was never a priority for companies like Google where they control the entire build environment.
However we seemed to have adopted the same approach as Bazel and similar build systems have become more popular in the open-source community. We should strive to make our builds more reproducible and hermetic, and this is a step in that direction.