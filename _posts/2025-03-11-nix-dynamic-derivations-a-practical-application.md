---
layout: post
title: 'Nix Dynamic Derivations: A practical application'
date: 2025-03-11 20:05 -0700
---

> ℹ️ This is the second blog post discussing _dynamic-derivations_ in Nix. Checkout the first part [An early look at Nix Dynamic Derivations]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}) if you want a primer on the experimental feature.

I'm still in love with the experimental feature _dynamic-derivations_ in Nix 🥰, but following my [earlier post]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}) I had read comments from readers that the potential was still _unclear_.

This makes total sense. Nix is already quite a complex tool, ecosystem and language. The addition of something like _dynamic-derivations_ muddles the capability to understand the potential it offers.

At the end of the last post, I echoed John Ericson's ([@ericson2314](https://github.com/ericson2314)) call to action for others in the community to begin to tinker with the feature. 

In the spirit of that request, I have put together a practical demonstration of what can be accomplished with _dynamic-derivations_ in the tool [MakeNix](https://github.com/fzakaria/MakeNix) 💥🏃‍♂️🔥

> Please checkout [https://github.com/fzakaria/MakeNix](https://github.com/fzakaria/MakeNix) and contribute any improvements, bug fixes or clarifications. The repository is meant to be an example for others to imitate. Contributions are always welcome.

Once again before we begin, if you want to play with it it's important you use [nix@d904921](https://github.com/NixOS/nix/commit/d904921eecbc17662fef67e8162bd3c7d1a54ce0). Additionally, you need to enable `experimental-features = ["nix-command" "dynamic-derivations" "ca-derivations" "recursive-nix"]`. Here, there be dragons 🐲.

Here we have a rather simple C project that produces a binary that emits `"Hello World"`

```console
> tree
├── Makefile
└── src
    ├── hello.c
    ├── hello.h
    ├── main.c
    ├── world.c
    └── world.h
> make all

> ./main
Hello, World!
```

We _could_ write a typical Nix derivation via `mkDerivation` that calls `make` and for this relatively small example it would be fine. However for larger projects, everytime we change a tiny bit of our code we must rebuild _the whole thing_ from scratch.  We don't get to leverage all the prior object files that had been built.

That's a bummer 🙁. Wouldn't it be great if each object file (i.e. `hello.o`) was created in their own derivation?

We could do that ahead of time by writing a tool to create a bunch of tiny `mkDerivation` but everytime we change a dependency in our graph (i.e. add or remove a source file), we have to re-run the tool. That's a bit of a bummer on the development loop.

If those generated Nix files were not committed to the repository and we wanted to add this package to [nixpkgs](https://github.com/NixOS/nixpkgs), we'd need to also do a full `nix build` within the derivation itself via _recursive-nix_. 😨

_Dynamic-derivations_ seeks to solve this callenge by having derivations **create other derivations** without having to execute a `nix build` recursively. Nix will realize the output of one derivation is another derivation and build it as well. 🤯

Let's return to our C
/C++ project. [GCC](https://gcc.gnu.org/) & [Clang](https://clang.llvm.org/) support an argument `-MM` which runs only the preprocessor and emits depfiles `.d` that contain Makefile targets with the dependency targets between files.

```makefile
main.o: src/main.c src/hello.h src/world.h
```

The idea behind [MakeNix](https://github.com/fzakaria/MakeNix) is to generate these depfiles, parse them and create the necessary `mkDerivation` **all at build time**.

[MakeNix](https://github.com/fzakaria/MakeNix) includes a very simple Golang parser, [parser.go](https://github.com/fzakaria/MakeNix/blob/main/parser/parser.go) (~70 lines of code), that parses the depfiles and generates the complete Nix expression.

Here is a sample of the Nix expression generated.

```nix
{ pkgs }:
let fs = pkgs.lib.fileset;
  hello.o = pkgs.stdenvNoCC.mkDerivation {
    name = "hello.o";
    src = fs.toSource {
      root = ./src;
      fileset = fs.unions [
        ./src/hello.c
        ./src/hello.h
      ];
    };
    nativeBuildInputs = [ pkgs.gcc ];
    buildPhase = ''
      gcc -c hello.c -o hello.o
    '';
    installPhase = ''
      cp hello.o $out
    '';
  };
  main.o = ...;
  world.o = ...;
in pkgs.runCommand "result" {
  nativeBuildInputs = [ pkgs.gcc ];
} ''
  gcc -o main ${hello.o} ${main.o} ${world.o}
  cp main $out
''
```

After the Nix expression is generated, we need to only `nix-instantiate` it and set the `$out` of the dynamic-derivation to this path.

**That's it.**

We just got incremental Nix C/C++ builds automatically from the dependency information provided by the compiler. 🔥

```bash
# use `nix run` to bind mount our temporary store to /nix/store
> nix run nixpkgs#fish --store /tmp/dyn-drvs

# we still have to specify the `--store` to avoid the store-daemon
> nix build -f default.nix --store /tmp/dyn-drvs --print-out-paths -L
/nix/store/v4hkwn8y4m083gsap6523c0m5r985ygr-result

> ./result
Hello, World!

> nix derivation show /nix/store/v4hkwn8y4m083gsap6523c0m5r985ygr-result \
    --store /tmp/dyn-drvs/ | jq -r '.[].inputDrvs | keys'
[
  "/nix/store/2hm681pgbj7wwg0x0a6wyw0m98rvg0q4-gcc-wrapper-13.3.0.drv",
  "/nix/store/6inhnnprqd57qw5dv5sqxmc9ywiwi5yf-world.o.drv",
  "/nix/store/7k0msqyp2dm021sdj0qjgpkzff8xhqzr-bash-5.2p37.drv",
  "/nix/store/fwvwwnpi04yzpcjcnl6yn3mg82vvp45k-hello.o.drv",
  "/nix/store/ki70bzsbzapc9wihavq67irlr5zxp90q-main.o.drv",
  "/nix/store/ycj0m56p8b0rv9v78mggfa6xhm31rww3-stdenv-linux.drv"
]
```

As a reminder, we could have generated that Nix expression above earlier **but** if we embedded it within another Nix expression we need to run `nix build` recursively.

Can't not repeat this enough, with _dynamic-derivations_ **there is no recursive** `nix build`.

The derivation that puts this all together is rather simple.

It does exactly what we set out to accomplish: generate depfiles, parse depfiles, emit dynamic Nix expression, `nix-instantiate`, profit. 🤑

> Please refer to my [earlier post]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}) on understanding this from the ground up. The interesting thing to notice here is that our output name for this derivation is in fact a derivation.

```nix
let
  pkgs =
    import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/5ef6c425980847c78a80d759abc476e941a9bf42.tar.gz") {
    };
  fs = pkgs.lib.fileset;
in
  with pkgs;
    builtins.outputOf
    (stdenvNoCC.mkDerivation {
      name = "result.drv";
      outputHashMode = "text";
      outputHashAlgo = "sha256";
      requiredSystemFeatures = ["recursive-nix"];

      src = fs.toSource {
        root = ./.;
        fileset = fs.unions [
          (fs.fromSource (lib.sources.sourceByRegex ./src [ ".*\.c$" ]))
          (fs.fromSource (lib.sources.sourceByRegex ./src [ ".*\.h$" ]))
          ./parser
          ./Makefile
        ];
      };

      buildInputs = [nix go gcc];

      buildPhase = ''
        make deps
        
        go run parser/parser.go > derivation.nix
      '';

      installPhase = ''
        cp $(nix-instantiate derivation.nix --arg pkgs 'import ${pkgs.path} {}') $out
      '';
    }).outPath "out"
```

As an experiment now, we can go ahead and change any of our source files.

```patch
--- a/src/hello.c
+++ b/src/hello.c
@@ -2,5 +2,5 @@
 #include "hello.h"
 
 void hello() {
-    printf("Hello, ");
+    printf("Goodbye, ");
 }
```

If we re-run `nix build` we can notice that only `hello.o` gets rebuilt. 💥

_For demonstrative purposes, I trimmed some of the output below_.

```console
> nix build -f default.nix --store /tmp/dyn-drvs -print-out-paths -L
result.drv> Running phase: unpackPhase
result.drv> source root is source
result.drv> Running phase: patchPhase
result.drv> Running phase: configurePhase
result.drv> no configure script, doing nothing
result.drv> Running phase: buildPhase
result.drv> gcc -MM src/hello.c > src/hello.d
result.drv> gcc -MM src/main.c > src/main.d
result.drv> gcc -MM src/world.c > src/world.d
result.drv> Dependencies generated
hello.o> Running phase: unpackPhase
hello.o> source root is source
hello.o> Running phase: patchPhase
hello.o> Running phase: configurePhase
hello.o> no configure script, doing nothing
hello.o> Running phase: buildPhase
hello.o> Running phase: installPhase
hello.o> Running phase: fixupPhase
/nix/store/flqzpyhf6by2rjizr3px3nmbgqvpj0vv-result

> ./result 
Goodbye, World!
```

Not too bad. 😎 That was a relatively quick to get an incremental build in Nix working via _dynamic-derivations_.

Checkout [MakeNix](https://github.com/fzakaria/MakeNix) and play with it yourself. What other languages can we apply this to?

Thank you again to John who answered some questions. 🙇