---
layout: post
title: 'Bazel Knowledge: What''s an Interface JAR?'
date: 2024-10-29 19:34 -0700
excerpt_separator: <!--more-->
---

I spent the day working through an upgrade of our codebase at _$DAYJOB$_ to Java21 and hit Bazel [issue#24138](https://github.com/bazelbuild/bazel/issues/24138) as a result of an incorrectly produced `hjar`.

🤨
_WTF is an `hjar` ?_

☝️ _It is the newer version of `ijar` !_

😠
_WTF is an `ijar` ?_

Let's discover what an `ijar` (Interface JAR) is and how it's the _magic sauce_ that makes Bazel so fast for Java.

<!--more-->

Let's consider a simple Makefile

```make
program: main.o utils.o
	$(CC) -o program main.o utils.o

main.o: main.c utils.h
	$(CC) -c main.c

utils.o: utils.c utils.h
	$(CC) -c utils.c
```

We've been taught to make use of _header files_, especially in C/C++ so that we can avoid recompilation as a form of _early cutoff optimization_.

☝️ If we change `utils.c` solely, we do not have to recompile `main.o`.

We can visualize this Makefile in the following graph.

![Makefile as a graph](/assets/images/makefile_as_graph.svg)

Ok, great! What does this have to do with Java & Bazel ?

Well, let's remember back to my previous post on [reproducible outputs]({% post_url 2024-09-26-bazel-knowledge-reproducible-outputs %}).

Bazel constructs a similar graph to determine when to do _early cutoff optimization_ through the "Action Key". Bazel computes a hash for each action, that takes dependencies for instance, and if the hash hasn't changed it can memoize the work.

![Bazel Action Graph](/assets/images/action_graph_bazel.png)

In Java-world, dependencies are expressed as JARs.

Wouldn't private-only changes to a dependency (i.e. renaming a private variable) cause the Action Key HASH to change (since it produced a different JAR) ?

🤓 YES! That is why we need an `ijar` !

`ijar` is a tool found within the Bazel repository [bazel/third_party/ijar](https://github.com/bazelbuild/bazel/blob/master/third_party/ijar/README.txt).

You can build and run it fairly simple with Bazel
```bash
$ bazel run //third_party/ijar
Usage: ijar [-v] [--[no]strip_jar] [--target label label] [--injecting_rule_kind kind] x.jar [x_interface.j
ar>]
Creates an interface jar from the specified jar file.
```

It's purpose is straightforward. The tool strips all non-public information from the JAR. For example, it throws away:
  - Files whose name does not end in ".class".
  - All executable method code.
  - All private methods and fields.
  - All constants and attributes except the minimal set necessary to describe the class interface.
  - All debugging information
    (LineNumberTable, SourceFile, LocalVariableTables attributes).

The end result is something in spirit to a C/C++ header file.

Let's see it in practice. 🕵️

Let's now create an incredibly simple JAR. It will have a single class file within it.

```java
public class Banana {
    public void peel() {
        System.out.println("Peeling the banana...");
        squish();
    }
    private void squish() {
        System.out.println("Squish! The banana got squashed.");
    }
}
```

We compile it like usual.
```bash
$ javac Banana.java
$ jar cf banana.jar Banana.class
```

When we run `ijar` on it we get the hash _e18e0ae82bdc4deb04f04aa_

⚠️ I shortened the hashes to make them more legible.

```bash
$ bazel-bin/third_party/ijar/ijar banana.jar

$ sha256sum banana.jar
f813749013ea6aba2e00876  banana.jar

$ sha256sum banana-interface.jar
e18e0ae82bdc4deb04f04aa  banana-interface.jar
```

Let's now change the internals of the _Banana_ class; let's rename the method `squish()` -> `squash()`.

Let's recompute the new sha256.

```bash
$ sha256sum banana.jar
9278282827ddb55c68eb370 banana.jar

$ sha256sum banana-interface.jar
e18e0ae82bdc4deb04f04aa  banana-interface.jar
```

🤯 Although the hash of _banana.jar_ had changed, we still get _e18e0ae82bdc4deb04f04aa_ for the ijar.

We now the equivalent of a header file for Java code.  🙌

This is the amazing lesser known tool that makes Bazel super-powered 🦸 for JVM languages.