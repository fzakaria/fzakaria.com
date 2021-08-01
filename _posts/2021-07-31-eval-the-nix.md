---
layout: post
title: Eval the Nix
date: 2021-07-31 17:14 -0700
excerpt_separator: <!--more-->
---

I'll keep this post short and _sweet_. I want to write a little blurb that I've been mostly enjoying using **nix eval** to introspect.

<!--more-->

**Scenario 1**
I wanted to set _JAVA_HOME_ to a particular JDK.

You can use `eval` to determine the _JAVA_HOME. The **gotcha** here however, is that the JDK may not necessarily be in your _/nix/home_.

```bash
❯ nix eval nixpkgs.jdk8.home --raw
/nix/store/0jfk27bplglsqh7m945pvayjwh2fy1m0-openjdk-8u272-b10/lib/openjdk
```

A more complete solution is the following.

```bash
❯ export JAVA_HOME=$(nix build nixpkgs.jdk8 && nix eval nixpkgs.jdk8.home --raw)
```

**Scenario 2** I wanted to discover the calculated _/nix/store_ path for a particular derivation.

```bash
❯ nix eval nixpkgs.hello.outPath --raw
/nix/store/jmmw0d3nmklwafcwylvrjb9v69wrbcxf-hello-2.10
```

💡 You can also do something similar to find out the derivation path.

```bash
❯ nix eval nixpkgs.hello.drvPath --raw
/nix/store/wqnx5cgcabxkfp771fmjr1nw7mjr9zlm-hello-2.10.drv
```

**Scenario 3** I want a quick one-liner for what I can do with `nix repl`.

```bash
❯ nix eval '(builtins.attrNames (import <nixpkgs>{}).hello)' --json | jq
[
  "__ignoreNulls",
  "all",
  "args",
  "buildInputs",
  "builder",
  "configureFlags",
  "depsBuildBuild",
  "depsBuildBuildPropagated",
  "depsBuildTarget",
  "depsBuildTargetPropagated",
  "depsHostHost",
  "depsHostHostPropagated",
  "depsTargetTarget",
  "depsTargetTargetPropagated",
  "doCheck",
  "doInstallCheck",
  "drvAttrs",
  "drvPath",
  "inputDerivation",
  "meta",
  "name",
  "nativeBuildInputs",
  "out",
  "outPath",
  "outputName",
  "outputUnspecified",
  "outputs",
  "override",
  "overrideAttrs",
  "overrideDerivation",
  "passthru",
  "patches",
  "pname",
  "propagatedBuildInputs",
  "propagatedNativeBuildInputs",
  "src",
  "stdenv",
  "strictDeps",
  "system",
  "tests",
  "type",
  "userHook",
  "version"
]
```

⚠️ I do find however **annoying** differences between `nix repl` and `nix eval` that I'm not clear on.

For instance the following works on `nix repl` but fails on `nix eval`

```bash
❯ nix repl
Welcome to Nix version 2.3.12. Type :? for help.

nix-repl> :l <nixpkgs>
Added 14373 variables.

nix-repl> hello
«derivation /nix/store/wqnx5cgcabxkfp771fmjr1nw7mjr9zlm-hello-2.10.drv»
```

```bash
❯ nix eval nixpkgs#hello
error: anonymous function at /nix/store/h7b0frzjk6ylyqq471m667yd9bl9n6fm-source/pkgs/build-support/fetchurl/boot.nix:5:1 called with unexpected argument 'meta'

       at /nix/store/h7b0frzjk6ylyqq471m667yd9bl9n6fm-source/pkgs/build-support/fetchzip/default.nix:18:2:

           17|
           18| (fetchurl (let
             |  ^
           19|   basename = baseNameOf (if url != "" then url else builtins.head urls);
(use '--show-trace' to show detailed location information)
```

If you happen to know why, answer [this message on discourse](https://discourse.nixos.org/t/nix-eval-has-terrible-messages-how-to-improve/14339) or [tweet me](https://twitter.com/fmzakari).