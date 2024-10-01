---
layout: post
title: 'Bazel Knowledge: reproducible outputs'
date: 2024-09-26 11:50 -0700
excerpt_separator: <!--more-->
---

You might hear a lot of about how Bazel is _"reproducible"_ and _"hermetic"_, but what does that even mean ? 😕

Part of what makes Bazel incredibly fast is it effectively **skips work** by foregoing doing portions of the graph if the inputs have not changed.

Let's consider this simple action graph in Bazel.

![Bazel Action Graph](/assets/images/action_graph_bazel.png)

<!--more-->

Bazel constructs an [action key](https://bazel.build/reference/glossary#action-cache) for each action which we can simplify down to constituting: the Starlark of the action itself & the SHA256 of the outputs of all the dependencies (i.e. srcs or deps).

Let's consider a change to _File D_, which would mean that the action key for _Action C_ now differs.

At this point Bazel will decide to rerun _Action C_ and will produce an output _SHA256-C_.

If the _SHA256-C_ is the exact same as before, Bazel **will forgoe** executing _Action A_ again. 🤯

> How often does this happen in practice? 🤔 A ton! Consider changes to comments that don't effect the output. Bazel also considers the output hash on the target's ABI, so in the case of C++ that might constitute the header files and in Java they strip out all private methods to create an "interface jar" ([ijar](https://github.com/bazelbuild/bazel/blob/master/third_party/ijar/README.txt)).

Watch out though, if you use [genrule](https://bazel.build/reference/be/general#genrule) you can find yourself easily producing outputs that are not reproducible if nothing changes which will kill this pruning of the action graph.

Let's look at an example.

```python
genrule(
    name = "output_zip",
    outs = ["output.zip"],
    cmd = """
    echo 'Hello, World!' > hello.txt && \\
    zip output.zip hello.txt && mv output.zip $@
    """,
)

genrule(
    name = "hello_text",
    srcs = [":output_jar"],
    outs = ["hello.txt"],
    cmd = """
    unzip $(location :output_jar) hello.txt -d $(GENDIR) \\
    && mv $(GENDIR)/hello.txt $@
    """,
)
```

This is a very simple setup where I'm producing a ZIP file and in in the final target unzipping it.

ZIP files unfortunately are normally non-reproducible because they include modification timestamp information embedded in them & the order the files are included are non-ordered.

Let's build this with Bazel. We will use the [execlog](https://github.com/bazelbuild/bazel/blob/master/src/tools/execlog/README.md) to view all the actions that were processed.

> The _execlog_ is an output file that is generated of all the actions Bazel undertook. 
We simply select the _targetLabel_ to view the actions executed.

```console
> bazel --ignore_all_rc_files build //:hello_text \
    --execution_log_json_file=/tmp/exec.log.json

> cat /tmp/exec.log.json | jq .targetLabel
"//:output_zip"
"//:hello_text"
```

Now let's **delete** the _output.zip_ file by doing `rm bazel-bin/output.zip` and
re-run Bazel.

```console
> bazel --ignore_all_rc_files build //:hello_text \
    --execution_log_json_file=/tmp/exec.log.json

> cat /tmp/exec.log.json | jq .targetLabel
"//:output_zip"
"//:hello_text"
```

Both targets are still being run! 😢

Fortunately, there are a few alternatives we can use such as [rules_pkg](https://github.com/bazelbuild/rules_pkg) or [@bazel_tools//tools/zip:zipper](https://github.com/bazelbuild/bazel/blob/master/tools/zip/BUILD) that has support for creating ZIP archive format in _a reproducible way_.

Let's modify our code now to use `@bazel_tools//tools/zip:zipper`.

```python
genrule(
    name = "output_zip",
    outs = ["output.zip"],
    cmd = """
    echo 'Hello, World!' > hello.txt && \\
    $(location @bazel_tools//tools/zip:zipper) c $@ hello.txt
    """,
    tools = ["@bazel_tools//tools/zip:zipper"],
)

genrule(
    name = "hello_text",
    srcs = [":output_zip"],
    outs = ["hello.txt"],
    cmd = """
    unzip $(location :output_zip) hello.txt -d $(GENDIR) \\
    && mv $(GENDIR)/hello.txt $@
    """,
)
```

We've effectively done the same thing as before, but we are being more mindful about
creating our output to be reproducible if the inputs are the same.

```console
> rm bazel-bin/output.zip
override r-xr-xr-x fzakaria/wheel for bazel-bin/output.zip? y

> bazel --ignore_all_rc_files build //:hello_text \
    --execution_log_json_file=/tmp/exec.log.json

> cat /tmp/exec.log.json | jq .targetLabel
"//:output_zip"
```

🙌  YES! As expected we now only re-run the _output_zip_ action and the final action
can be skipped.

We now have our graph reproducible in a way that can help Bazel give us incremental rebuilds by skipping portions of the graph. 🥳

If reproducible builds interest you, I _highly_ recommend you check out the wealth of information on the subject by the [Reproducible Builds Group](https://reproducible-builds.org/docs/). They've documented all the various intricate ways they discovered software builds introduce nondeterminism into the build.