---
layout: post
title: Nix that looks like Bazel
date: 2025-04-02 19:22 -0700
---

> This is an idea 💡 that came from [PlanetNix](https://planetnix.com/). I **did not** originate the idea.

At the 2025 North American NixCon ([PlanetNix](https://planetnix.com/)), one of the interesting _lightning talks_ was from someone from [Groq](https://groq.com/) who demo'd what I originally thought to be a terrible idea but within a few minutes thought it was so evil it was good. 😈

What if we redesigned building software in Nix to look like Bazel?

What got me thinking about this? Well a blog post was published about [bonanza](https://blogsystem5.substack.com/p/bazel-next-generation) a potential "next-gen" incarnation of Bazel. Nix already solves many of the challenges _bonanza_ seeks to fix.

Follow me while I try to rebuild a Nix build-framework to build software, specifically Java, such that it looks like Bazel. 👇

If you are unfamiliar with [Bazel](http://bazel.build/), it's a large-scale monorepo-centric build system open-sourced by Google. It has inspired many clones such as [Buck](https://buck.build/), [Pants](https://www.pantsbuild.org/), [Please](https://please.build/) and so forth.

It uses a "python-like language to define build targets. The surface area is much smaller than something like Nix which lets you run arbitrary bash -- although Bazel does have a "generic bash rule" as well.

Here is what a typical Bazel build definition for a Java program may look like. One key distinction are that dependencies are referenced by _label_ and targets within the same file (package), can be defined starting after the colon.

> If you are confused, that's ok. This is not meant to be a great tutorial on Bazel.  🤔

```python
java_binary(
    name = "ProjectRunner",
    srcs = ["src/main/java/com/example/ProjectRunner.java"],
    main_class = "com.example.ProjectRunner",
    deps = [":greeter"],
)

java_library(
    name = "greeter",
    srcs = ["src/main/java/com/example/Greeting.java"],
)
```

Traditionally in Nix, you would replace these rules with something like `mkDerivation` and build the single final application.

Here is something similar we can write in _pure_ Nix.

```nix
# com/example/lib_b/default.nix
{java_library}:
java_library {
  name = "lib_b";
  srcs = [
    ./LibraryB.java
  ];
  deps = [
    "//com/example/lib_a"
  ];
}
# com/example/default.nix
{java_binary}:
java_binary {
  name = "main";
  mainClass = "com.example.Main";
  srcs = [
    ./Main.java
  ];
  deps = [
    "//com/example/lib_b"
  ];
}
```

Wow, that looks surprisingly similar. 😮

Getting this to work is surprisingly easy. We only need two function definitions for `java_library` and `java_binary`.

First in order to build anything in Java we need "libraries" (JARs).
[Nixpkgs](https://github.com/NixOS/nixpkgs) already has this great concept that any JAR placed in `share/java` gets automatically added to the _CLASSPATH_ during compilation in a `mkDerivation`.

```nix
{
  stdenv,
  lib,
  jdk,
  pkgs,
}: let
  fs = lib.fileset;
in
  {
    name,
    srcs,
    deps ? [],
  }:
    stdenv.mkDerivation {
      inherit name;
      srcs = fs.toSource {
        root = ./.;
        fileset = fs.unions srcs;
      };
      buildInputs = map (d: pkgs.${d}) deps;
      nativeBuildInputs = [jdk];
      buildPhase = ''
        find $srcs -name "*.java" | xargs javac -d .
        jar -cvf ${name}.jar -C . .
      '';
      installPhase = ''
        mkdir -p $out/share/java
        mv ${name}.jar $out/share/java/${name}.jar
      '';
    }
```

That makes compiling individal libraries pretty straightforward.

What about running them? In that case, we need the full transitive-closure of all compile dependencies to be present at runtime.

Recursion! In this case it is safe to do since we aren't using any infinite lazy lists. 😏

Our `java_binary` definition now becomes straightforward. It is a `java_library` & a `writeTextFile` that sets the _CLASSPATH_ before calling our main class.

```nix
{
  writeTextFile,
  java_library,
  jdk,
  lib,
  pkgs,
}: {
  name,
  mainClass,
  srcs,
  deps ? [],
}: let
  # get all deps transitively
  java_lib = java_library {
    name = "lib_${name}";
    inherit srcs;
    inherit deps;
  };
  # Recursively collect buildInputs from a list of derivations
  collectBuildInputs = inputs:
    builtins.concatMap (
      drv: let
        deps = drv.buildInputs or [];
      in
        [drv] ++ collectBuildInputs deps
    )
    inputs;
  depsAsPkgs = map (d: pkgs.${d}) deps;
  classpath = lib.concatStringsSep ":" (map (x: "${x}/share/java/${x.name}.jar") (collectBuildInputs (depsAsPkgs ++ [java_lib])));
in
  writeTextFile {
    inherit name;
    text = ''
      ${jdk}/bin/java -cp ${classpath} ${mainClass}
    '';
    executable = true;
    destination = "/bin/${name}";
  }
```

`collectBuildInputs` is the function that recursively walks all the dependencies and collects them to produce the necessary _CLASSPATH_.

I create now my top-level `default.nix` to define the targets possible

> This step could likely be done at evaluation time and traverse the filesystem, but I'm keeping it _simple_ for the purpose of understanding. 💪

```nix
let
  pkgs =
    import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/5ef6c425980847c78a80d759abc476e941a9bf42.tar.gz") {
      overlays = [
        (self: super: rec {
          java_library = super.callPackage ./java_library.nix {};
          java_binary = super.callPackage ./java_binary.nix {};
          "//com/example/lib_a" = super.callPackage ./com/example/lib_a {};
          "//com/example/lib_b"= super.callPackage ./com/example/lib_b {};
          "//com/example:main"= super.callPackage ./com/example {};
        })
      ];
    };
in
{
  "//com/example/lib_a" = pkgs."//com/example/lib_a";
  "//com/example/lib_b" = pkgs."//com/example/lib_b";
  "//com/example:main" = pkgs."//com/example:main";
}
```

Now all that's left to do is build & run the program to validate it works.

```console
> nix-build -A "//com/example:main"
/nix/store/ry72i3ha3jrcpbz6yn4yna2wsx532gv8-main

> cat /nix/store/ry72i3ha3jrcpbz6yn4yna2wsx532gv8-main/bin/main 
/nix/store/1frnfh27i5pqk9xqahrjchlwyfzqgs1y-openjdk-21.0.5+11/bin/java -cp /nix/store/566jmxk1f8slkmp3mvrg4q0d8lbng5xx-lib_b/share/java/lib_b.jar:/nix/store/30lvqr3sc75yf9afzcl7l6j8phhw0xzv-lib_a/share/java/lib_a.jar:/nix/store/4zdhqm0ld93cqiv811brk5i6pyrcdvlg-lib_main/share/java/lib_main.jar:/nix/store/566jmxk1f8slkmp3mvrg4q0d8lbng5xx-lib_b/share/java/lib_b.jar:/nix/store/30lvqr3sc75yf9afzcl7l6j8phhw0xzv-lib_a/share/java/lib_a.jar com.example.Main

> ./result/bin/main 
Hello from Library A! and Library B!
```

Nice! 🔥

What is the appeal of all this?

Well, having a smaller API surface to build packages for a particular language is nice. You limit the opportunity for _esoteric_ setups to creep in.

Finally, it's likely my familiarity to Bazel, but I find reading the build definitions for the languages relatively straightforward as they all follow the same format.

By defining all the build targets individually at the language level, the code is also better set up to do incremental & parallel builds.

> n.b. Specifically for Java, doing incremental builds would necessitate something like [ijar]({% post_url 2024-10-29-bazel-knowledge-what-s-an-interface-jar %}).