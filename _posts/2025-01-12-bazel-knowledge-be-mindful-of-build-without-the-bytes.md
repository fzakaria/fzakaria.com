---
layout: post
title: 'Bazel Knowledge: Be mindful of Build Without the Bytes (bwob)'
date: 2025-01-12 13:14 -0800
excerpt_separator: <!--more-->
---

[Bazel](https://bazel.build/) is a pretty amazing tool but it's definitely full of it's warts, sharp edges and arcane knowledge.

The appeal to most who adopt Bazel is the ability to memoize much of the build graph if nothing has changed. Furthermore, while leveraging remote caches, build results can be shared across machines making memoization even more effective.

This was a pretty compelling reason to adopt Bazel but pretty soon many noticed, especially on their CI systems, lots of unecessary data transfers for larger codebases.

😲 If the network is poor, the benefits of remote caching (memoization) can be outweighed by the cost to download the artifacts.

<!--more-->

Let's take a really simple example of transfering *1GiB* of data.

| Network (Mbps) | Transfer (seconds) | Transfer (minutes) |
|-----------------------|-------------------------|--------------------------|
| 10                   | 858.99                 | 14.32                   |
| 50                   | 171.80                 | 2.86                    |
| 100                  | 85.90                  | 1.43                    |
| 1000                 | 8.59                   | 0.14                    |
| 10000                | 0.86                   | 0.01                    |

Bazel typically will download every output file of every action executed (or cached) to the host machine. The total size of all output files in a build can be extremely large especially if you are building OCI images.

Large repos may create more than 1GiB of total output files, and it's easy to see that on a limited network it may be more cost-effective to rebuild them locally.

Most developers however, only care about a subset of the output files and even more likely the top-level binary they want to run. On CI systems, the output files are of no interest at all.

As of Bazel 7, the feature [build without the bytes](https://blog.bazel.build/2023/10/06/bwob-in-bazel-7.html) (bwob) was enabled by default to solve this very problem.

The feature allows you to download only a subset of the output files, thus reducing the amount of data transferred between Bazel and the remote cache. You can enable BwoB by setting either `--remote_download_minimal` or `--remote_download_toplevel`.

Now for the suprising part, when _bwob_ is enabled, Bazel can have suprising outcomes when you expect files to be present but are no longer. 🕵️

> This is something we stumble a few times at `$DAYJOB$` alongside my colleague [Vince Rose](https://www.linkedin.com/in/vincerose/).

Let's build a really simple executable `genrule`

```python
genrule(
    name = "write_file",
    outs = ["a.txt"],
    cmd = "echo 'hello, world!' > $@",
)

genrule(
    name = "echo",
    srcs = [
        ":a.txt",
    ],
    outs = ["echo.sh"],
    cmd = """
cat > $@ << 'EOF'
#!/usr/bin/env bash
set -e
cat $(location :a.txt)
EOF
    """,
    executable = True,
)
```

We will enable a local _disk_cache_ in our `.bazelrc` and _bwob_ toplevel.

```
common --disk_cache=~/.cache/bazel-disk-cache
common --remote_download_outputs=toplevel
```

Let's run our command!

```shell
$ bazel run //:echo
INFO: Invocation ID: e5b66438-9b71-4fc3-97a7-5446ecf7759d
INFO: Analyzed target //:echo (0 packages loaded, 3 targets configured).
INFO: Found 1 target...
Target //:echo up-to-date:
  bazel-bin/echo.sh
INFO: Elapsed time: 0.051s, Critical Path: 0.00s
INFO: 2 processes: 1 disk cache hit, 1 internal.
INFO: Build completed successfully, 2 total actions
INFO: Running command line: bazel-bin/echo.sh
hello, world!
```

Great that works! Let's now `bazel clean` and re-run the target.

```shell
$ bazel clean
INFO: Invocation ID: 84292a54-30d4-42f6-aa83-0978a3355383
INFO: Starting clean (this may take a while). Consider using --async if the clean takes more than several minutes.

$ bazel run //:echo
INFO: Invocation ID: 85680e76-b9c8-456b-81ca-03835023191b
INFO: Analyzed target //:echo (6 packages loaded, 11 targets configured).
INFO: Found 1 target...
Target //:echo up-to-date:
  bazel-bin/echo.sh
INFO: Elapsed time: 0.185s, Critical Path: 0.00s
INFO: 3 processes: 2 disk cache hit, 1 internal.
INFO: Build completed successfully, 3 total actions
INFO: Running command line: bazel-bin/echo.sh
cat: bazel-out/k8-fastbuild/bin/a.txt: No such file or directory
```

Looks like our `genrule` can no longer find _a.txt_ 🤦‍♂️

Thankfully the fix is relatively simple, you can either [--remote_download_outputs=all](https://bazel.build/reference/command-line-reference#flag--remote_download_outputs) as a quick solution or be more selective with [--remote_download_regex](https://bazel.build/reference/command-line-reference#flag--remote_download_regex)

```shell
$ bazel run //:echo --remote_download_regex='.*/a\.txt'
INFO: Invocation ID: 01911793-d17a-435d-9503-a551f56a4cc3
INFO: Analyzed target //:echo (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //:echo up-to-date:
  bazel-bin/echo.sh
INFO: Elapsed time: 0.040s, Critical Path: 0.00s
INFO: 2 processes: 1 disk cache hit, 1 internal.
INFO: Build completed successfully, 2 total actions
INFO: Running command line: bazel-bin/echo.sh
hello, world!
```

Looks like the issue has been raised a few times on GitHub issues (i.e, [#11920](https://github.com/bazelbuild/bazel/issues/11920)) or on the Bazel slack but it's unclear if it's _working as intended_ or a _bug_ 🐛.

> **Update (28-05-2025)**:  
> It turns out that using `executable = True` in a `genrule` is discouraged and should be removed.
> This is because `genrule` targets don't provide runfiles, which makes them unsuitable for being directly executed via `bazel run`.  
> 
> Instead, the recommended approach — as explained by [@fmeum](https://github.com/fmeum) in [this comment](https://github.com/bazelbuild/bazel/issues/11920#issuecomment-2585915779) — is to take the output of the `genrule` (such as a shell script created by `echo`) and wrap it in an `sh_binary` rule. This `sh_binary` can then serve as the actual executable target.

This outcome though can be very confusing for yourself or engineers whom are using Bazel.

My understanding is that this may be a current _bug_ specifically of `genrule` at the moment.

Consider this alternative:

```cpp
#include <stdio.h>

int main(int argc, char* argv[]) {
    FILE* file = fopen("a.txt", "r");
    if (file == NULL) {
        perror("Error opening file");
        return 1;
    }

    char ch;
    while ((ch = fgetc(file)) != EOF) {
        putchar(ch);
    }

    fclose(file);
    return 0;
}
```

```python
cc_binary(
    name = "hello_world",
    srcs = ["hello_world.cc"],
    data = [
        ":a.txt",
    ],
)

genrule(
    name = "write_file",
    outs = ["a.txt"],
    cmd = "echo 'hello, world!' > $@",
)
```

In this case, the output of the `genrule` _a.txt_ is present as a _runfile_ and correctly present during a `bazel run` invocation.

```shell
$ bazel clean --expunge

$ bazel run //:hello_world --remote_download_minimal
Starting local Bazel server and connecting to it...
INFO: Invocation ID: ff279c3c-ed12-4395-9d15-12611ca927b5
INFO: Analyzed target //:hello_world (87 packages loaded, 454 targets configured).
INFO: Found 1 target...
Target //:hello_world up-to-date:
  bazel-bin/hello_world
INFO: Elapsed time: 2.646s, Critical Path: 0.03s
INFO: 8 processes: 3 disk cache hit, 5 internal.
INFO: Build completed successfully, 8 total actions
INFO: Running command line: bazel-bin/hello_world
hello, world!
```

```shell
ls bazel-bin/hello_world.runfiles/_main/
a.txt  hello_world
```

I have included this additional information on an issue to Bazel; let's see what comes of it. 🤷
