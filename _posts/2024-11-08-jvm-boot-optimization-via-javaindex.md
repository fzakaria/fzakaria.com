---
layout: post
title: JVM boot optimization via JavaIndex
date: 2024-11-08 14:01 -0800
excerpt_separator: <!--more-->
---

_Ever heard of a JarIndex? I had been doing JVM develpoment for 10+ years and I hadn't. Read on to discover what it is and how it can speedup your compilation and boot time._ 🤓

After having worked on [Shrinkwrap](https://github.com/fzakaria/shrinkwrap) and publishing our results in [Mapping Out the HPC Dependency Chaos](https://arxiv.org/abs/2211.05118), you start
to see the Linux environment as a bit of an oddball.

_Everything in Linux is structured around O(n) or O(n^2) search and lookup_.

This feels now unsuprising given that everything in Linux searches across colon separate lists (i.e. _LD_LIBRARY_PATH_, _RUN_PATH_).
This idiom however is even more pervasive and has bled into all of our language.

The JVM for instance, must search for classes amongst a set of directories, files or JARs set on the _CLASS_PATH_.
<!--more-->

Everytime the JVM needs to load a class file, it must perform a linear search along all entries in the _CLASS_PATH_.
Thanksfully, if the entries are directories or JARs, no subsequent search must be performed since the package name of a class dictates the directory structure
that must exist.

`io.fzakaria.Example` -> `io/fzakaria/Example.class`

Nevertheless, the _CLASS_PATH_ size can be large. 
At _$DAY_JOB$_, almost all of our services launch with +300 entries (JARs) on the ClassPath.

Large enterprise codebases may feature over a thousand ClassPath entries. 😮

A large ClassPath means that the JavaVirtualMachine (JVM) needs to search entry for the desired class.
This not only affects startup time for your application, _on every startup, repeatedly_, but also compilation as well via `javac`.

The authors of the JVM already knew about this problem, especially when the idea of Java Applets were dominant. Each JAR on the ClassPath
would have been fetched via HTTP and would cause unbearable slowdown for startup.

The JDK has support for a _JarIndex_.

A _JarIndex_, is a JAR which has a special file `INDEX.LIST` that effectively contains an index of all JARs on the ClassPath and the packages found within.

```
JarIndex-Version: 1.0

libMain.jar
Main.class

lib/libA.jar
A.class

lib/libB.jar
B.class
```

Whenever a class must be searched rather than searching through the _CLASS_PATH_, the index file is used leading to constant-time lookup for classes.

This seemingly powerful primitive confusingly has been deprecated and ultimately removed in JDK22 ([JDK-8302819](https://bugs.openjdk.org/browse/JDK-8302819)) 🤔 -- citing challenges when having to support a broad ranges of topics such as Multi-Version JARs.

Unsuprisingly, I think this feature would be an easy fit into Bazel, Spack or Nix -- as there are a lot more constraints on the type of JARs that need be supported.

I put together a small [gist](https://gist.github.com/fzakaria/4e98f65be96cf7f8b13081e75d7a2bf8) on what this support might look like.

```python
def _jar_index_impl(ctx):
    java_info = ctx.attr.src[JavaInfo]
    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]
    java_home = java_runtime.java_home
    jar_bin = "%s/bin/jar" % java_home

    runtime_jars = " "
    for jar in java_info.transitive_runtime_jars.to_list():
        runtime_jars += jar.path + " "

    cmds = [
        "%s -i %s %s" % (jar_bin, java_info.java_outputs[0].class_jar.path, runtime_jars),
        "cp %s %s" % (java_info.java_outputs[0].class_jar.path, ctx.outputs.index.path),
    ]

    ctx.actions.run_shell(
        inputs = [ java_info.java_outputs[0].class_jar] + java_info.transitive_runtime_jars.to_list(),
        outputs = [ctx.outputs.index],
        tools = java_runtime.files,
        command = ";\n".join(cmds),
    )

    return [
        DefaultInfo(files = depset([ctx.outputs.index])),
    ]

jar_index = rule(
    implementation = _jar_index_impl,
    attrs = {
        "src": attr.label(
            mandatory = True,
            providers = [JavaInfo],
        ),
        "_java_runtime": attr.label(
            default = "@bazel_tools//tools/jdk:current_java_runtime",
            providers = [java_common.JavaRuntimeInfo],
        ),
    },
    outputs = {"index": "%{name}_index.jar"},
)
```

Further improvements can be made, to give this index-like support to the Java compiler itself and not only for `java_binary` targets.

We've gone out of our way on these systems to define our inputs, enforce contraints and model our dependencies. Not taking advantage of
this stability and regressing to the default search often found in our tooling is leaving easy performance improvements on the floor.