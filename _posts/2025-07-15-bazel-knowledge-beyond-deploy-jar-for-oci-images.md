---
layout: post
title: 'Bazel Knowledge: Beyond _deploy.jar for OCI images'
date: 2025-07-15 21:04 -0700
---

> Special shoutout to [aspect-build/rules_py](https://github.com/aspect-build/rules_py) whose inspiration for the [py_image_layer](https://github.com/aspect-build/rules_py/blob/5968bcbde0cc7224b104bea3255a97bda29c89f1/docs/py_image_layer.md) helped me in crafting this solution. 🙏

Getting up and running with [Bazel](http://bazel.build/) can feel simple, especially if you are running everything from `bazel` itself.

A simple `java_binary` can be invoked effortlessly with `bazel run //:hello_world`, and seemingly everything is taken care for you.

What if it comes time to now distribute this code?

If you are writing any server-like code, there's a good chance you want to package up your `java_binary` into an OCI image so that you can run it with your container orchestration framework du-jour.

A quick peek at the state-of-the-art Bazel ruleset for this task leads you to [rules_oci](https://github.com/bazel-contrib/rules_oci) 🫣 whose own [documentation](https://github.com/bazel-contrib/rules_oci/blob/ee577e1b0e7ff2db7d501597e95f6d841765571f/docs/java.md) quickly sends you down the rabbit hole of using `_deploy.jar`.

> The `_deploy.jar` in Bazel is a *self-contained* jar file which makes it quite easy to run with a simple `java -jar` command.

```python
oci_image(
    name = "java_image",
    base = "@distroless_java",
    entrypoint = [
        "java",
        "-jar",
        "/path/to/Application_deploy.jar",
    ],
    ...
)
```

What's the problem with this? 🤔


While simple, this is a nightmare for container image caching. Any change to your application code, even a one-line fix, forces a rebuild of **the entire JAR**. 😱

OCI container runtimes (i.e. Docker and friends) build images from a stack of immutable layers. Each layer is a tarball of filesystem changes, identified by a content-addressable digest (a SHA256 hash of the layer's uncompressed tarball). When you pull an image, the runtime downloads only the layers it doesn't already have in its local cache.

Placing all application code and dependencies into a single JAR means that any code change, no matter how small, results in a completely new JAR and, consequently, a new image layer. For large Java applications, this leads to unnecessary duplication and inefficient distribution.

What can we do about this ? 🤓

Instead of the `_deploy.jar`, we can use the _exploded runfiles directory_ that `java_binary` generates. This directory contains all the necessary files laid out in a structured way. The key is to split this directory's contents into separate layers: application code, third-party dependencies (i.e. maven) & JDK.

> This exploded runfiles directory, is in fact the same setup how `java_binary` is run when invoked with `bazel run`. ☝️

We will leverage [mtree](https://man.freebsd.org/cgi/man.cgi?mtree(8)) to help us accomplish our goal! It is a format for creating a manifest for a file hierarchy. It's essentially a text file that describes a directory tree, listing each file, its permissions, ownership, and other metadata. The standard `tar` utility can use an _mtree manifest_ to create a tarball.

Here is a simple `java_binary` example we will be using for our example. It has a single `java_library` dependency as well as a third-party dependency `@maven//:com_google_guava_guava` via [rules_jvm_external](https://github.com/bazel-contrib/rules_jvm_external).

```python
load("@tar.bzl", "mtree_spec")
load("@rules_java//java:defs.bzl", "java_binary", "java_library")

java_binary(
  name = "hello_world",
  srcs = ["HelloWorld.java"],
  main_class = "HelloWorld",
  deps = [":library",],
)

java_library(
  name = "library",
  srcs = ["Library.java"],
  deps = ["@maven//:com_google_guava_guava",],
)

mtree_spec(
  name = "mtree",
  srcs = [":hello_world"]
)
```

If we look into the produced mtree file (`//:mtree`), you can see it's a full mapping of all the necessary files, JARs and JDK, necessary to run the application.

```
> cat bazel-bin/mtree.spec | head
hello_world uid=0 gid=0 time=1672560000 mode=0755 type=file content=bazel-out/darwin_arm64-fastbuild/bin/hello_world
hello_world.jar uid=0 gid=0 time=1672560000 mode=0755 type=file content=bazel-out/darwin_arm64-fastbuild/bin/hello_world.jar
hello_world.runfiles uid=0 gid=0 time=1672560000 mode=0755 type=dir
hello_world.runfiles/_main/ uid=0 gid=0 time=1672560000 mode=0755 type=dir
hello_world.runfiles/_main/liblibrary.jar uid=0 gid=0 time=1672560000 mode=0755 type=file content=bazel-out/darwin_arm64-fastbuild/bin/liblibrary.jar
hello_world.runfiles/_main/hello_world uid=0 gid=0 time=1672560000 mode=0755 type=file content=bazel-out/darwin_arm64-fastbuild/bin/hello_world
hello_world.runfiles/_main/hello_world.jar uid=0 gid=0 time=1672560000 mode=0755 type=file content=bazel-out/darwin_arm64-fastbuild/bin/hello_world.jar
hello_world.runfiles/rules_jvm_external++maven+maven/ uid=0 gid=0 time=1672560000 mode=0755 type=dir
hello_world.runfiles/rules_jvm_external++maven+maven/com uid=0 gid=0 time=1672560000 mode=0755 type=dir
hello_world.runfiles/rules_jvm_external++maven+maven/com/google uid=0 gid=0 time=1672560000 mode=0755 type=dir
```

Our goal will be to create an `mtree` specification of a `java_binary` and split the manifest into 3 individual files for the application code, third-party dependencies and the JDK. 🎯

We can then leverage these separate `mtree` specifications to create indvidual tarballs for our separate layers and voilà. 🤌🏼


First let's create `SplitMTree.java` which is our small utility which given a _match string_ simply selects the matching lines. This is how we will create 3 distinct mutated `mtree` manifests.

<details markdown="1">
<summary markdown="span">SplitMTree.java</summary>
    
```java
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class SplitMTree {
  public static void main(String[] args) throws IOException {
    if (args.length < 3) {
      System.err.println("Usage: SplitMtree <input> <match> <output>");
      System.exit(1);
    }

    Path input = Paths.get(args[0]);
    String match = args[1];
    Path output = Paths.get(args[2]);

    List<String> lines = new ArrayList<>();

    try (BufferedReader reader = Files.newBufferedReader(input)) {
      String line;
      while ((line = reader.readLine()) != null) {
        if (line.isBlank()) continue;

        if (line.contains(match)) {
          lines.add(line);
        }
      }
    }

    Files.write(output, lines);
  }
}
```
    
</details>

Next our simple `rule` to apply this splitter is straight-forward and simply invokes it via `ctx.actions.run`.

<details markdown="1">
<summary markdown="span">mtree_splitter.bzl</summary>
    
```python
def _impl(ctx):
  """Implementation of the mtree_splitter rule."""
  mtree = ctx.file.mtree
  modified_mtree = ctx.actions.declare_file("{}.mtree".format(ctx.label.name))
  ctx.actions.run(
    inputs = [mtree],
    outputs = [modified_mtree],
    executable = ctx.executable._splitter,
    arguments = [
      mtree.path,
      ctx.attr.match,
      modified_mtree.path,
    ],
    progress_message = "Splitting mtree with match {}".format(
      ctx.attr.match,
    ),
    mnemonic = "MTreeSplitter",
  )
  return [DefaultInfo(files = depset([modified_mtree]))]

mtree_splitter = rule(
  implementation = _impl,
  attrs = {
    "mtree": attr.label(
      doc = "A label to a mtree file to split.",
      allow_single_file = True,
      mandatory = True,
    ),
    "match": attr.string(
      doc = "A string to match against the mtree file.",
      mandatory = True,
    ),
    "_splitter": attr.label(
      doc = "Our simple utility to split the mtree file based on the match.",
      default = Label("//:split_mtree"),
      executable = True,
      cfg = "exec",
    ),
  },
)
``` 
</details>

Now we put this together in a macro `java_image_layer` that will create all the necessary targets for a given `java_binary`. We construct the `mtree`, split it into 3 parts, and for each part construct a `tar`. Finally, we bind all the layers together via a `filegroup` so that we can pass this sole target to the `oci_image` definition.

> We place some sensible defaults for the matching we search for to create our individual layers. For instance, we are using the default `remotejdk` included by [rules_java](https://github.com/bazelbuild/rules_java) so we simply filter on `rules_java++toolchains+remotejdk`.

```python
def java_image_layer(name, binary, platform, **kwargs):
  """Creates a Java image layer by splitting the provided binary into multiple layers based on mtree specifications.

  Args:
      name: The name of the layer.
      binary: The Java binary to be split into layers.
      platform: The target platform for the layer.
      **kwargs: Additional attributes to be passed to the filegroup rule.
  """
  mtree_name = "{}-mtree".format(name)
  mtree_spec(
    name = mtree_name,
    srcs = [binary],
  )
  groups = {
    "jdk": "rules_java++toolchains+remotejdk",
    "maven": "rules_jvm_external++maven",
    "main": "_main",
  }

  srcs = []
  for group, match in groups.items():
    mtree_modified = "{}_{}.mtree".format(name, group)
    mtree_splitter(
      name = mtree_modified,
      mtree = mtree_name,
      match = match,
    )

    tar_name = "{}_{}".format(name, group)
    tar(
      name = tar_name,
      srcs = [binary],
      mtree = mtree_modified,
    )

    srcs.append(tar_name)

  platform_transition_filegroup(
    name = name,
    srcs = srcs,
    target_platform = platform,
    **kwargs
  )
```

❗ We use [platform_transition_filegroup](https://github.com/bazel-contrib/bazel-lib/blob/e55168fda556b14f5356602665c2e5ba9737b294/docs/transitions.md#L28) rather than the `native.filegroup` because we need to transition our artifact for the target platform. If we are developing on MacOS for instance, we need to make sure we transition the JDK to the Linux variant.

Now that we have all this setup, what does it look like to use?

```python
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load")
load(":java_image_layer.bzl", "java_image_layer")

config_setting(
  name = "host_x86_64",
  values = {"cpu": "x86_64"},
)

config_setting(
  name = "host_aarch64",
  values = {"cpu": "aarch64"},
)

config_setting(
  name = "host_arm64",
  # Why does arm64 on MacOS prefix with darwin?
  values = {"cpu": "darwin_arm64"},
)

platform(
  name = "linux_x86_64_host",
  constraint_values = [
    "@platforms//os:linux",
    "@platforms//cpu:x86_64",
  ],
)

platform(
  name = "linux_aarch64_host",
  constraint_values = [
    "@platforms//os:linux",
    "@platforms//cpu:arm64",
  ],
)

java_image_layer(
  name = "java_image_layers",
  binary = ":hello_world",
  platform = select({
    ":host_x86_64": ":linux_x86_64_host",
    ":host_aarch64": ":linux_aarch64_host",
    ":host_arm64": ":linux_aarch64_host",
  }),
)

oci_image(
  name = "image",
  base = "@bookworm_slim",
  entrypoint = [
    "hello_world.runfiles/_main/hello_world",
  ],
  tars = [":java_image_layers"],
)

oci_load(
  name = "load",
  image = ":image",
  repo_tags = ["hello-world:latest"],
)
```

A little verbose to include all the `config_setting` but I wanted to show how to create an OCI image even on a MacOS. 🫠

⚠️ A special note on the base image: because the default `java_binary` launcher is a bash script, we cannot use a [distroless base image](https://github.com/GoogleContainerTools/distroless). We need a base that includes a shell. I picked Debian's [bookworm_slim](https://hub.docker.com/layers/library/debian/bookworm-slim/images/sha256-94882f177083c7fa6764b9ef2a86ed3c29c99593b34d5441648a7fb3c0cd10ec) for this example.

> The `entrypoint` is no longer `java -jar`. It now points to the shell script launcher `java_binary` creates. You will have to change the entrypoint to match the name of your binary.

We can now build our image and load into our local docker daemon.

We will inspect the image uding `docker history` and we can confirm there are 4 layers, 3 we created and 1 for the base image. Bazel even includes the target name for the history comment of the layer. 🔥 

```bash
> bazel run //:load2
INFO: Invocation ID: d2d143f8-1f7e-4b8a-88be-c8cd7d6430df
INFO: Analyzed target //:load2 (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //:load2 up-to-date:
  bazel-bin/load2.sh
INFO: Elapsed time: 0.260s, Critical Path: 0.01s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/load2.sh
Loaded image: hello-world:latest

> docker inspect hello-world:latest | jq '.[0].RootFS.Layers'
[
  "sha256:58d7b7786e983ece7504ec6d3ac44cf4cebc474260a3b3ace4b26fd59935c22e",
  "sha256:f859b0c2d3bfcf1f16a6b2469a4356b829007a2ef65dc4705af5286292e2ee0e",
  "sha256:33e0c4d79f867b55ec3720e0266dda5206542ff647a5fa8d9e0cb9e80dd668c8",
  "sha256:5f1a9bff7956c994f0fe57c4270bd4e967cab0e1c0ab24d85bcf08e7c340e950"
]

> docker history hello-world:latest

IMAGE          CREATED       CREATED BY                                      SIZE      COMMENT
c3658883db33   N/A           bazel build //:java_image_layer_main            16.7kB
<missing>      N/A           bazel build //:java_image_layer_maven           3.31MB
<missing>      N/A           bazel build //:java_image_layer_jdk             276MB
<missing>      2 weeks ago   # debian.sh --arch 'arm64' out/ 'bookworm' '…   97.2MB    debuerreotype 0.15
```

Just to confirm, let's run our docker image!

```bash
> docker run --rm hello-world:latest
Hello from the Library with Guava!
```

I will then go ahead and change something small in our application code and confirm only a _single layer_ has changed.

```patch
@@ -2,6 +2,6 @@ import com.google.common.base.Joiner;

 public class Library {
     public String getMessage() {
-        return Joiner.on(' ').join("Hello", "from", "the", "Library", "with", "Guava!");
+        return Joiner.on(' ').join("Goodbye", "from", "the", "Library", "with", "Guava !");
     }
 }
```

```bash
> bazel run //:load2
INFO: Invocation ID: d289ae67-865b-4699-a47a-b0142a609ec7
INFO: Analyzed target //:load2 (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //:load2 up-to-date:
  bazel-bin/load2.sh
INFO: Elapsed time: 1.687s, Critical Path: 1.50s
INFO: 9 processes: 3 action cache hit, 1 internal, 7 darwin-sandbox, 1 worker.
INFO: Build completed successfully, 9 total actions
INFO: Running command line: bazel-bin/load2.sh
2cde5e70cafc: Loading layer [==================================================>]  20.48kB/20.48kB
The image hello-world:latest already exists, renaming the old one with ID sha256:c3658883db334fee7f36acf77ce1de4cb6a1bed3f23c01c6a378c36cac8ce56a to empty string
Loaded image: hello-world:latest

> docker run --rm hello-world:latest
Goodbye from the Library with Guava !

> docker inspect hello-world:latest | jq '.[0].RootFS.Layers'

[
  "sha256:58d7b7786e983ece7504ec6d3ac44cf4cebc474260a3b3ace4b26fd59935c22e",
  "sha256:f859b0c2d3bfcf1f16a6b2469a4356b829007a2ef65dc4705af5286292e2ee0e",
  "sha256:33e0c4d79f867b55ec3720e0266dda5206542ff647a5fa8d9e0cb9e80dd668c8",
  "sha256:2cde5e70cafce28c14d306cd0dc07cdd3802d1aa1333ed9c1c9fe8316b727fd2"
]
```

If you scroll back up, you'll see that only a single layer `2cde5e70cafce28c14d306cd0dc07cdd3802d1aa1333ed9c1c9fe8316b727fd2` differs between the two images. Huzzah!

By moving away from `_deploy.jar` and using the `mtree` manipulation technique, we've created a properly layered Java container. Now, changes to our application code will only result in a small, new layer, making our container builds and deployments significantly faster and more efficient. 🚀