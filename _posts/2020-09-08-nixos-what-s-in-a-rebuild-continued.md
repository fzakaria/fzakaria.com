---
layout: post
title: NixOS; what's in a rebuild? Continued.
date: 2020-09-08 16:17 -0700
excerpt_separator: <!--more-->
---

> This is _part 2_ of a series on **nixos-rebuild**. You can read part 1 [here]({% post_url 2020-09-06-nixos-what-s-in-a-rebuild %}).

We previously broke down that one of the first tasks done by _nixos-rebuild_ is to build the _system_ attribute.

What happens next for **switch** ? Let's go back to the [source](https://github.com/NixOS/nixpkgs/blob/02590c96209d374d7f720293fcb8337e17104bc9/nixos/modules/installer/tools/nixos-rebuild.sh#L428-L429).

<!--more-->

```bash
...
copyToTarget "$pathToConfig"
targetHostCmd nix-env -p "$profile" --set "$pathToConfig"
...
```

It will attempt to copy the _system_ _/nix/store_ path if a target host is set & also change the profile (_/nix/var/nix/profiles/system_) to the new _system_.

```bash
❯ tree /nix/var/nix/profiles/
/nix/var/nix/profiles/
...
├── system -> system-18-link
...
├── system-8-link -> /nix/store/3n0563wd5c0jxppaaj2y4nlw2ybvikl3-nixos-system-unnamed-20.03post-git
└── system-9-link -> /nix/store/9y3gp7llvinvra8qcx9n52s0kpvvyzh8-nixos-system-unnamed-20.03post-git
```

Finally the _system_ is activated; by calling the generated _switch-to-configuration_ script created within the system store entry.
```bash
...
if ! targetHostCmd $pathToConfig/bin/switch-to-configuration "$action";
...
```
```bash
❯ tree /nix/store/rpfin018i0s2bdvmsikkrdvd0wvwg287-nixos-system-altaria-20.03post-git/bin
/nix/store/rpfin018i0s2bdvmsikkrdvd0wvwg287-nixos-system-altaria-20.03post-git/bin
└── switch-to-configuration
```

These **4** tasks; are the basic steps that _nixos-rebuild_ will perform.

1. Build the _system_ attribute
2. Copy the _/nix/store_ transitive closure
3. Set the _/nix/var/nix/profiles/system_ to the new version
4. Run the _switch-to-configuration_ script

Many[^1] [^2] [^3] have already written about these simple steps; simple scripts can be found on GitHub or even simple wrappers such as [nix-simple-deploy](https://github.com/misuzu/nix-simple-deploy); however _nixos-rebuild_ natively supports remote machines.

```bash
nixos-rebuild switch --target-host $REMOTE_HOST
```

Is there a need for these small wrappers given that _nixos-rebuild_ can do it?

There is a simplicity to running the minimal number of commands needed for your workflow; avoiding _nixos-rebuild.sh_ which is ~500 LOC.

### Linux 🎮 NixOS

I admitted earlier that I have just recently finally started running NixOS after having run Nix on my Debian system for a while now.

_I am only running NixOS on my personal server and not my laptop_; which continues to be Debian. The non-NixOS Nix distribution does not come with _nixos-rebuild_;

> I use my laptop primarily for my work which does not support NixOS.

I would like to however continue hacking on my laptop; building NixOS VMs or running _nixos-rebuild_ with `--target-host` set to my server. Can this be achieved?

With the help of [Infinisil](https://github.com/Infinisil); he helped demonstrate how I can easily install not only _nixos-rebuild_; but even the manpages.

Here is an example of adding the two if you are using [home-manager](https://github.com/rycee/home-manager).
```nix
home.packages = with pkgs; [
  # I want the NixOS manpages even when not on nixos
  ((import <nixpkgs/nixos> {
    configuration = { };
  }).config.system.build.manual.manpages)
  # I want NixOS tooling even when not on NixOS
  (nixos { }).nixos-rebuild
];
```

> _Bonus_; the above actually includes all NixOS manpages including `configuration.nix`

Now I can continue to play around with NixOS even while on my Linux distribution! Hurray?

I would love to dig deeper or understand the _active_ & _init_ scripts within the _system_ target that take care of making NixOS bootable; if you have a good write-up please share!

[^1]: <https://vaibhavsagar.com/blog/2019/08/22/industrial-strength-deployments/#fnref1>
[^2]: <https://ixmatus.net/articles/deploy-software-nix-deploy.html>
[^3]: <http://www.haskellforall.com/2018/08/nixos-in-production.html>

