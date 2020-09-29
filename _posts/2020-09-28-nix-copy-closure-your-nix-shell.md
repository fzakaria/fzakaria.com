---
layout: post
title: nix-copy-closure your nix-shell
date: 2020-09-28 22:01 -0700
excerpt_separator: <!--more-->
---

> This is a synopsis of <https://github.com/NixOS/nix/issues/1985>. I recommend reading it for additional detail. Many thanks to contributors on the issue like [Infinisil](https://github.com/Infinisil) for adding context.

Someone reached out to me over e-mail to discuss my previous post on [caching your nix-shell]({% post_url 2020-08-11-caching-your-nix-shell %}).

_"What I wish to do is to copy a particular development environment (nix-shell)
from A to B, so that I could run nix-shell on server B. Server B is only accessible through SSH and **does not** have Internet access."_

Seems straightforward, so let's investigate. Let's use a very basic _shell.nix_ file.

> Very important we make sure to pin _nixpkgs_. In the example below I do it inline in the Nix expression but you can also use [niv](https://github.com/nmattia/niv) or pin the channel to a particular commit.

```nix
let
  nixpkgs = import (builtins.fetchTarball {
    name = "nixos-unstable-2020-09-24";
    url =
      "https://github.com/nixos/nixpkgs/archive/5aba0fe9766a7201a336249fd6cb76e0d7ba2faf.tar.gz";
    sha256 = "05gawlhizp85agdpw3kpjn41vggdiywbabsbmk76r2dr513188jz";
  }) { };
in with nixpkgs;
with stdenv;
with stdenv.lib;
mkShell {
  name = "example-shell";
  buildInputs = [ hello ];
  shellHook = ''
    export MESSAGE="$(hello)";
  '';
}
```

Let's see it in action:
```bash
❯ nix-shell shell.nix

[nix-shell:~/code/nix/playground]$ echo $MESSAGE
Hello, world!
```

Recently an improvement [#95536](https://github.com/NixOS/nixpkgs/pull/95536) by [Infinisil](https://github.com/Infinisil) made the workflow to discover the _transitive runtime closure_ much simpler than what I had [blogged about]({% post_url 2020-08-11-caching-your-nix-shell %}).

✨ A new attribute for derivations _inputDerivation_ is introduced that is _always buildable_ and whose runtime dependences are it's build dependencies; exactly what we need for nix-shell!

```bash
❯ nix-build --no-out-link shell.nix -A inputDerivation
these derivations will be built:
  /nix/store/bjn4imm9dw7xnxpjrwyrpk0wsy0j7xwh-example-shell.drv
building '/nix/store/bjn4imm9dw7xnxpjrwyrpk0wsy0j7xwh-example-shell.drv'...
/nix/store/rw6i1wk9iv0286xi2b6kpw4ynk4pldyh-example-shell
```

We now have a store path _/nix/store/rw6i1wk9iv0286xi2b6kpw4ynk4pldyh-example-shell_ which we can check the immediate dependencies.

> The below is simply the *immediate* dependencies and not the full transitive closure for brevity.

```bash
❯ nix-store --query --references \
    /nix/store/rw6i1wk9iv0286xi2b6kpw4ynk4pldyh-example-shell

/nix/store/2jysm3dfsgby5sw5jgj43qjrb5v79ms9-bash-4.4-p23
/nix/store/333six1faw9bhccsx9qw5718k6b1wiq2-stdenv-linux
/nix/store/9krlzvny65gdc8s7kpb6lkx8cd02c25b-default-builder.sh
/nix/store/w9yy7v61ipb5rx6i35zq1mvc2iqfmps1-hello-2.10
/nix/store/rw6i1wk9iv0286xi2b6kpw4ynk4pldyh-example-shell
```

I will now copy the _shell.nix_ file to my other machine & copy the transitive closure to it.
```bash
❯ scp shell.nix machine-b:~

❯ nix-copy-closure --to machine-b \
    /nix/store/rw6i1wk9iv0286xi2b6kpw4ynk4pldyh-example-shell
copying 36 paths...
```

Let's hop on _machine B_ and create a network namespace to pretend we do not have Internet access.

> A network namespace is logically another copy of the network stack,
> with its own routes, firewall rules, and network devices.

```bash
❯ ssh machine-b

# since we won't have any Internet access, hydrate the cache
# with our nixpkgs version
❯ nix-prefetch-url --unpack \
https://github.com/nixos/nixpkgs/archive/5aba0fe9766a7201a336249fd6cb76e0d7ba2faf.tar.gz \
--name "nixos-unstable-2020-09-24"

❯ sudo ip netns add nixshell
# enter the namespace
❯ sudo ip netns exec nixshell su $USER -c zsh

# let's confirm we do not have Internet access
❯ ping google.com
ping: google.com: Temporary failure in name resolution
```

Let's fire up our _nix-shell_ and see if it works.

```bash
# don't forget we are within our network namespace
# without access to the Internet
❯ nix-shell shell.nix
bash: cannot set terminal process group (-1): Inappropriate ioctl for device
bash: no job control in this shell

[nix-shell:~]$ echo $MESSAGE
Hello, world!
```

🎆 Huzzah!
We have now copied over our development environment *hermetically* with the help of Nix. This is a great demonstration of the power of Nix & reproducibility.

> An important take-away though is that it's important to make sure *we pin* the exact version of _nixpkgs_ otherwise the _nix-shell_ may calculate different hashes.

Do you have an interesting workflow or innovative use of Nix with development environments? [Let me know about it.](mailto:farid.m.zakaria@gmail.com)