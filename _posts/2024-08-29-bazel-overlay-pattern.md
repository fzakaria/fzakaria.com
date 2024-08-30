---
layout: post
title: Bazel Overlay Pattern
date: 2024-08-29 20:06 -0700
excerpt_separator: <!--more-->
---

Do you have an internal fork of a codebase you've added Bazel `BUILD` files to?

Do you want to open-source the BUILD files (+ additional files) but doing so into the upstream project might be a bit too onerous to start? 🤔

Continuing with my dive 🤿 into [Bazel](https://bazel.build/) for `$DAYJOB$`, I wanted to touch on a pattern I've only ever seen employed by Google for [LLVM](https://github.com/llvm/llvm-project) but I'm finding very powerful: _Bazel Overlay Pattern_.

<!--more-->

> I have first encountered this pattern employed by Google in their [llvm-bazel](https://github.com/google/llvm-bazel) repository.

With the _Bazel Overlay Pattern_, you can open-source the Bazel build system for a **separate** project & repository.

This is useful if the upstream project does not want to accept the `BUILD` files themselves or if you want to validate it working in the open first before proposing the change itself.

🤨 Wait... I thought Bazel has the _"Bazel Registry"_ which already has a bunch of external projects building with Bazel.

_Sort of_. The `BUILD` files introduced into the registry either wrap the existing build-system using something [rules_foreign_cc](https://github.com/bazelbuild/rules_foreign_cc) or bring in the minimal Bazel BUILD files needed to build the final target. The BUILD files offered in the registry are not suited for daily development for that project, they are missing granular build targets, test targets & other developer producitivity targets (i.e. lint, format etc..).

🤌🏼 We want to upstream BUILD files that are meant to be the "real" build system for the project.

## Bazel Overlay Pattern

> I have created the project [bazel-overlay-example](https://github.com/fzakaria/bazel-overlay-example) that you can checkout on GitHub for reference.

Let's run throgh a very minimal example to understand how this work.
We have a C project, "hello_world", with a single file.

```
hello_world/
└── cmd
    └── hello.c
```

In a separate project, "hello_world-overlay", we create a directory with a directory structure **matching** that of the target project.
In this repository within a folder called _bazel-overlay_, include all the files we **only** need to build our project using Bazel.

```
hello_world-overlay/
├── bazel-overlay
│   └── cmd
│       └── BUILD.bazel
├── BUILD.bazel
├── configure.bzl
├── overlay_directories.py
├── third_party
│   └── hello-world-> /tmp/hello-world
└── WORKSPACE
```

Additionally, create a reference to the original project in a directory _third_party_. This can likely a git-submodule but it can even be a symlink or http_archive in the `WORKSPACE.bazel` file.

The 💡 awesome idea for the _overlay pattern_ leverages Bazel's [repository rules](https://bazel.build/extending/repo).

We've added two extra files: [configure.bzl](https://github.com/fzakaria/bazel-overlay-example/blob/main/configure.bzl) and [overlay_directories.py](https://github.com/fzakaria/bazel-overlay-example/blob/main/overlay_directories.py).

> These two files were simplified copies, nearly verbatim, from Google's [llvm-bazel](https://github.com/google/llvm-bazel) repository.

These two files do the "magic" 🪄.

> Feel free to read the files to see how they work. They are a bit too long to include verbatim on this post. They simply iterate over the files and setup symlinks.

We set it up in our `WORKSPACE` like so:

```python
load(":configure.bzl", "overlay_configure")

overlay_configure(
    name = "hello-world",
    overlay_path = "bazel-overlay",
    src_path = "./third_party/hello-world",
)
```

When you try to build the external repository `@hello-world//`, the repository rule will symlink all the files in the _overlay_path_ & the _src_path_ together.

```bash
$ tree $(bazel info output_base)/external/hello-world

/home/fmzakari/.cache/bazel/_bazel_fmzakari/738ca8ce4d
1d8ce828e952fe7b9fdd95/external/hello-world
├── cmd
│   ├── BUILD.bazel -> /tmp/hello-world-overlay/ba
zel-overlay/cmd/BUILD.bazel
│   └── hello.c -> /tmp/hello-world-overlay/third_party/hello-world/cmd/hello.c
└── WORKSPACE
```

It's as if the two repositories were merged! 😎

This is a surprising powerful pattern that lets you explore adding the Bazel build system for a separate repository. The benefit to doing in a separate repository vs. a branch is that it's easy to track `HEAD`. If your `third_party` is a git-submodule, you can keep moving the submodule forward and validating the build succeeds.

I'm moving forward with this pattern to explore upstreaming `$DAYJOB$` Bazel build system to the open source repository. 🙌

❗ I recently contributed [PR#22349](https://github.com/bazelbuild/bazel/pull/22349) to Bazel which does add an _overlay_ concept to `http_archive` which almost looks like it could do this as well **but** if you had a lot BUILD files it would be tedious to manually list them out.

```python
http_archive(
  name="hello_world",
  strip_prefix="hello_world-0.1.2",
  urls=["https://fake.com/hello_world.zip"],
  remote_file_urls={
    "WORKSPACE": ["https://fake.com/WORKSPACE"],
    "cmd/BUILD.bazel": ["https://fake.com/cmd/BUILD.bazel"],
  },
)
```

For now, I'm sticking with the _Bazel Overlay Pattern_.