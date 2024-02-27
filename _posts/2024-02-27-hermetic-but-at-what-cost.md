---
layout: post
title: Hermetic, but at what cost?
date: 2024-02-27 22:02 +0000
excerpt_separator: <!--more-->
---

> **tl;dr;** This is a little story about how making Bazel _hermetic_ can lead to some unexpected consequences. In this particular case, it caused our GitHub action to slow down by 50x from 1 minute to over 60 minutes.
>
> The fix recommended was to apply the following to your `.bazelrc` -- I **needed** to understand why however.
> ```
> # Disabling runfiles links drastically increases performance in slow disk IO situations
> # Do not build runfile trees by default. If an execution strategy relies on runfile
> # symlink tree, the tree is created on-demand. See: https://github.com/bazelbuild/bazel/> > issues/6627
> # and https://github.com/bazelbuild/bazel/commit/03246077f948f2790a83520e7dccc2625650e6df
> build --nobuild_runfile_links
> test --nobuild_runfile_links
>
> # https://bazel.build/reference/command-line-reference#flag--legacy_external_runfiles
> build --nolegacy_external_runfiles
> test --nolegacy_external_runfiles
> ```

<!--more-->

[Bazel](https://bazel.build/) is a popular build system for those seeking to adopt Google-style build methodologies & kool-aid with the hopes of achieving hermetic nirvana.
Very quickly after adopting Bazel, you realize that although you've defined your build targets, ultimately the default toolchains provided by Bazel use the system provided binaries, libraries and headers.

> 📝 [NixOS](https://nixos.org/) is a great way to bring in a reproducible environment for Bazel to use.

Recently, I decided to "fix" our non-hermetic Python Bazel builds by adding a new reliance on [@python_rules](https://github.com/bazelbuild/rules_python) which helps pull in a Python toolchain for Bazel to use.

> 📝 Toolchains in Bazel are often downloaded as pre-compiled binary blobs, so their reproducibility is still limited to and can vary according to the underlying system being run.

Python is a toolchain but also a runtime file ["runfile"](https://bazel.build/extending/rules#runfiles), as the language is interpreted. The result of including _@python_rules_ was that every Python test target (_py_test_) included a runfile tree for a complete Python installation.


Here is a sample of the symlinks for the Python installation that are created.
```console
❯ ls -l bazel-out/k8-fastbuild/mytest.test.runfiles/rules_python\~0.30.0\~python\~python_3_10_x86_64-unknown-linux-gnu/bin
2to3 -> /home/fmzakari/.cache/bazel/_bazel_fmzakari/17bce12c4b47a4a2fc75249afee05177/external/rules_python~0.30.0~python~python_3_10_x86_64-unknown-linux-gnu/bin/2to3
2to3-3.10 -> /home/fmzakari/.cache/bazel/_bazel_fmzakari/17bce12c4b47a4a2fc75249afee05177/external/rules_python~0.30.0~python~python_3_10_x86_64-unknown-linux-gnu/bin/2to3-3.10
idle3 -> /home/fmzakari/.cache/bazel/_bazel_fmzakari/17bce12c4b47a4a2fc75249afee05177/external/rules_python~0.30.0~python~python_3_10_x86_64-unknown-linux-gnu/bin/idle3
```

How many files (inodes) are created for each test?

```console
❯ find bazel-out/k8-fastbuild/bin/stablehlo/tests/transform_chlo.mlir.test.runfiles/rules_python\~0.30.0\~python\~python_3_10_x86_64-unknown-linux-gnu  | wc  -l
2458
```

🤯 **2458** 🤯

Let that sink in. Bazel will create **2458** inodes (symlinks) for each test target. It will do this by default for builds even if the tests are never run or executed.

To double down on this pain, Bazel supports two runfile trees for external repositories which is outlined in their [wiki](https://github.com/bazelbuild/bazel/wiki/Updating-the-runfiles-tree-structure).

🤯 So the whole tree exists at least twice for each test target. 🤯

This increase in symlinks caused our GitHub cache action to suddenly jump from 1 minute to over 60 minutes. This was a 50x increase in time to run the action. The _tar_ and _untar_ of the `.cache` directory had to process so many additional files that it was an IO bottleneck.

The recommended approach (from Bazel Slack and other web links) is to have the following in your `.bazelrc`

```
# Disabling runfiles links drastically increases performance in slow disk IO situations
# Do not build runfile trees by default. If an execution strategy relies on runfile
# symlink tree, the tree is created on-demand. See: https://github.com/bazelbuild/bazel/issues/6627
# and https://github.com/bazelbuild/bazel/commit/03246077f948f2790a83520e7dccc2625650e6df
build --nobuild_runfile_links
test --nobuild_runfile_links

# https://bazel.build/reference/command-line-reference#flag--legacy_external_runfiles
build --nolegacy_external_runfiles
test --nolegacy_external_runfiles
```

**--nobuild_runfile_links**
:  This causes runfiles to not be created during builds. Tests still work, because they have a feature to build the runfiles on demand if needed. The downside to this option, is you can't run the test unless you do `bazel test` or `bazel run` which sets up the runfile tree.

**--nolegacy_external_runfiles**
:  Stops creating the symlinks in 2x places by no longer supported the legacy location for runfiles.

Bazel can provide some amazing guarantees but navigating the myriad of knobs can be frustrating.

Having had experience with NixOS -- I'm curious why Bazel doesn't support template support for the shebang to point to a single location for the Python interpreter.

Anyways, if you want to make your GitHub actions faster, consider adding the above to your `.bazelrc` file.