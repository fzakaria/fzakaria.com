---
layout: post
title: Learn Nix the Fun Way
date: 2024-07-05 17:37 -0700
excerpt_separator: <!--more-->
---

> This is a post inspired by many talks I've given to engineering groups about Nix. You can see an example of one such talk [Why I love Nix, and you should too](https://docs.google.com/presentation/d/e/2PACX-1vT1xW7f8xFwg1g5LYMxumQ-XnFsg96_Vh6eTcb7gh31JBS2PsJpDR-fnUUCKF_IDFi-qNkceUIGjtze/pub?start=false&loop=false&delayms=5000)

I've given _a lot_ of Nix talks. I've given Nix talks internally at companies where I've introduced it, at local meetups and even at NixCon.

Giving a talk about Nix is hard. As engineers I find often we try to explain **why** or **how** Nix works but never show the end result.

Many of the talks I've given start explaining _"Nix developed as part of Eelco's PhD thesis in 2003"_ and immediately eyes roll.

![A meme photo of Picard hearing Nix terminology](/assets/images/picard_nix_hash_meme_50p.jpg)

Let's do it different this time. Let's learn _Nix the fun way_.

<!--more-->

## what-is-my-ip

Let's walk through a single example of a shell script one may write: _what-is-my-ip_

```bash
#! /usr/bin/env bash
curl -s http://httpbin.org/get | \
    jq --raw-output .origin
```

Sure, it's _sort of portable_, if you tell the person running it to have _curl_ and _jq_. What if you relied on a specific version of either though?

Nix **guarantees** portability.

We might leverage _[Nixpkgs' trivial builders](https://ryantm.github.io/nixpkgs/builders/trivial-builders/)_ to turn this into a Nix derivation (i.e. build recipe).

```nix
{
  pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz") { },
}:
pkgs.writeShellScriptBin "what-is-my-ip" ''
  ${pkgs.curl}/bin/curl -s http://httpbin.org/get | \
    ${pkgs.jq}/bin/jq --raw-output .origin
''
```

> 😬 Avoid over-focusing on the fact I just introduced a new language. Just come along for the ride.

Here we are pinning our package to dependencies which come from NixOS/Nixpkgs release branch 24.05.

If we build this, we get the result:

  **/nix/store/lr6wlz2652r35rwzc79samg77l6iqmii-what-is-my-ip**

```bash
❯ /nix/store/lr6wlz2652r35rwzc79samg77l6iqmii-what-is-my-ip/bin/what-is-my-ip 
24.5.113.148
```

Now that this is in Nix and we've modeled our dependencies, we can do _fun_ things like generate graph diagrams to view them (click the image to view larger).

```bash
❯ nix-store --query --graph $(nix-build what-is-my-ip.nix) | \
dot -Tpng -o what-is-my-ip-deps.png
```

[![Image of what-is-my-ip dependencies as a graph](/assets/images/what-is-my-ip-deps.png)](/assets/images/what-is-my-ip-deps.png)

Let's create a _developer environment_ and bring in our new tool.
This is a great way to create developer environment with reproducible tools

```nix
let
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz") {};
  what-is-my-ip = import ./what-is-my-ip.nix {inherit pkgs;};
in
  pkgs.mkShell {
    packages = [what-is-my-ip];
    shellHook = ''
      echo "Hello, Nix!"
    '';
  }
```

```
❯ nix-shell what-is-my-ip-shell.nix
Hello, Nix!

[nix-shell:~/tutorial]$ which what-is-my-ip
/nix/store/lr6wlz2652r35rwzc79samg77l6iqmii-what-is-my-ip/bin/what-is-my-ip
```

🕵️ Notice that the hash **lr6wlz2652r35rwzc79samg77l6iqmii** is _exactly_ the same which we built earlier.

We can now do binary or source deployments 🚀🛠️📦 since we know the full dependency closure of our tool. We simply copy the necessary _/nix/store_ paths to another machine with Nix installed.

```bash
❯ nix copy --to ssh://nixie.tail9f4b5.ts.net \
    $(nix-build what-is-my-ip.nix) --no-check-sigs

❯ ssh nixie.tail9f4b5.ts.net

[fmzakari@nixie:~]$ /nix/store/lr6wlz2652r35rwzc79samg77l6iqmii-what-is-my-ip/bin/what-is-my-ip
98.147.178.19
```

Maybe though you are stuck with Kubernetes or Docker. Let's use Nix to create an OCI compatible image.

```nix
let
  pkgs = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz") {};
  what-is-my-ip = import ./what-is-my-ip.nix {inherit pkgs;};
in
  pkgs.dockerTools.buildImage {
    name = "what-is-my-ip-docker";
    config = {
      Cmd = ["${what-is-my-ip}/bin/what-is-my-ip"];
    };
  }
```

```bash
❯ docker load < $(nix-build what-is-my-ip-docker.nix)
Loaded image: what-is-my-ip-docker:c9g6x30invdq1bjfah3w1aw5w52vkdfn

❯ docker run -it what-is-my-ip-docker:c9g6x30invdq1bjfah3w1aw5w52vkdfn
24.5.113.148
```

Cool! Nix + Docker integration perfectly. The image produced has only the files exactly necessary to run the tool provided, effectively **distroless**.

Finally, let's take the last step and create a reproducible operating system using NixOS to contain only the programs we want.

```nix
let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz";
  pkgs = import nixpkgs {};
  what-is-my-ip = import ./what-is-my-ip.nix {inherit pkgs;};
  nixos = import "${nixpkgs}/nixos" {
    configuration = {
      users.users.alice = {
        isNormalUser = true;
        # enable sudo
        extraGroups = ["wheel"];
        packages = [
          what-is-my-ip
        ];
        initialPassword = "swordfish";
      };

      system.stateVersion = "24.05";
    };
  };
in
  nixos.vm
```

```console
❯ nix-build what-is-my-ip-vm.nix

❯ QEMU_KERNEL_PARAMS=console=ttyS0 ./result/bin/run-nixos-vm -nographic; reset

<<< Welcome to NixOS 24.05pre-git (x86_64) - ttyS0 >>>

Run 'nixos-help' for the NixOS manual.

nixos login: alice
Password: 

[alice@nixos:~]$ which what-is-my-ip
/etc/profiles/per-user/alice/bin/what-is-my-ip

[alice@nixos:~]$ readlink $(which what-is-my-ip)
/nix/store/lr6wlz2652r35rwzc79samg77l6iqmii-what-is-my-ip/bin/what-is-my-ip

[alice@nixos:~]$ what-is-my-ip
24.5.113.148
```

💥 Hash **lr6wlz2652r35rwzc79samg77l6iqmii** present again!

We took a relatively simple script through a variety of applications in the Nix ecosystem: build recipe, shell, docker image and finally NixOS VM.

Hopefully, seeing the _fun things_ you can do with Nix might inspire you to push through the hard parts.

There is a golden pot 💰 at the end of this rainbow 🌈 awaiting you.

**Learn Nix the fun way.**