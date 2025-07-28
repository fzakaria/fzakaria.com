---
layout: post
title: 'Bazel Knowledge: Mixing and matching how to build third_party is lunacy'
date: 2025-07-28 10:27 -0700
---

Have you ever found your `java_binary` full of mixed bytecode versions and wondered why?

The original intent of [Bazel](https://bazel.build), and it's peer group (i.e. Buck and Pants), are to build everything from source and to consolidate into large-ish repositories. These are the practices done by the companies (eg. Google and Meta), who built these tools and therefore the tools are originally purpose-built for this use-case.

Building from source for everything is very orthogonal to how most developers experience development, especially in open-source -- unless you are a fan of [NixOS](http://nixos.org/). This makes total sense as the cost of setting up a mono-repository for every small effort would be a Herculean task. In order to "meet developers where they are", Bazel itself has adopted a third-party registry system ([https://registry.bazel.build/](https://registry.bazel.build/)) and rules for individual languages have emerged to make interoperability with pre-existing language package managers simpler such as [rules_jvm_external](https://github.com/bazel-contrib/rules_jvm_external) for Java.


Unfortunately, as the use of [Bazel](https://bazel.build) at _$DAYJOB$_ continues to expand, I am beginning to see the costs and fallout of this popular approach. There is no set standard as to when to build from source and when to pull from a third-party artifact repository such as [Maven Central](https://central.sonatype.com/) across rules, so one may find themselves in at best confusing builds and at worst broken code.

Let's take a look at an example to illustrate this point. If you'd like to see all the source online, I've published them to [fzakaira/reproduction#protobuf-bytecode](https://github.com/fzakaria/reproductions/tree/bazel/protobuf-bytecode).

In this example I would like to leverage a new-ish JDK (eg. JDK21), default language version to 11 (i.e. `java_language_version=11`) **but** I want to build a particular slice of my code at a different bytecode level (`--release=14`).  

> This might seem like a good fit for [transitions](https://bazel.build/extending/config), however I found that to be a big complexity addition to the codebase and if you can avoid it that might be best. 🧠

Let's set up our JDK21 and our language version.
```
common --java_runtime_version=remotejdk_21
common --java_language_version=11
```

Now let's modify the toolchain such that our particular slice of our codebase builds with a different bytecode target.

```python
default_java_toolchain(
  name = "java_toolchain",
  package_configuration = [
    ":specific_packages",
  ],
  source_version = "11",
  target_version = "11",
  visibility = ["//visibility:public"],
)

java_package_configuration(
  name = "specific_packages",
  javacopts = [
    "--release=14",
  ],
  packages = ["specific_packages_group"],
)

package_group(
  name = "specific_packages_group",
  packages = [
    "//slice/...",
  ],
)
```

Here is where it gets _interesting_, let's build a simple `java_binary` and check all the bytecode within it.

```python
proto_library(
  name = "example_proto",
  srcs = ["example.proto"],
)

java_proto_library(
  name = "example_java_proto",
  deps = [":example_proto"],
)

java_binary(
  name = "main",
  srcs = ["Main.java"],
  main_class = "Main",
  runtime_deps = [
    ":example_java_proto"
  ],
)
```

I wrote a simple handy tool, [check-jar-versions](https://github.com/fzakaria/check-jar-versions), that can quickly list out all the bytecode versions within a JAR file.

```bash
> bazel build //slice/:main_deploy.jar
INFO: Invocation ID: dbb086ca-66b4-40bd-a1f4-5b6f733bf671
INFO: Analyzed target //slice:main_deploy.jar (0 packages loaded, 350 targets configured).
INFO: Found 1 target...
Target //slice/:main_deploy.jar up-to-date:
  bazel-bin/main_deploy.jar
INFO: Elapsed time: 0.608s, Critical Path: 0.02s
INFO: 2 processes: 1101 action cache hit, 1 disk cache hit, 1 internal.
INFO: Build completed successfully, 2 total actions

> nix run github:fzakaria/check-jar-versions -- bazel-bin/slice/main_deploy.jar
Class File Format Version: 55 (Java 11) - Number of files: 744
Class File Format Version: 58 (Java 14) - Number of files: 6
```

We see some classes compiled at Java 14 for the code within `//slice` but probably unsurprisingly we get Java 11 as well 😲.

Why ?
This is because `java_proto_library` automatically includes dependencies for the protobuf runtime to the compiled Java code.

```bash
> bazel query "kind('java_library', deps(//:main))"
INFO: Invocation ID: 29b33588-a7cd-450a-a63e-6b044cc19966
@protobuf//java/core:core
@protobuf//java/core:lite_runtime_only
```

Okay well to be honest, since I have a pretty basic application that is a little unsurprising since I guess my assumption is I've built everything from source and clearly `//slice/...` doesn't catch the `@protobuf//` library.

Where this gets a little tricky to find and more subtle is when you mix in prebuilt artifacts from Maven which is popular via [rules_jvm_external](https://github.com/bazel-contrib/rules_jvm_external).

We can demo that by adding a single `http_jar` to our dependency.

```python
http_jar = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_jar")

http_jar(
  name = "protobuf-java",
  integrity = "sha256-0C+GOpCj/8d9Xu7AMcGOV58wx8uY8/OoFP6LiMQ9O8g=",
  urls = ["https://repo1.maven.org/maven2/com/google/protobuf/protobuf-java/4.27.3/protobuf-java-4.27.3.jar"],
)
```

Now if the `protobuf-java` dependency is earlier in the graph for our `java_binary` we get different results.

```python
java_binary(
  name = "main",
  srcs = ["Main.java"],
  main_class = "Main",
  runtime_deps = [
    "@protobuf-java//jar",
    ":example_java_proto"
  ],
)
```

```bash
> bazel build //slice/:main_deploy.jar
INFO: Invocation ID: 424ae6d9-af38-418f-a986-5aa890bc9b1a
INFO: Analyzed target //slice/:main_deploy.jar (0 packages loaded, 351 targets configured).
INFO: Found 1 target...
Target //slice/:main_deploy.jar up-to-date:
  bazel-bin/slice/main_deploy.jar
INFO: Elapsed time: 0.568s, Critical Path: 0.02s
INFO: 2 processes: 1101 action cache hit, 1 disk cache hit, 1 internal.
INFO: Build completed successfully, 2 total actions

> nix run github:fzakaria/check-jar-versions -- bazel-bin/slice/main_deploy.jar
Class File Format Version: 52 (Java 8) - Number of files: 718
Class File Format Version: 55 (Java 11) - Number of files: 45
Class File Format Version: 58 (Java 14) - Number of files: 6
```

Now all those Java 11 files are shadowed by the one from the prebuilt protobuf JAR which are at the Java 8 bytecode level. 🤯

We have established a pattern in our repository where we have decided to use prebuilt JARs for our third-party dependencies. Even if we don't explicitly depend on the prebuilt Maven protobuf JAR, it may come in transitvely from another dependency.

The problem however is that our dependant ruleset [@protobuf](https://github.com/protocolbuffers/protobuf) -- same is true for [@grpc-java](https://github.com/grpc/grpc-java) -- chose to build from source and therefore we get different results depending on the order of the dependencies in the build.

It's even more confusing since `@grpc-java//` mixes & matches the two types [[ref](https://github.com/grpc/grpc-java/blob/c3ef1ab034c8c3c75d2538d7e1c9b5f99583d8bf/compiler/BUILD.bazel#L36)].

```python
java_library(
  name = "java_lite_grpc_library_deps__do_not_reference",
  exports = [
    "//api",
    "//protobuf-lite",
    "//stub",
    artifact("com.google.code.findbugs:jsr305"),
    artifact("com.google.guava:guava"),
  ],
)
```

Mixing prebuilt jars and source-built targets without discipline creates confusing and inconsistent builds. Bazel doesn’t protect you — it just builds what you tell it to. The fact that class files may also be shadowed by others in the graph can hide this fact and lead to suprising failure modes.

Ok, so I sort of understand the problem. What can I do about it ? 🤓

Pick a idiom and try to stick to it ! You might have to go out of your way to do so.

For our repository, we pull in too much from Maven Central in our dependency graph, so we've decided to make sure all our rulesets leverage the same prebuilt JARs.

In the case of `@protobuf//` it meant creating a new `proto_lang_toolchain` that uses the prebuilt JAR.

```python
proto_lang_toolchain(
  name = "protoc_java",
  # stripped for brevity
  blacklisted_protos = [],
  command_line = "--java_out=$(OUT)",
  runtime = "@maven//:com_google_protobuf_protobuf_java",
  toolchain_type = "@com_google_protobuf//bazel/private:java_toolchain_type",
)
```

In the case of `@grpc-java`, we had to patch the rules to do the equivalent.

```patch
diff --git a/compiler/BUILD.bazel b/compiler/BUILD.bazel
index 753f48507..48c872e76 100644
--- a/compiler/BUILD.bazel
+++ b/compiler/BUILD.bazel
@@ -19,13 +19,13 @@ cc_binary(
 java_library(
     name = "java_grpc_library_deps__do_not_reference",
     exports = [
-        "//api",
-        "//protobuf",
-        "//stub",
+        artifact("io.grpc:grpc-api"),
+        artifact("io.grpc:grpc-protobuf"),
+        artifact("io.grpc:grpc-stub"),
         "//stub:javax_annotation",
         artifact("com.google.code.findbugs:jsr305"),
         artifact("com.google.guava:guava"),
-        "@com_google_protobuf//:protobuf_java",
+        artifact("com.google.protobuf:protobuf-java"),
     ],
 )
```