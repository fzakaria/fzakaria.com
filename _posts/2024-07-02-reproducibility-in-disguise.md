---
layout: post
title: "Reproducibility in Disguise: Bazel, Dependencies,
and the Versioning Lie"
date: 2024-07-02 16:49 -0700
excerpt_separator: <!--more-->
---

Reproducibility has become a _big_ deal. Whether it's having higher confidence in one's build or trying to better understand your supply chain for provenance, having an accurate view of your build graph is a _must_.

Tools such as [Bazel](https://bazel.build/) have picked up mainstream usage from their advocacy by large companies that use it or via similar derivatives such as Buck. These companies write & proclaim how internally it's solved many of their software development lifecycle problems. They've graciously open-sourced these tools for us to use so that we may also reap similar benefits. _Sounds great right?_

<!--more-->

These companies however have a very distinctive software development practice from most of us: **they vendor all their dependencies**.

Vendoring all third party dependencies has proven too onerous for most. Few developers truly understand the amount of code they pull in via transitive dependencies from their language package managers.

![third party iceberg](/assets/images/iceberg_third_party_50p.jpg)


To help those onboard to Bazel, the tool has introduced incrementally the concept of non-vendored dependencies (remote repositories) and integration with typical language package management tools such as _maven_, _pip_ or _npm_. More recently, they've fully launched the _bazel mod_ system which is a semantic versioning solver for dependencies. These are features that
are not used internally at these companies that promote and have built out the tools themselves.

_Ah, diamond dependency problem, how I've missed you._ 🙃


The introduction and use of Bazel has given many a **false** sense of security in that they have a lot better reproducibility than they did before.

![head in sand meme](/assets/images/head_in_sand_bazel_50p.jpeg)

The inconvenient truth is that by leveraging language package management packages and patterns, they've _infected_ or _poisoned_ the build system with ultimately the same root problems (diamond dependency) Google set out to thwart when building Bazel and vendoring dependencies.

To illustrate this, let's walk through an example within the Python ecosystem how one can easily run-amuck with semantic versioning, diamond dependencies and shared libraries.

We will build two Python packages **a** & **b**. Each package will have its own Python C extension which in turn depends on a C shared library **foo**. The idea here is that two distinct developers develop **a** & **b** but they rely on the same common **foo** C shared object library.

Using these packages in a Bazel build system, would look like:
```starlark
py_library(
    name = "example",
    srcs = [ "example.py"],
    deps = [
        # has a dependency on libfoo
        "requirement(a)",
        # has a dependency on libfoo
        "requirement(b)"
    ],
)
```

Originally, when using package **a** or **b** you had to install the shared library on your system, likely using a package manager like _homebrew_, _dnf_ or _apt_. The Python ecosystem recognized this was a UX nightmare and came out with [PEP 513](https://peps.python.org/pep-0513/) which describes the process of bundling the shared library (in this case _foo_) within the wheel itself using something like _auditwheel_ and giving the wheel produced the moniker "manylinux".

_Thus solving the problem, right?_
What happens when you have two packages that have built against a common shared object library at two different versions?


Here is the [sample repository](https://github.com/fzakaria/python-shared-object-fallacy) we will use to demonstrate how this is doomed for failure.
We setup two packages **a** and **b** both with a C extension **ext.c**.
Each C extension will link against **libfoo**. To mimic libfoo changing slightly across developer machines we have each package link against the variant within it's directory.

In the case of libfoo within A it has the symbol _buzz_.

```c
void buzz() {
    printf("buzz from libfoo 1.1\n");
}
```

In the case of libfoo within B it has the symbol _bar_.

```c
void bar() {
    printf("bar from libfoo 1.2\n");
}
```

Notably, they are each missing the other respective function.

```console
src
├── a
│   ├── ext.c
│   ├── __init__.py
│   └── libfoo
│       ├── foo.c
│       ├── foo.h
│       ├── libfoo.so
│       └── Makefile
└── b
    ├── ext.c
    ├── __init__.py
    └── libfoo
        ├── foo.c
        ├── foo.h
        ├── libfoo.so
        └── Makefile
```

Both C extensions get build and list needing **libfoo** as a shared object dependency.

```console
patchelf --print-needed a/ext.cpython-311-x86_64-linux-gnu.so 
libfoo.so
libc.so.6

patchelf --print-needed b/ext.cpython-311-x86_64-linux-gnu.so 
libfoo.so
libc.so.6
```

Trying to import both packages though results in a failure 💥.  

The problem is that only a single library with the given name _libfoo.so_ can be loaded by the dynamic linker at runtime.

It doesn't matter if the shared objects are included in the wheel in the case of manylinux variants or found in the system. This is a diamond-dependency problem for the dependent shared library between two Python packages.

This problem is made even worse in that Python packages _include no information about the version of their dependent shared libraries_. **Semantic versioning is a lie.**

```console
>>> import a.ext
>>> a.ext.buzz()
buzz from libfoo 1.1
>>> import b.ext
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/.../.venv/lib/python3.11/site-packages/root-1.1-py3.11-linux-x86_64.egg/b/__init__.py", line 1, in <module>
    from b.ext import bar
ImportError: /.../.venv/lib/python3.11/site-packages/root-1.1-py3.11-linux-x86_64.egg/b/ext.cpython-311-x86_64-linux-gnu.so:
undefined symbol: bar
```
For most of us at the hobbyist level this may not be a problem as _thankfully_ C library developers for popular packages have taken the onerous burden to making them forward and backwards compatible through the use of symbol versioning.

As an enterprise company however whose adopted Bazel with the promise though of reproducible and hermetic builds, we've been grifted.

The only true solution to this problem is to build all your software together and vendor all your dependencies so that at least you know which version of the diamond dependency problem you've chosen ahead of time and can plan accordingly.