---
layout: post
title: Bazel WORKSPACE chunking
date: 2024-08-29 10:36 -0700
excerpt_separator: <!--more-->
---

I have been doing quite a lot of [Bazel](https://bazel.build/) for `$DAYJOB$`; and it's definitely got it's _fair share of warts_.

> I have my own misgivings of it's migration to _bzlmod_ and it converging to a standard-issue dependency-management style tool.

We have yet to transition to `MODULE.bazel` and our codebase is quite large. As you'd expect, we hit quite a lot of _diamond dependency_ issues & specifically with external repositories in our `WORKSPACE` file.

A surprising implementation detail I recently learned was how Bazel does dependency resolution for external repositories in WORKSPACE.

<!--more-->

To demonstrate, let's see a quick example. I have two sample workspaces that export a single target `//:version` that will either have 1.0 or 2.0.


```python
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")

http_archive(
    name = "workspace",
    url = "file:///tmp/example-workspace/workspace-1.0.tar.gz",
    strip_prefix = "workspace-1.0",
)

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

http_archive(
    name = "workspace",
    url = "file:///tmp/example-workspace/workspace-2.0.tar.gz",
    strip_prefix = "workspace-2.0",
)
```

What is the version of `@workspace//:version` you expect ? 🤔

```console
$ bazel build @workspace//:version
INFO: Analyzed target @workspace//:version (1 packages loaded, 1 target configured).
INFO: Found 1 target...
Target @workspace//:version up-to-date:
  bazel-bin/external/workspace/VERSION
INFO: Elapsed time: 0.078s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action

$ cat  bazel-bin/external/workspace/VERSION
1.0
```

Huh. 😳. Okay. 

So in this example it looks like it's _first version wins_.

Let's try another slightly different example.

```python
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

http_archive(
    name = "workspace",
    url = "file:///tmp/example-workspace/workspace-1.0.tar.gz",
    strip_prefix = "workspace-1.0",
)

http_archive(
    name = "workspace",
    url = "file:///tmp/example-workspace/workspace-2.0.tar.gz",
    strip_prefix = "workspace-2.0",
)
```

What is the version of `@workspace//:version` you expect now ? 🤔


```console
$ bazel build @workspace//:version
INFO: Analyzed target @workspace//:version (1 packages loaded, 2 targets configured).
INFO: Found 1 target...
Target @workspace//:version up-to-date:
  bazel-bin/external/workspace/VERSION
INFO: Elapsed time: 0.145s, Critical Path: 0.02s
INFO: 2 processes: 1 internal, 1 linux-sandbox.
INFO: Build completed successfully, 2 total actions

$ cat  bazel-bin/external/workspace/VERSION
2.0
```

😳 2.0

So now it looks like it's last one wins? 🤨

Turns out the version selection in Bazel is a little more _complex_.

🕵️ The WORKSPACE file into _chunks_ separated by load statements. For a repo named X (`@workspace//` in our case), the *last* definition of X in the _first_ chunk that contains a definition of X is the winner

If you ever face an issue of having the wrong version of an external repoitory, the thing to do is move it up `load` statements until you find the _chunk_ that is defining it.

I found references to this on some GitHub issues & was helped out by [@Wyverald](https://github.com/Wyverald) on Slack but thought a clear concise example to demonstrate it was interesting.

If you want to play with the example above, I've uploaded it to [bazel-workspace-chunking](https://github.com/fzakaria/bazel-workspace-chunking) on GitHub.

❗ Don't trust `bazel query //external:workspace --outout build` to see the version.

You might be tempted to ru nthe above query but it gives **incorrect** results.

```console
$ bazel build @workspace//:version
INFO: Analyzed target @workspace//:version (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target @workspace//:version up-to-date:
  bazel-bin/external/workspace/VERSION
INFO: Elapsed time: 0.057s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action

$ cat  bazel-bin/external/workspace/VERSION
1.0

$ bazel query //external:workspace --output build
# /tmp/example-workspace/WORKSPACE.bazel:13:13
http_archive(
  name = "workspace",
  url = "file:///tmp/example-workspace/workspace-2.0.tar.gz",
  strip_prefix = "workspace-2.0",
)
# Rule workspace instantiated at (most recent call last):
#   /tmp/example-workspace/WORKSPACE.bazel:13:13 in <toplevel>
# Rule http_archive defined at (most recent call last):
#   /home/fmzakari/.cache/bazel/_bazel_fmzakari/c72d1df8de0701fb5f44d35dec4b70b5/external/bazel_tools/tools/build_defs/repo/http.bzl:372:31 in <toplevel>

Loading: 0 packages loaded
```

Even when the `VERSION` was still **1.0**, the query simply gives back the last version cited in the `WORKSPACE` file.
