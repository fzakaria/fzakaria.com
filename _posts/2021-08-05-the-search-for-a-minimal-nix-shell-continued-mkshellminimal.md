---
layout: post
title: The search for a minimal nix-shell continued; mkShellMinimal
date: 2021-08-05 18:53 -0700
excerpt_separator: <!--more-->
---

> “The simplest things are often the truest.” - Richard Bach, 1936.

Earlier [I wrote about]({% post_url 2021-08-02-a-minimal-nix-shell %}) trying to get a minimal nix-shell. The goal and challenge of the post was about reducing the dependency closure size of the shell.

> I was asked what's the point in trying to minimize the closure size ?
> 
> We are using _nix-shell_ in our CI infrastructure and every CI job hydrates it's own
> _/nix/store_ from scratch. Reducing the dependency closure size would mean faster CI runs. 🏎️

The post finished with a question, _"Can we do better ?"_, to which I answered _"No, not at this time."_.

I'd like to introduce [mkShellMinimal](https://github.com/NixOS/nixpkgs/pull/132617) that does better 🎊

<!--more-->

Let's first look at a similar basic example, a _nix-shell_ without any user declared dependencies.
```nix
let
  nixpkgs = import <nixpkgs> { };
in
with nixpkgs;
mkShellMinimal {
  name = "my-minimal-shell";

  # No user defined dependencies
  packages = [ ];

  # You can do typical environment variable setting
  FOO = "bar";
}
```

If we check the closure size of our shell, we see that it's only **1.4KiB** 😮

```bash
❯ nix path-info -rSsh $(nix-build shell.nix) 
This derivation is not meant to be built, unless you want to capture the dependency closure.

/nix/store/8ka1hnlf06z3h2rpd00b4d9w5yxh0n39-setup        	 376.0 	 376.0
/nix/store/nprykggfqhdkn4r5lxxknjvlqc4qm1yl-builder.sh   	 280.0 	 280.0
/nix/store/xd8d72ccrxhaz3sxlmiqjnn1z0zwfhm8-my-minimal-shell	 744.0 	   1.4K
```

That's nearly a **200_000x** improvement. 😱

> To facilitate a simpler way to introspect or upload the transitive closure of the shell, I've allowed it to be
> buildable.

I've greatly simplified the feature set of what you can do with _mkShellMinimal_ as opposed to _mkShell_.

For instance the only way to declare dependencies is with the _packages_ keyword. There is no dependency even on [coreutils](https://www.gnu.org/software/coreutils/) and one could replace it with [busybox](https://www.busybox.net/).

> Thank you to [jappeace](https://github.com/jappeace) for inspiring the pursuit.

### Challenges & Trivia

The rest of the post will document what it took to deliver this minimal shell. It was in fact not as trivial as it
might have originally seemed.

> If you are only interested in having a minimal _nix-shell_ you can stop reading here 📖.

#### Tight coupling with stdenv

In the pursuit of trying to remove [stdenv](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv) was somewhat _annoying_. I discovered that the _nix-shell_ implementation has some [tight coupling](https://github.com/NixOS/nix/blob/94ec9e47030c2a7280503d338f0dca7ad92811f5/src/nix-build/nix-build.cc#L494)(`source $stdenv/setup`) with it by expecting a setup file provided by stdenv; this needed to be _hacked in_ 🐱‍💻.

```c++
std::string rc = fmt(
        R"(_nix_shell_clean_tmpdir() { rm -rf %1%; }; )"s +
        (keepTmp ?
            "trap _nix_shell_clean_tmpdir EXIT; "
            "exitHooks+=(_nix_shell_clean_tmpdir); "
            "failureHooks+=(_nix_shell_clean_tmpdir); ":
            "_nix_shell_clean_tmpdir; ") +
        (pure ? "" : "[ -n \"$PS1\" ] && [ -e ~/.bashrc ] && source ~/.bashrc;") +
        "%2%"
        "dontAddDisableDepTrack=1;\n"
        + structuredAttrsRC +
        "\n[ -e $stdenv/setup ] && source $stdenv/setup; "
        "%3%"
        "PATH=%4%:\"$PATH\"; "
        "SHELL=%5%; "
```

#### How is Bash as a dependency gone?

Well since the purpose behind _nix-shell shell.nix_ is for a developer friendly environment (as opposed to debugging a failing deriviation), I have _mkShellMinimal_ rely on _/bin/sh_ which is _nearly_ required for POSIX compliance.

> In fact, even NixOS [adds a symlink](https://github.com/NixOS/nixpkgs/blame/982fe76fa696743f7ddcfea68a54ed3c1a9ee4ec/nixos/modules/config/shells-environment.nix#L191-L198) for /bin/sh.

This works well for this case since the builder used for this shell is exceptionally simple.

```nix
 builder = writeScript "builder.sh" ''
    #!/bin/sh
    echo
    echo "This derivation is not meant to be built, unless you want to capture the dependency closure.";
    echo
    export > $out
  '';
```

#### But my nix-shell still drops me in Bash? Huh?

This is probably one of the most _bizarre_ aspects of _nix-shell_ and Nix; a system which tries to have reproducibility at it's core.

_nix-shell_ by default, [will start up Bash](https://github.com/NixOS/nix/blob/94ec9e47030c2a7280503d338f0dca7ad92811f5/src/nix-build/nix-build.cc#L365) from whatever is referenced via your _nixpkgs_ channel. 😳

```c++
auto expr = state->parseExprFromString("(import <nixpkgs> {}).bashInteractive", absPath("."));
```

This means you could, _in theory_, write a _shellHook_ in your mkShell that fails on another user's machine since their _nixpkgs_ channel references a wildly different major version of Bash. 🤯

[I would like to see](https://github.com/NixOS/nix/issues/5098) _nix-shell_ use a value specified in the derivation itself, to identify the version of Bash to use. That would make it completely hermetic.

#### Undocumented requirements to have `nix-shell --pure` work

I was struggling to get `nix-shell --pure` to enforce purity and not persist my _$PATH_. [I would have expected](https://github.com/NixOS/nix/issues/5092) this to a feature of the Nix CLI itself and not one of underlying derivation.

Turns out that is not the case. 

_nix-shell_ requires that the _builder_ **unconditionally** clears the _$PATH_ always at the start. 