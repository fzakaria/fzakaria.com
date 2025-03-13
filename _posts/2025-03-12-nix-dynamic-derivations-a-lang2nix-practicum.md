---
layout: post
title: 'Nix Dynamic Derivations: A lang2nix practicum'
date: 2025-03-12 20:55 -0700
---

> ℹ️ This is the third blog post discussing _dynamic-derivations_ in Nix. Checkout the [first]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}) and [second]({% post_url 2025-03-11-nix-dynamic-derivations-a-practical-application %}) posts if you want more information.

I will admit it. I am going a bit crazy after having learnt about _dynamic-derivations_. 😵‍💫

It's like learning about how to write your first `mkDerivation` and suddenly you realize everything can now be converted to Nix.

In my first post, [An early look at Nix Dynamic Derivations]({% post_url 2025-03-10-an-early-look-at-nix-dynamic-derivations %}), I mentioned that _dynamic-derivations_ could be used to even replace the slough of `lang2nix` tooling that exists in the ecosystem, especially those that use [import from derivations]({% post_url 2020-10-20-nix-parallelism-import-from-derivation %})(IFD).

I cooked up a demonstration of how simple it can be with [NpmNix](https://github.com/fzakaria/NpmNix). 👨‍🍳

> Please checkout [https://github.com/fzakaria/NpmNix](https://github.com/fzakaria/NpmNix) and contribute any improvements, bug fixes or clarifications. The repository is meant to be an example for others to imitate. Contributions are always welcome.

Why do I want to do this? Why did I pick the Node language ecosystem?

[`buildNpmPackage`](https://nixos.org/manual/nixpkgs/stable/#javascript-buildNpmPackage) already can natively parse package the `package-lock.json` file in _pure Nix_ and does not rely on IFD, **but**, doing so in the Nix evaluator can be pretty slow for huge files and affect evaluation time.

The lock file is very simple and has all the information ready to go, so let's see what it takes to translate it to a _dynamic-derivation_! 🥸

Once again before we begin, if you want to play with it it's important you use [nix@d904921](https://github.com/NixOS/nix/commit/d904921eecbc17662fef67e8162bd3c7d1a54ce0). Additionally, you need to enable `experimental-features = ["nix-command" "dynamic-derivations" "ca-derivations" "recursive-nix"]`. Here, there be dragons 🐲.

We can start off with a simple `package.json` that has 3 dependencies.

```json
{
    "name": "npmnix-demo",
    "version": "1.0.0",
    "dependencies": {
        "is-number": "^7.0.0",
        "is-odd": "3.0.1",
        "left-pad": "1.3.0"
    }
}
```

This `package.json` produces the following `package-lock.json` file.

```json
{
    "name": "npmnix-demo",
    "version": "1.0.0",
    "lockfileVersion": 3,
    "requires": true,
    "packages": {
        "node_modules/is-number": {
            "version": "7.0.0",
            "resolved": "https://registry.npmjs.org/is-number/-/is-number-7.0.0.tgz",
            "integrity": "sha512-41Cifkg6e8TylSpdtTpeLVMqvSBEVzTttHvERD741+pnZ8ANv0004MRL43QKPDlK9cGvNp6NZWZUBlbGXYxxng==",
            "license": "MIT",
            "engines": {
                "node": ">=0.12.0"
            }
        },
        "node_modules/is-odd": { ... },
        "node_modules/is-odd/node_modules/is-number": { ... },
        "node_modules/left-pad": { ... }
    }
}
```

[NpmNix](https://github.com/fzakaria/NpmNix) includes a very simple Golang parser, [parser.go](https://github.com/fzakaria/MakeNix/blob/main/parser/parser.go) (~70 lines of code), that parses the `package-lock.json` and generates the complete Nix expression.

Here is a sample of the Nix expression generated.

```nix
{ pkgs }:
let dependencies = [
(pkgs.stdenv.mkDerivation {
    pname = "left-pad";
    version = "1.3.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz";
      hash = "sha512-XI5MPzVNApjAyhQzphX8BkmKsKUxD4LdyK24iZeQGinBN9yTQT3bFlCBy/aVx2HrNcqQGsdot8ghrjyrvMCoEA==";
    };
    installPhase = ''
      mkdir -p $out/left-pad
      cp -r * $out/left-pad
    '';
  })
  (pkgs.stdenv.mkDerivation {
    pname = "is-odd/node_modules/is-number";
    version = "6.0.0";
    ...
  })
  (pkgs.stdenv.mkDerivation {
    pname = "is-number";
    version = "7.0.0";
    ...
  })
  (pkgs.stdenv.mkDerivation {
    pname = "is-odd";
    version = "3.0.1";
    ..
  })
];
in
pkgs.symlinkJoin {
  name = "node_modules";
  paths = dependencies;
}
```

What I like about this Nix expression is that every `node_module` is a separate derivation which are symlinked at the end. That means if only a single package gets updated, we can avoid downloading the other packages again. This is in contrast to solutions that download all the packages in a single derivation.

After the Nix expression is generated, we need to only `nix-instantiate` it and set the `$out` of the dynamic-derivation to this path.

**That's it.**

We just got the `node_modules` for our `package-lock.json` in a manner that doesn't cost us evaluation time, either due to IFD or from doing the evaluation in Nix.

What's nice is that we retain the developer experience however. If our packages ever change, we don't have to update a `npmDepHash`, `cargoHash` or whatnot.

```console
# use `nix run` to bind mount our temporary store to /nix/store
> nix run nixpkgs#fish --store /tmp/dyn-drvs

# we still have to specify the `--store` to avoid the store-daemon
> nix build -f default.nix --store /tmp/dyn-drvs -L
/nix/store/x9l8m94a2g6zkszab11na5l7c18xv0j1-node_modules

> ln -s /nix/store/x9l8m94a2g6zkszab11na5l7c18xv0j1-node_modules node_modules

> npm ls
npmnix-demo@1.0.0
├── is-number@7.0.0 -> /nix/store/x9l8m94a2g6zkszab11na5l7c18xv0j1-node_modules/is-number
├── is-odd@3.0.1 -> /nix/store/x9l8m94a2g6zkszab11na5l7c18xv0j1-node_modules/is-odd
└── left-pad@1.3.0 -> /nix/store/x9l8m94a2g6zkszab11na5l7c18xv0j1-node_modules/left-pad
```

As a reminder, we could have generated that Nix expression above earlier **or** in the case of `package-lock.json` handled it in pure Nix, but it has the downsides mentioned earlier such as potentially needing IFD or unecessary evaluation time.

The derivation that puts this all together is rather simple.

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
      name = "node_modules.drv";
      outputHashMode = "text";
      outputHashAlgo = "sha256";
      requiredSystemFeatures = ["recursive-nix"];

      src = fs.toSource {
        root = ./.;
        fileset = fs.unions [
          ./parser
          ./package-lock.json
        ];
      };

      buildInputs = [nix go];

      buildPhase = ''   
        go run parser/parser.go package-lock.json > derivation.nix
      '';

      installPhase = ''
        cp $(nix-instantiate derivation.nix --arg pkgs 'import ${pkgs.path} {}') $out
      '';
    }).outPath "out"
```

It runs our parser over the `package-lock.json`, emits the Nix expression, `nix-instantiate`, and profit. 🤑 

As an experiment now, we can go ahead and change any of our dependencies.

```patch
--- a/package.json
+++ b/package.json
@@ -3,7 +3,7 @@
     "version": "1.0.0",
     "dependencies": {
         "is-number": "^7.0.0",
-        "is-odd": "3.0.1",
+        "is-odd": "3.0.0",
         "left-pad": "1.3.0"
     }
 }
```

We then run `npm i --package-lock-only` to update our `package-lock.json` file.

If we re-run `nix build` we can notice that only `is-odd` gets rebuilt. 💥

_For demonstrative purposes, I trimmed some of the output below_.

```console
nix build -f default.nix --store /tmp/dyn-drvs -L --print-out-paths
node_modules.drv> Running phase: unpackPhase
node_modules.drv> unpacking source archive /nix/store/b6kw6a866rw1daa0kviczq59sqjy8hsh-source
node_modules.drv> no configure script, doing nothing
node_modules.drv> Running phase: buildPhase
is-odd> 
is-odd> trying https://registry.npmjs.org/is-odd/-/is-odd-3.0.0.tgz
is-odd>   % Total    % Received % Xferd  Average Speed   Time    
is-odd> Running phase: unpackPhase
is-odd> unpacking source archive /nix/store/riq3g1pj0fjrj8vpddh5wdpjgjzwzrgm-is-odd-3.0.0.tgz
is-odd> source root is package
is-odd> setting SOURCE_DATE_EPOCH to timestamp 499162500 of file package/package.json
is-odd> Running phase: buildPhase
is-odd> no Makefile or custom buildPhase, doing nothing
is-odd> Running phase: installPhase
is-odd> Running phase: fixupPhase
/nix/store/3fiqwa1vw7r8dsdzydadmyfs3q9ym2h9-node_modules

> ln -s /nix/store/3fiqwa1vw7r8dsdzydadmyfs3q9ym2h9-node_modules node_modules

> npm ls
npmnix-demo@1.0.0
├── is-number@7.0.0 -> /nix/store/3fiqwa1vw7r8dsdzydadmyfs3q9ym2h9-node_modules/is-number
├── is-odd@3.0.0 -> /nix/store/3fiqwa1vw7r8dsdzydadmyfs3q9ym2h9-node_modules/is-odd
└── left-pad@1.3.0 -> /nix/store/3fiqwa1vw7r8dsdzydadmyfs3q9ym2h9-node_modules/left-pad
```

Wow! Not too bad. 😎 That was a relatively straightforward way to replace potential _import-from-derivation_ or performing a lot of this creation at evaluation time.

Checkout [NpmNix](https://github.com/fzakaria/NpmNix) and play with it yourself. What other languages can we apply this to?

I continue to amazed at how simple _dynamic-derivations_ makes some tasks in Nix and improves the user experience. 🎯