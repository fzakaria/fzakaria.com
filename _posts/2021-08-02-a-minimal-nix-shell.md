---
layout: post
title: A minimal nix-shell
date: 2021-08-02 10:35 -0700
excerpt_separator: <!--more-->
---

We are currently using _nix-shell_ to create a reproducible environment for our developers and CI infrastructure. Can we minimize the dependency closure to make our CI jobs faster?

<!--more-->

If you are familiar with _Nix_, undoubtedly you have come across [nix-shell](https://nixos.org/manual/nix/unstable/command-ref/nix-shell.html). Originally designed to help debug a failing deriviation by entering the user into a shell, it has quickly become a beloved way to create reproducible developer environments via [mkShell](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-mkShell).

> mkShell is a special kind of derivation that is only useful when using it combined with nix-shell. It will in fact fail to instantiate when invoked with nix-build.

_mkShell_ however comes with a predefined set of dependencies via the [standard build environment (stdenv)](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv).

Let's look at an _empty mkShell_ and explore the transitive closure.
```nix
let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixos-unstable-2020-09-24";
    url =
      "https://github.com/nixos/nixpkgs/archive/8ecc61c91a596df7d3293603a9c2384190c1b89a.tar.gz";
    sha256 = "0vhajylsmipjkm5v44n2h0pglcmpvk4mkyvxp7qfvkjdxw21dyml";
  }) { };
in nixpkgs.mkShell {
  name = "basic-shell";
  buildInputs = [ ];
  shellHook = ''
  '';
}
``` 

We can even visualize the dependency closure using [graphviz](https://graphviz.org/).
```bash
nix-store --query --graph $(nix-build --no-out-link -A inputDerivation basic-shell.nix) 
```

![basic nix-shell](/assets/images/basic-shell-graph.svg)

There is quite a lot there including GCC and we see the total closure size is **~270MiB**.

```bash
❯ nix path-info --closure-size --human-readable $(nix-build --no-out-link -A inputDerivation basic-shell.nix)

/nix/store/zg33vr1apaq341c9bdfbhlwbp8l22qm6-basic-shell	 268.3M
```

Let's see how much better we can do with [mkShellNoCC](https://github.com/NixOS/nixpkgs/commit/9b3091a94cad63ebd0bd7aafbcfed7c133ef899d).
```nix
let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixos-unstable-2020-09-24";
    url =
      "https://github.com/nixos/nixpkgs/archive/8ecc61c91a596df7d3293603a9c2384190c1b89a.tar.gz";
    sha256 = "0vhajylsmipjkm5v44n2h0pglcmpvk4mkyvxp7qfvkjdxw21dyml";
  }) { };
in nixpkgs.mkShellNoCC {
  name = "shell-no-cc";
  buildInputs = [ ];
  shellHook = ''
  '';
}
```

![nix-shell without compiler](/assets/images/shell-no-cc-graph.svg)

Looks like we are down to **~53MiB**
```bash
❯ nix path-info --closure-size --human-readable $(nix-build --no-out-link -A inputDerivation shell-no-cc.nix).
/nix/store/7afg0p2kyc8qb5a0nv7mlvpf1mbpqkdx-shell-no-cc	  53.5M
```

🕵️ Can we do better?

> Thank you to [siraben](https://github.com/siraben) via Matrix to help share some of the following derivation.

Let's strip everything in **nix-shell** aside from _coreutils_.

```nix
let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixos-unstable-2020-09-24";
    url =
      "https://github.com/nixos/nixpkgs/archive/8ecc61c91a596df7d3293603a9c2384190c1b89a.tar.gz";
    sha256 = "0vhajylsmipjkm5v44n2h0pglcmpvk4mkyvxp7qfvkjdxw21dyml";
  }) { };
  stdenvMinimal = nixpkgs.stdenvNoCC.override {
    cc = null;
    preHook = "";
    allowedRequisites = null;
    initialPath = nixpkgs.lib.filter
      (a: nixpkgs.lib.hasPrefix "coreutils" a.name)
      nixpkgs.stdenvNoCC.initialPath;
    extraNativeBuildInputs = [ ];
  };
  minimalMkShell = nixpkgs.mkShell.override {
    stdenv = stdenvMinimal;
  };
in minimalMkShell {
  name = "minimal-shell";
  buildInputs = [ ];
  shellHook = ''
  '';
}
```

![nix-shell without compiler](/assets/images/shell-minimal-graph.svg)

💥 Looks like it's down to **34MiB**  💥
```bash
❯ nix path-info --closure-size --human-readable $(nix-build --no-out-link -A inputDerivation minimal-shell.nix)
/nix/store/2msg7r8gd7ydwmr33a9nrrjnar7wywxh-minimal-shell	  34.9M
```

Awesome, we've just reduced the closure-size by **~7.7x** !

🧐 Most of that space is due to **glibc** i8n & locales.
```bash
❯ du -h /nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47 | sort -rh | head -n 10
33M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47
17M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/share/i18n
17M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/share
16M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/lib
13M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/share/i18n/locales
8.7M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/lib/gconv
3.4M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/share/i18n/charmaps
1.8M	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/lib/locale
304K	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/share/locale
128K	/nix/store/j5p0j1w27aqdzncpw73k95byvhh5prw2-glibc-2.33-47/libexec
```

Can we do *even* better?

Unfortunately **not at this time**. Removing _coreutils_ from the closure, causes the [basic builder](https://github.com/NixOS/nixpkgs/blob/c464dc811babfe316ed4ab7bbc12351122e69dd7/pkgs/stdenv/generic/builder.sh#L7) to fail since it no longer can find _mkdir_.

```bash
❯ nix-shell minimal-shell.nix --pure
these derivations will be built:
  /nix/store/4gw7ly8hicaw5895370ylmrdhz9l4y9d-stdenv-linux.drv
building '/nix/store/4gw7ly8hicaw5895370ylmrdhz9l4y9d-stdenv-linux.drv'...
/nix/store/dsyj1sp3h8q2wwi8m6z548rvn3bmm3vc-builder.sh: line 7: mkdir: command not found
builder for '/nix/store/4gw7ly8hicaw5895370ylmrdhz9l4y9d-stdenv-linux.drv' failed with exit code 127
```