---
layout: post
title: NixOS; what's in a rebuild?
date: 2020-09-06 08:59 -0700
excerpt_separator: <!--more-->
---

I have been using Nix but mainly through [home-manager](https://github.com/rycee/home-manager) on my Debian system; finally I made the plunge into running NixOS on an AWS server for my _side-projects_.

There's a lot of information on how to configure & setup an already created NixOS machine but not much advice for workflows, best practices & multiple machines.

Here I'll document what I found useful and pulling back the veil on some of the NixOS tooling.

> Feel free to check my Nix repository for home-manager & NixOS
> <https://github.com/fzakaria/nix-home>

<!--more-->

### configuration.nix

NixOS documentation outlines that the entry-point to the NixOS setup is a file _configuration.nix_; why?

Well, NixOS configuration is primarily driven by **nixos-rebuild**; let's take a look at the [source](https://github.com/NixOS/nixpkgs/blob/02590c96209d374d7f720293fcb8337e17104bc9/nixos/modules/installer/tools/nixos-rebuild.sh#L419-L421).

One of the first things it does when running `switch` is the following.
```bash
...
pathToConfig="$(nixBuild '<nixpkgs/nixos>' \
--no-out-link -A system "${extraBuildFlags[@]}")"
...
```

Interesting so it's building a _system_ & fetching the _/nix/store/_ path for it; what's that?

You can find the _system_ attribute in [nixos/default.nix](https://github.com/NixOS/nixpkgs/blob/ce6bc4dbc7821bc271e6ae5d25b57075c4ce877f/nixos/default.nix#L33).

```nix
{ configuration ? import ./lib/from-env.nix "NIXOS_CONFIG" <nixos-config>
, system ? builtins.currentSystem
}: {
  ...
  system = eval.config.system.build.toplevel;
  ...
}
```

This is in fact the **entry-point** for NixOS; and we can see here that the _configuration_ defaults to <nixos-config> if not given.

> On NixOS _\<nixos-config\>_ is set in _NIX_PATH_ to `nixos-config=/etc/nixos/configuration.nix`

Let's write the most basic _configuration.nix_
```nix
{...}:{
  # We need no bootloader, because we aren't booting yet
  boot.loader.grub.enable = false;

  fileSystems = {
     "/".label = "nixos-root";
  };
}
```

`$ nix-build -I nixos-config=./configuration.nix --no-out-link '<nixpkgs/nixos>' -A system`

We can also inline and build the _system_.

```nix
let nixos = import <nixpkgs/nixos> { configuration = {
      # We need no bootloader, because we aren't booting yet
      boot.loader.grub.enable = false;

      fileSystems = {
         "/".label = "nixos-root";
      };
    };
};
in nixos.system
```

The output will be the _/nix/store_ system closure; this is a _somewhat_ typical Linux filesystem including _/etc_.


> comment from [infinisil](https://github.com/Infinisil): _/bin_ & _/lib_ are purposefully left out to avoid programs depending on them; forcing purer Nix builds. They can be found nested within the _/sw_ directory.

```
$ tree /nix/store/x0nbdy16myi7y72vy02nw8hywr3fnv7d-nixos-system-nixos-20.09pre237891.f9eba87bf03

/nix/store/x0nbdy16myi7y72vy02nw8hywr3fnv7d-nixos-system-nixos-20.09pre237891.f9eba87bf03
├── activate
├── append-initrd-secrets -> /nix/store/vy8lxijna11za631r54gb9gl099qn7by-append-initrd-secrets/bin/append-initrd-secrets
├── bin
│   └── switch-to-configuration
├── configuration-name
├── etc -> /nix/store/cbg97bmc5jhid2hn0xxgs5ggd75xcibb-etc/etc
├── extra-dependencies
├── firmware -> /nix/store/76n4kcg49px9wqha2d9lpfsj5cccwj0h-firmware/lib/firmware
├── init
...
```

Cool! _nixos-rebuild_ will change _/run/current-system_ pointing to this entry afterwards.

### vm.nix

A little fun _tip_; there is a top level attribute alongside _system_ that can make building a virtual machine very easy.

We simply need to change the attribute to **nixos.vm**
```nix
nixos = import <nixpkgs/nixos> { configuration = import ./configuration.nix };
in nixos.vm
```

You can then start the **vm** by running `./result/bin/run-nixos-vm`.

> The virtual machine setup will override the hardware configuration to setup sane defaults for QEMU

I tend to keep a _vm.nix_ alongside each of my machine configurations to test quickly in an isolated environment.

If you prefer a _nix-build_ one-liner rather the explicit file above; you can do `nix-build '<nixpkgs/nixos>' -A vm -I nixos-config=./configuration.nix` which accomplishes the same thing.