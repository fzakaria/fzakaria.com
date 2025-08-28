---
layout: post
title: 'Bazel Knowledge: dive into unused_deps'
date: 2025-08-27 16:28 -0700
---

The Java language implementation for [Bazel](https://bazel.build/) has a great feature called [strict dependencies](https://blog.bazel.build/2017/06/28/sjd-unused_deps.html) -- the feature enforces that all directly used classes are loaded from jars provided by a target's direct dependencies.

If you've ever seen the following message from Bazel, you've encountered the feature.

```bash
error: [strict] Using type Dog from an indirect dependency (TOOL_INFO: "//:dog").
See command below **
    public void dogs(Dog dog) {
                     ^
 ** Please add the following dependencies:
  //:dog to //:park
 ** You can use the following buildozer command:
buildozer 'add deps //:dog' //:park
```

The analog tool for removing dependencies which are not directly referenced is [unused_deps](https://github.com/bazelbuild/buildtools/tree/4006b543a694f6cf77c2d8cc188c5f53f3bac1d9/unused_deps).

You can run this on your Java codebase to prune your dependencies to those only strictly required.

```bash
> unused_deps //...
....
buildozer "add deps $(bazel query 'labels(exports, :cat)' | tr '\n' ' ')" //:park
buildozer 'remove deps :cat' //:park
```

That's a pretty cool feature, but how does it work? 🤔

Turns out the Go code for the tool is relatively short, let's dive in! I love learning the inner machinery of how the tools I leverage work. 🤓

Let's use a simple example to explore the tool.

```python
java_library(
    name = "libC",
    srcs = ["src/C.java"],
)

java_library(
    name = "libB",
    srcs = ["src/B.java"],
    deps = [":libC"],
)

java_library(
    name = "app",
    srcs = ["src/A.java"],
    deps = [":libB"],
)
```

First thing the tool does is query which targets to _look at_, and it emits this to _stderr_ so that part is a little obvious.

```bash
> unused_deps //...
bazel query --tool_tag=unused_deps --keep_going \
            --color=yes --curses=yes \
            kind('(kt|java|android)_*', //...)
...
```

It performs a query searching for any rules that start with `kt_`, `java_` or `android_`. This would catch our common rules such as `java_library` or `java_binary`.

Here is where things get a little more _interesting_. The tool emits an ephemeral Bazel `WORKSPACE` in a temporary directory that contains a Bazel [aspect](https://bazel.build/extending/aspects).

What is the aspect the tool _injects_ into our codebase?

```python
# Explicitly creates a params file for a Javac action.
def _javac_params(target, ctx):
    params = []
    for action in target.actions:
        if not action.mnemonic == "Javac" and not action.mnemonic == "KotlinCompile":
            continue
        output = ctx.actions.declare_file("%s.javac_params" % target.label.name)
        args = ctx.actions.args()
        args.add_all(action.argv)
        ctx.actions.write(
            output = output,
            content = args,
        )
        params.append(output)
        break
    return [OutputGroupInfo(unused_deps_outputs = depset(params))]

javac_params = aspect(
    implementation = _javac_params,
)
```

The aspect is designed to emit additional files `%s.javac_params` that contain the arguments to the compilation actions.

If we inspect what this file looks like for the simple `java_library` I created `//:app`, we see it's the arguments to `java` itself.

```bash
> cat bazel-bin/app.javac_params | head
external/rules_java++toolchains+remotejdk21_macos_aarch64/bin/java
'--add-opens=java.base/java.lang=ALL-UNNAMED'
'-Dsun.io.useCanonCaches=false'
-XX:-CompactStrings
-Xlog:disable
'-Xlog:all=warning:stderr:uptime,level,tags'
-jar
external/rules_java++toolchains+remote_java_tools/java_tools/JavaBuilder_deploy.jar
--output
bazel-out/darwin_arm64-fastbuild/bin/libapp.jar
--native_header_output
bazel-out/darwin_arm64-fastbuild/bin/libapp-native-header.jar
--output_manifest_proto
bazel-out/darwin_arm64-fastbuild/bin/libapp.jar_manifest_proto
```

> If you are wondering what `JavaBuilder_deploy.jar` is?  Bazel uses a custom compiler plugin that will be relevant shortly. ☝️

How does the aspect get injected into our project?

Well, after figuring out which targets to build via the `bazel query`, `unused_deps` will `bazel build` your target pattern and specify `--override_repository` to include this additional dependency and enable the aspect via the `--aspects` flag.

```bash
> unused_deps //...
...
bazel build --tool_tag=unused_deps --keep_going --color=yes --curses=yes \
            --output_groups=+unused_deps_outputs \
            --override_repository=unused_deps=/var/folders/4w/cclwgg8s5mxc0g4lbsqkkqdh0000gp/T/unused_deps3033999312 \
            --aspects=@@unused_deps//:unused_deps.bzl%javac_params \
            //...
```

> If you are using Bazel 8+ and have `WORKSPACE` disabled, which is the default, you will need my [PR#1387](https://github.com/bazelbuild/buildtools/pull/1387) to make it work.

The end result after the `bazel build` is that every Java target (i.e. `java_library`) will have produced a `javac_params` file in the `bazel-out` directory.

Why did it go through such lengths to produce this file? The tool is trying is trying to find the direct dependencies of each Java target.

The tool searches for the line `--direct_dependencies` for each target to see the dependencies that were needed to build it.

```bash
> cat bazel-bin/app.javac_params | grep direct_dependencies -A 3 -B 2
--strict_java_deps
ERROR
--direct_dependencies
bazel-out/darwin_arm64-fastbuild/bin/liblibB-hjar.jar
--experimental_fix_deps_tool
```

**QUESTION #1**: Why does the tool need to set up this aspect anyways? Bazel will already emit param files `*-0.params` for each Java target that contains nearly identical information.

```bash
> cat bazel-bin/libapp.jar-0.params | grep "direct_dependencies" -A 3
--direct_dependencies
bazel-out/darwin_arm64-fastbuild/bin/liblibB-hjar.jar
--experimental_fix_deps_tool
add_dep
```

The tool will then iterate through all these JAR files, open them up and look at the `MANIFEST.MF` file within it for the value of `Target-Label` which is the 
Bazel target expression for this dependency.

In this case we can see the desired value is `Target-Label: //:libB`.

```bash
> zipinfo bazel-out/darwin_arm64-fastbuild/bin/liblibB-hjar.jar
Archive:  bazel-out/darwin_arm64-fastbuild/bin/liblibB-hjar.jar
Zip file size: 680 bytes, number of entries: 3
-rw----     1.0 fat        0 bx stor 10-Jan-01 00:00 META-INF/
-rw----     1.0 fat       67 b- stor 10-Jan-01 00:00 META-INF/MANIFEST.MF
-rw----     1.0 fat      263 b- stor 10-Jan-01 00:00 example/b/B.class
3 files, 330 bytes uncompressed, 330 bytes compressed:  0.0%

> unzip -p bazel-out/darwin_arm64-fastbuild/bin/liblibB-hjar.jar | head -n 3
Manifest-Version: 1.0
Created-By: bazel
Target-Label: //:libB
```

If you happen to use [rules_jvm_external](https://github.com/bazel-contrib/rules_jvm_external) to pull in Maven dependencies, the ruleset will "stamp" the downloaded JARs which means injecting them with the `Target-Label` entry in their `MANIFEST.MF` specifically to work with `unused_deps` [[ref](https://github.com/bazel-contrib/rules_jvm_external/blob/1c5cfbf96de595a3e23cf440fb40380cc28c1aea/private/rules/jvm_import.bzl#L35)].

```bash
> unzip -p bazel-bin/external/rules_jvm_external++maven+maven/com/google/guava/guava/32.0.1-jre/processed_guava-32.0.1-jre.jar | grep Target-Label
Target-Label: @maven//:com_google_guava_guava
```

**QUESTION #2** Why does `unused_deps` go to such lengths to discover the labels of the direct dependencies of a particular target?

Could this be replaced with a `bazel query` command as well ? 🕵️

For our `//:app` target we have the following
```python
java_library(
    name = "app",
    srcs = ["src/A.java"],
    deps = [":libB"], 
)
```

```bash
> bazel query "kind(java_*, deps(//:app, 1))" --notool_deps --noimplicit_deps
INFO: Invocation ID: 09539f9d-9beb-401c-aca4-4728d5cfa75e
//:app
//:libB
```

After the labels of all the direct dependencies are known for each target, `unused_deps` will parse the jdeps file, `./bazel-bin/libapp.jdeps`,  of each target which is a binary protocol serialization of `blaze_deps.Dependencies` found in [deps.go](https://github.com/bazelbuild/buildtools/blob/4006b543a694f6cf77c2d8cc188c5f53f3bac1d9/deps_proto/deps.proto).

Using `protoc` we can inspect and explore the file.

```bash
> protoc --proto_path /Users/fzakaria/code/ --decode blaze_deps.Dependencies \
        /Users/fzakaria/code/github.com/bazelbuild/buildtools/deps_proto/deps.proto \
        < ./bazel-bin/libapp.jdeps
dependency {
  path: "bazel-out/darwin_arm64-fastbuild/bin/liblibB-hjar.jar"
  kind: EXPLICIT
}
rule_label: "//:app"
success: true
contained_package: "example.app"
```

This is the _super cool feature_ of Bazel and integrating into the Java compiler. 🔥

Bazel invokes the Java compiler itself and will then iterate through all the symbols, via a provided symbol table, the compiler had to resolve. For each symbol, if the dependency is not from the `--direct_dependencies` list than it must have been provided through a transitive dependency. [[ref](https://github.com/bazelbuild/bazel/blob/ffe95d234eed3e64c9b4028b191d10dc10bc0861/src/java_tools/buildjar/java/com/google/devtools/build/buildjar/javac/plugins/dependency/ImplicitDependencyExtractor.java#L101)].

The presence of kind `IMPLICIT` would actually trigger a failure for the strict Java dependency check if enabled.

`unused_deps` then takes the list of the direct dependencies and keeps only all the dependencies the compiler reported back as _actually requiring_ to perform compilation.

The set difference represents the set of targets that are effectively _unused_ and can be reported back to the user for removal! ✨

**QUESTION #3**: There is a third type of dependency kind `INCOMPLETE` which I saw when investigating our codebase. I was unable to discern how to trigger it and what it represents.

```
dependency {
  path: "bazel-out/darwin_arm64-fastbuild/bin/internal-rest-server/internal-rest-server-project-ijar.jar"
  kind: INCOMPLETE
}
```

What I enjoy about Bazel is learning how you can improve developer experience and provide insightful tools when you integrate the build system deeply with the underlying language, `unused_deps` is a great example of this.