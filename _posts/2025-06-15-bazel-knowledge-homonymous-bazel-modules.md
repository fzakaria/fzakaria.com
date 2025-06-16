---
layout: post
title: 'Bazel Knowledge: Homonymous Bazel Modules'
date: 2025-06-15 14:25 -0700
---

I was watching the [Aspect](https://www.aspect.build/) YouTube podcast on [Developer tooling in Monorepos with bazel_env](https://youtu.be/TDyUvaXaZrc?si=xW7MvpeZSyjF-jCX) with Fabian Meumertzheim ([@fmeum](https://github.com/fmeum)), and as a _complete aside_ they mentioned:

_"Why did you name the [bazel_env.bzl](https://github.com/buildbuddy-io/bazel_env.bzl) repository to end in **.bzl** ?"_ 🤔

> Besides the fact that ending the repositories in **.bzl** looks cool 😎.

I had not heard of this pattern before and decided to document it, and I've been referring to them as _Homonymous Bazel modules_.


> **Homonymous** (_adjective_): having the same name as another.

Let's consider a simple example. Very soon after having used Bazel, you become familiar with the rule that _you are allowed to omit the target name_ if it matches the _last component of the package path_ [[ref](https://bazel.build/concepts/labels)].

These two labels are equivalent in Bazel:
```
//my/app/lib

//my/app/lib:lib
```

Turns out this rule also applies to the _repository name_ at the start of the label.

If your repository name and target name match, you can omit the target in both `bazel run` and `load()`.  😲

Let's explore with a simple example, our `@hello_world` module. It includes only a single `cc_binary` that prints `"Hello, World!"`.

```python
module(
    name = "hello_world",
    version = "0.0.0",
    bazel_compatibility = [">=7.0.2"],
)
```

```python
cc_binary(
    name = "hello_world",
    srcs = ["hello_world.cc"],
)
```

Since the target is the same as the repository, I can freely omit the target from the `bazel run` command in any Bazel codebase that depends on this module.

```bash
> bazel run @hello_world
INFO: Analyzed target @@hello_world~//:hello_world
INFO: Found 1 target...
Target @@hello_world~//:hello_world up-to-date:
  bazel-bin/external/hello_world~/hello_world
INFO: Elapsed time: 0.300s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/external/hello_world~/hello_world
Hello, World!
```
Nice! This is a great pattern for any Bazel module that might provide a tool in addition to rules. 🙌

Ever used a Bazel module and couldn't quite remember the `load` path for the rule to use? 🥴

Was it `load(@other_module//some/lib:defs.bzl, fake_rule)` or was it `load(@other_module//lib/fake_rule.bzl, fake_rule)`...

If your rule is simple enough, simply label the file the same name as the repository!

This lets consumers do `load("@your_module.bzl", "your_rule")` instead of having to guess or look up a full label like `@your_module//some/path:file.bzl`.

Let's change our example slightly now to end in **.bzl**.

```python
module(
    name = "hello_world.bzl",
    version = "0.0.0",
    bazel_compatibility = [">=7.0.2"],
)
```

We write a `hello_world.bzl` as it's the same name as the repository.

```python
def _hello_world_impl(ctx):
  output_file = ctx.actions.declare_file(
    "{}.txt".format(ctx.label.name)
  )
  ctx.actions.write(
    output = output_file,
    content = "Hello World",
  )
  return [
    DefaultInfo(files = depset([output_file]))
  ]

hello_world = rule(
  implementation = _hello_world_impl,
)
```

We now can easily load our rule without having to remember the import path.

```python
load("@hello_world.bzl", "hello_world")

hello_world(
    name = "hello_world",
)
```

This pattern works great for small utility modules and makes your Bazel usage more ergonomic — less boilerplate, fewer mistakes.