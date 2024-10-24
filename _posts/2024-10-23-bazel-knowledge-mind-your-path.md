---
layout: post
title: 'Bazel Knowledge: mind your PATH'
date: 2024-10-23 15:37 -0700
excerpt_separator: <!--more-->
---

Have you encountered the following?

```bash
> bazel build
INFO: Invocation ID: f16c3f83-0150-494e-bd34-1a9cfb6a2e67
WARNING: Build option --incompatible_strict_action_env has changed, discarding analysis cache (this can be expensive, see https://bazel.build/advanced/performance/iteration-speed).
INFO: Analyzed target @@com_google_protobuf//:protoc (113 packages loaded, 1377 targets configured).
[483 / 845] 13 actions, 12 running
    Compiling src/google/protobuf/compiler/importer.cc; 3s disk-cache, darwin-sandbox
    Compiling src/google/protobuf/compiler/java/names.cc; 1s disk-cache, darwin-sandbox
    Compiling src/google/protobuf/compiler/java/name_resolver.cc; 1s disk-cache, darwin-sandbox
    Compiling src/google/protobuf/compiler/java/helpers.cc; 1s disk-cache, darwin-sandbox
    Compiling src/google/protobuf/compiler/objectivec/enum.cc; 1s disk-cache, darwin-sandbox
    Compiling absl/strings/cord.cc; 1s disk-cache, darwin-sandbox
    Compiling src/google/protobuf/compiler/objectivec/names.cc; 0s disk-cache, darwin-sandbox
    Compiling absl/time/internal/cctz/src/time_zone_lookup.cc; 0s disk-cache, darwin-sandbox ...
```

I finally had it with Bazel **recompiling protoc** 😤

The working title for this post: _Why the #$@! does protoc keep recompiling!_ 🤬

> If you are not interested in the story and just want to avoid recompiling _protoc_, try putting `build --incompatible_strict_action_env` in your _.bazelrc_.
>
> Checkout Aspect's [bazelrc guide](https://docs.aspect.build/guides/bazelrc/) for other good tidbits.

<!--more-->

Admittedly, I've been using Bazel a while and I wasn't sure why I kept having to rebuild _protoc_ despite nothing seemingly changing on my system.

Worse, my coworkers who I've been working hard to champion Bazel were starting to notice.

_"You explained that Bazel is supposed to be hermetic and have great caching. Why am I recompiling protoc?"_

This seems to be a bit of an issue within the Bazel community so much so, that one recommended approach is just _use precompiled binaries_ via [aspect-build/toolchains_protoc](https://github.com/aspect-build/toolchains_protoc). 🤦

> _Aside_: Using prebuilt binaries not only hinders my own personal adoption of Bazel on [NixOS](https://nixos.org) but devalues the value proposition of Bazel itself.

Turns out there is a long-standing **5 year old** issue [issues#7095](https://github.com/bazelbuild/bazel/issues/7095) that provided some clues; specifically changing `PATH` is busting the action key.

I want to validate this assumption, by following the guide on [how to debug remote cache hits](https://bazel.build/remote/cache-remote).

I ran Bazel twice, once with a different `PATH` and stored the compact execution log.
I then convert it to textual form and diff them.

```bash
# build protoc normally
> bazel build @com_google_protobuf//:protoc --execution_log_compact_file=/tmp/exec1.log

# muck up the PATH
> PATH=$PATH:/bin4/ bazel build @com_google_protobuf//:protoc --execution_log_compact_file=/tmp/exec2.log

> bazel-bin/src/tools/execlog/parser \
  --log_path=/tmp/exec1.log \
  --log_path=/tmp/exec2.log \
  --output_path=/tmp/exec1.log.txt \
  --output_path=/tmp/exec2.log.txt

> diff /tmp/exec1.log.txt /tmp/exec2.log.txt | head -n 30
# omitted for brevity
```

Sure enough; there is an `action_env` with the `PATH` variable and it's different, causing the action digest to change.

But, why! 🤔

Some of the actions used in the C++ toolchain use the shell's default environment.
For instance, Bazel doesn't include a C++ toolchain by default so it has to find a C++ compiler by searching
on the `PATH` itself.

We can test this (thanks to [keith](https://github.com/keith) for this) with a small demo.
We can see what envs are in actions by default passing `-s`

```python
def _impl(ctx):
    file = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.run_shell(
        outputs = [file],
        command = "touch {}".format(file.path),
    )

    return DefaultInfo(files = depset([file]))

foo = rule(
    implementation = _impl,
)
```

Will produce:

```bash
SUBCOMMAND: # //:bar [action 'Action bar', configuration: 815f76489fb61a0245ff1941974c20af0ca4e7f91caa00c80538d4493d650289, execution platform: @@platforms//host:host, mnemonic: Action]
(cd /home/ubuntu/.cache/bazel/_bazel_ubuntu/1275a810ad76d4d1cc60319d4aaf0d39/execroot/_main && \
  exec env - \
  /bin/bash -c 'touch bazel-out/aarch64-fastbuild/bin/bar')
```

If we change the `run_shell` action to use `use_default_shell_env=True` we then get.

```bash
SUBCOMMAND: # //:bar [action 'Action bar', configuration: 815f76489fb61a0245ff1941974c20af0ca4e7f91caa00c80538d4493d650289, execution platform: @@platforms//host:host, mnemonic: Action]
(cd /home/ubuntu/.cache/bazel/_bazel_ubuntu/1275a810ad76d4d1cc60319d4aaf0d39/execroot/_main && \
  exec env - \
    PATH=<OMITTED FOR BREVITY> \
  /bin/bash -c 'touch bazel-out/aarch64-fastbuild/bin/bar')
```

Okay, so how do we solve this?

There are two ways to solve this.

First, you can try `--incompatible_strict_action_env` in your _.bazerc_ file.
If this flag is set, Bazel will force set `PATH` to be a static value. If your C++ compiler is either a hermetic toolchain or found in the default lists set; you are good to go!

If you tried the first option but your build is failing, you'll have to manually force set the `PATH` via the `action_env` flag such as `--action_env=PATH=/usr/bin:/something/custom`

Hopefully these settings get you from recompiling _protoc_ and reach Bazel nirvana.

I highly recommend [Aspect's bazelrc guide](https://docs.aspect.build/guides/bazelrc/) for other no-nonsense settings that should likely just be the default 🙄 