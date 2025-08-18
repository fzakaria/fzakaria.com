---
layout: post
title: Using Nix as a library
date: 2025-08-17 20:13 -0700
---

I have been actively _trying to_ contribute to [CppNix](https://github.com/NixOS/nix) -- mostly because using it brings me joy and it turns out so does contributing. 🤗

Stepping into any new codebase can be overwhelming. You are trying to navigate new nomenclature, coding standards, tooling and overall architecture. Nix is over [20 years old](https://20th.nixos.org/) and has its fair share of warts in a codebase. Knowledge of the codebase is bimodal either being very diffuse or consolidated to a few minds (i.e. [@ericson2314](https://github.com/ericson2314)). Thankfully everyone on the Matrix channel has been extremely welcoming.

I have been actively following [Snix](https://snix.dev/), a modern Rust re-implementation of the components of the Nix package manager. I like the ideals from the project authors of communicating over well-defined API boundaries via separate processes and a library-first type of design. I was wondering however whether we could leverage [CppNix](https://github.com/NixOS/nix) as a library as well. 🤔

_Is there a need to throw the baby out with the bath water?_ 👶

Turns out using Nix as a library is incredibly straightforward!

To start, let's create a `devShell` that will include our necessary packages: `nix` (duh), `meson` (build tool) and `pkg-config`.

<details markdown="1">
<summary markdown="span">flake.nix</summary>

```nix
{
  description = "Example of how to use Nix as a library.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/25.05";
    devshell.url = "github:numtide/devshell";
  };

  outputs = { self, nixpkgs, devshell }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in {
      devShells = lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nix
              meson
              ninja
              pkg-config
              # I am surprised I need this
              # I think this is a bug
              # https://github.com/NixOS/nix/issues/13782
              boost
            ];
          };
        });
    };
}
```
</summary>
</details>

Adding `pkg-config` to our `devShell` will initiate a `buildHook` for any package that contains a `dev` output and set up the necessary environment variables. This will be the mechanism with which our build tool `meson` finds the necessary shared-objects and header files.

```bash
> env | grep PKG_CONFIG_PATH
PKG_CONFIG_PATH=/nix/store/dxar61b2ig87cfdvsylfcnyz6ajls91v-nix-2.28.3-dev/lib/pkgconfig:/nix/store/sgsi5d3z14ygk1f2nlgnlj5w4vl0z8gc-boehm-gc-8.2.8-dev/lib/pkgconfig:/nix/store/l6wng97amh2h2saa5dpvbx5gavjv95r4-nlohmann_json-3.11.3/share/pkgconfig:/nix/store/8kyckzscivn03liyw8fwx93lm3h21z9c-libarchive-3.7.8-dev/lib/pkgconfig:/nix/store/d003f74y8hj2xw9gw480nb54vq99h5r3-attr-2.5.2-dev/lib/pkgconfig:/nix/store/rrgb780yg822kwc779qrxhk60nmj8f6q-acl-2.3.2-dev/lib/pkgconfig:/nix/store/ammv4hfx001g454rn0dlgibj1imn9rkw-boost-1.87.0-dev/lib/pkgconfig
```

We can also run `pkg-config --list` to see that they can be discovered.

```bash
> pkg-config --list-all | head
nix-flake              Nix - Nix Package Manager
nix-store              Nix - Nix Package Manager
nix-main               Nix - Nix Package Manager
nix-cmd                Nix - Nix Package Manager
nix-store-c            Nix - Nix Package Manager
nix-util-test-support  Nix - Nix Package Manager
nix-expr-test-support  Nix - Nix Package Manager
nix-fetchers           Nix - Nix Package Manager
...
```

Let's now create a _trivial_ `meson.build` file. Since we have our `pkg-config` setup, we can declare "system dependencies" that we expect to be present, knowing that we are including these dependencies from our `devShell`.

```meson
project('nix-example', 'cpp',
  version : '0.1',
  default_options : ['warning_level=3', 'cpp_std=c++14'])

deps = [
  dependency('nix-store'),
  dependency('boost'),
]

executable('nix-example',
           'main.cc',
           dependencies: deps,
           install : true)
```

For our sample project I will recreate functionality that is already present in the `nix` command. We will write a function that accepts a `/nix/store` path, resolve its derivation and prints it as JSON.

```cpp
#include <iostream>

#include "nix/main/shared.hh"
#include "nix/store/store-api.hh"
#include "nix/store/derivations.hh"
#include "nix/store/store-dir-config.hh"
#include <nlohmann/json.hpp>

int main(int argc, char **argv) {
    if (argc != 2) {
        std::cerr << "usage: " << argv[0]
                  << " /nix/store/<hash>-<name>"
                  << std::endl;
        return 1;
    }

    nix::initLibStore(true);
    nix::ref<nix::Store> store = nix::openStore();
    std::string s = argv[1];
    nix::StorePath sp = store->parseStorePath(s);
    auto drvPath = sp.isDerivation() ? sp : *store->queryPathInfo(sp)->deriver;
    auto drv = store->readDerivation(drvPath);
    const nix::StoreDirConfig & config = *store;
    auto json = drv.toJSON(config);
    std::cout << json.dump(2) << std::endl;
    return 0;
}
```

We can now build our project and run it! 🔥

```bash
> meson setup build

> meson compile -C build

> ./build/nix-example "/nix/store/bbyp6vkdszn6a14gqnfx8l5j3mhfcnfs-python3-3.12.11" | head
{
  "args": [
    "-e",
    "/nix/store/vj1c3wf9c11a0qs6p3ymfvrnsdgsdcbq-source-stdenv.sh",
    "/nix/store/shkw4qm9qcw5sc5n1k5jznc83ny02r39-default-builder.sh"
  ],
  "builder": "/nix/store/cfqbabpc7xwg8akbcchqbq3cai6qq2vs-bash-5.2p37/bin/bash",
...
```

That feels pretty cool!
Lots of projects end up augmenting Nix by wrapping it with _fancy bash scripts_, however we can just as easily leverage it as a library and write native-first code.

> Learning the necessary functions to call is a little obtuse however I was able to reason through the necessary APIs by looking at unit-tests in the repository.

What idea do you want to leverage Nix for but maybe put off since you thought doing it on top of Nix would be too hacky?

Special thanks to [@xokdvium](https://github.com/xokdvium) who helped me through some learnings on `meson` and how to leverage Nix as a library. 🙇