---
layout: post
title: Nix remote building with Yubikey
date: 2024-07-10 18:46 -0700
excerpt_separator: <!--more-->
---

There isn't that much Nix documentation for remote building with Nix.

I'm leaving my tiny module that I'm using to enable my Framework Laptop running NixOS to perform remote builds using the [Nix Community builders](https://nix-community.org/community-builder/), specifically that I use a Yubikey key as my SSH private key.

> Actually some of the best documentation is courtesy of [nixbuild](https://docs.nixbuild.net/remote-builds/).

<!--more-->

### Prerequisites

1. Using a Yubikey for SSH access

    You can get your public key using _ssh-add -L_

    ```console
    ❯ ssh-add -L
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDruWlzuyOXV0Ltjv0vVoCSkf4/ic4ET4of6NTqLWfvw/wpNFDr3SXRDAftOFcyoKp0ls0z6xy3CH99pUNmVnU19nwPdPfY93FJHaVDmS3VUzhco+e+bd1Azds5bltg06H+2vuHFcFMA28Y1o5h6ISlVY45bUzhKnW6+9whwECGBQo5KSvSW0D50eP557DD1KZlWUuJrcno65iQUz6dZ+R5cwfoTRhCvh4ltzJ6Fel6RuHPzG3u56lHM+upsF1REljHsNGI6XF3bcRuIoSssvaT0ZzVJQz/YnI1+wGZDNSKJI7WE+xmhfhcGLDzVaxNkLuJLMv/goTcDsDBb1BVw0YF YubiKey #8531869 PIV Slot 9a
    ```

2. Use [Filippo Valsorda](https://filippo.io) excellent [Yubikey SSH agent](https://github.com/FiloSottile/yubikey-agent)

    ```nix
    yubikey-agent.enable = true;
    ```

### Nix Module

The _surprising_ (and a bit ugly unfortunately) part is to include a default _ssh_config_ for the root user; this is necessary because on NixOS the nix builds are done by the daemon which is running as _root_.

In order to give the _root_ user access to the Yubikey we pass in the `SSH_AUTH_SOCK` value which is _/run/user/1000/yubikey-agent/yubikey-agent.sock_.

```nix
{config, ...}: {
  programs.ssh = {
    # Community builder for Linux
    knownHosts."build-box.nix-community.org".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElIQ54qAy7Dh63rBudYKdbzJHrrbrrMXLYl7Pkmk88H";

    # nix remote builders don't work with Yubikey and on NixOS the builder runs as root
    # so what we do is tell it the user to login as but give it the identity agent to connect
    # to for my (fmzakari) user. A bit of a hack but....not sure a better alternative.
    extraConfig = ''
      Host build-box.nix-community.org
        IdentityAgent /run/user/1000/yubikey-agent/yubikey-agent.sock
    '';
  };

  nix = {
    distributedBuilds = true;

    # Nix will instruct remote build machines to use their own binary substitutes if available.
    # In practical terms, this means that remote hosts will fetch as many build dependencies as
    # possible from their own substitutes (e.g, from cache.nixos.org), instead of waiting for this
    # host to upload them all. This can drastically reduce build times if the network connection
    # between this computer and the remote build host is slow.
    settings.builders-use-substitutes = true;

    buildMachines = [
      {
        protocol = "ssh-ng";
        hostName = "build-box.nix-community.org";
        maxJobs = 12;
        systems = ["x86_64-linux"];
        supportedFeatures = [
          "benchmark"
          "big-parallel"
          "kvm"
          "nixos-test"
        ];
        sshUser = "fmzakari";
      }
    ];
  };
}
```

If you think this Nix code can be improved, **please let me know**.