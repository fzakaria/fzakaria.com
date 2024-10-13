---
layout: post
title: 'Bazel Knowledge: Aspects to generate Java CLASSPATH'
date: 2024-10-13 11:10 -0700
excerpt_separator: <!--more-->
---

One of the more advanced features of [Bazel](https://bazel.build) is the concept of [aspect](https://bazel.build/extending/aspects).

For a very brief primer on why you may want an aspect is that Bazel let's you audit and analyze the BUILD graph without performing any actual builds. It does this by constructing a "shadow graph" that your aspect can perform analysis on. This can be useful for a variety things such as IDE integration.

I wanted to ask a very simple question to make integration with Visual Studio Code straightforward:

_"What's the CLASSPATH I need for a particular target so that I don't get red squigglies?"_

<!--more-->

Sometimes simple questions involve some of the more advanced features of Bazel.
I wanted to generate a file that I can feed into any IDE, such as Visual Studio Code, and get semi-decent language integration.

My end goal:
```console
> bazel build //:generate_classpath

> cat bazel-bin/classpath.txt
bazel-out/k8-fastbuild/bin/java/lib/liblib.jar
bazel-out/k8-fastbuild/bin/java/lib2/liblib2.jar
```

First thing we want to do is generate an aspect that will collect recursively all the compile time Jars.

We define our aspect which requires the sole `deps` attribute to be propagated.
We then make sure we recursively merge all the results of the prior aspect invocations into the final
`ClassPathInfo` provider object.

```python
ClassPathInfo = provider(
    "Provider for classpath information",
    fields = {
        'compile_jars' : 'depset of compile jars'
    }
)


def _classpath_aspect_impl(target, ctx):
    # Make sure the rule has a deps attribute.
    if hasattr(ctx.rule.attr, 'deps'):
        target_compile_jars = target[JavaInfo].full_compile_jars
        dep_compile_jars = [
            dep[ClassPathInfo].compile_jars
            for dep in ctx.rule.attr.deps
        ]
        all_compile_jars = [target_compile_jars] + dep_compile_jars
        merged_depset = depset(transitive=all_compile_jars)

        classpath_strings = []
        for jar in merged_depset.to_list():
            classpath_strings.append(jar.path)

        output_file = ctx.actions.declare_file("classpath.txt")
        ctx.actions.write(
            output = output_file,
            content = "\n".join(classpath_strings),
            is_executable = False
        )

        return [ClassPathInfo(
            compile_jars = merged_depset
            ),
            OutputGroupInfo(
                compile_jars = depset([output_file])
            )]
    return [ClassPathInfo(compile_jars = depset())]

classpath_aspect = aspect(
    implementation = _classpath_aspect_impl,
    # attr_aspects is a list of rule attributes along
    # which the aspect propagates.
    attr_aspects = ['deps'],
)
```

A _less documented_ feature of Bazel is the "output groups" which you can see here we are
by specifying `OuputGroupInfo`. The idea here is that we can now specify our apect for any
label by using this command line invocation:

```console
> bazel build //java/app --aspects defs.bzl%classpath_aspect \
        --output_groups=compile_jars

INFO: Analyzed target //java/app:app (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Aspect //:defs.bzl%classpath_aspect of //java/app:app up-to-date:
  bazel-bin/java/app/classpath.txt

>  cat bazel-bin/java/app/classpath.txt
bazel-out/k8-fastbuild/bin/java/lib/liblib.jar
bazel-out/k8-fastbuild/bin/java/lib2/liblib2.jar⏎
```

That's not all though! We can also create a rule that defines the labels provided must be of the type aspect.
This let's us encode the build targets in our `BUILD` files themselves.

The rule itself is straightforward. For each label provided, it goes through the
items in the `compile_jars` depset and creates an output file which is the
concatenated new-line delimited list.

```python
def _generate_classpath_rule_impl(ctx):
    for dep in ctx.attr.deps:
        classpath_strings = []
        for jar in dep[ClassPathInfo].compile_jars.to_list():
            classpath_strings.append(jar.path)
        output_file = ctx.actions.declare_file("classpath.txt")
        ctx.actions.write(
            output = output_file,
            content = "\n".join(classpath_strings),
        )
        return [DefaultInfo(files = depset([output_file]))]
    return [DefaultInfo(files = None)]

generate_classpath_rule = rule(
    implementation = _generate_classpath_rule_impl,
    attrs = {
        'deps' : attr.label_list(aspects = [classpath_aspect]),
    },
)
```

> ❗ There is a bit of duplication in the rule for generating the output file. We could have also
> used the OutputGroupInfo and merged all the files together.

In order to invoke this rule you define it in a `BUILD` file and give it the top-level
applications that you are working on.

```python
generate_classpath_rule(
    name = "generate_classpath",
    deps = [
        "//java/app:app",
    ]
)
```

🎉 We now have **two** pretty simple ways to generate the compile-time CLASSPATH for a label.
This can make integrations with IDEs a bit more straightforward if they don't have a working Bazel plugin.