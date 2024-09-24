---
layout: post
title: 'Bazel Knowledge: Reference targets by output name'
date: 2024-09-23 08:41 -0700
excerpt_separator: <!--more-->
---

In an attempt to try and record some of the smaller knowledge brain gains on using Bazel, I'm hoping to write a few smaller article. 🤓

Did you know you can reference an output file directly by name or the target name that produced it?

```python
load("@bazel_skylib//rules:diff_test.bzl", "diff_test")

genrule(
    name = "src_file",
    outs = ["file.txt"],
    cmd = "echo 'Hello, Bazel!' > $@",
)

diff_test(
    name = "test_equality",
    file1 = ":src_file",
    file2 = ":file.txt",
)
```

⚠️ If the output is the same name as the rule Bazel will give you a **warning** but everything still seems to work.

I tend to prefer matching by rule name. I'm not yet aware of any reason to
prefer one over the other.