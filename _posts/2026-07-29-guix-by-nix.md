---
layout: post
title: Guix by Nix
date: 2026-07-29 20:58 -0700
---

I have been working more on [GuixPkgs](https://github.com/fzakaria/guixpkgs) in preparation for a talk at [nix.vegas](http://nix.vegas/) for [DEFCON34](https://defcon.org/html/defcon-34/dc-34-index.html). At the end of my previous [GuixPkgs post]({% post_url 2026-06-25-guixpkgs-every-guix-package-as-a-nix-flake %}) I left a teaser:

> We can then build a NixOS machine where every package is the Guix equivalent 😱.

Well, [adeci](https://github.com/adeci)[^1] took the bait and we went _even further_ than that. 😈

Say hello to [Guix by Nix](https://github.com/adeci/guix-by-nix): a bootable VM where the kernel is Guix's Linux-libre, the userland is translated Guix packages, and PID 1 is [**GNU Shepherd**](https://shepherding.services/). 

No systemd. No D-Bus. No NixOS activation. Not even a `nix` or `guix` binary in the guest. It's Guile all the way down and Nix built all of it.

```console
$ nix run --accept-flake-config github:adeci/guix-by-nix
...
Starting Guix-derived initrd
GUIX_BY_NIX_INITRD_MODULES_READY modules=virtio_pci,virtio_blk,...,overlay
GUIX_BY_NIX_INITRD_ROOT_READY device=/dev/vda
Starting Guix by Nix activation
GUIX_BY_NIX_ACTIVATION_READY
Starting Guix Shepherd as PID 1
SHEPHERD_NETWORK_READY address=10.0.2.15 gateway=10.0.2.2 resolver=10.0.2.3
SHEPHERD_PID1 parent=1 child=690

Welcome to Guix by Nix (experimental)
guix-by-nix login: root
```

Log in with `root` / `guix-by-nix` and poke around:

```console
bash-5.2# ps -p 1
  PID TTY          TIME CMD
    1 ?        00:00:00 shepherd

bash-5.2# uname -r
6.12.62-gnu

bash-5.2# readlink -f "$(command -v ls)"
/nix/store/...-coreutils-9.1/bin/ls
```

As a reminder, even though these binaries live in `/nix/store`, they are _not_ Nixpkgs packages. They were translated from Guix derivations using [guix-transfer](https://github.com/fzakaria/guix-transfer) and built by the `nix-daemon`.

That `coreutils` was built from Guix's package definition, source bootstrap and all , but it lives in `/nix/store`, because `nix-daemon` built it.

If you want to try out any of these packages on your own machine, you can use [GuixPkgs](https://github.com/fzakaria/guixpkgs).

```console
$ nix run --accept-flake-config github:fzakaria/guixpkgs#coreutils
```

> **Tip**
> Guix offers all packages built from source where Nix may offer it as a prebuilt binary. You can use GuixPkgs to get a source-built bootstrapped version of OpenJDK for example and all the [whacky steps](https://www.bootstrappable.org/projects/java.html) to get there.
{: .alert .alert-tip }

## How it works

How does this actually work? The project is a three-stage pipeline:

1. [guix-transfer]({% post_url 2026-06-05-the-guix-nix-abomination-leveraging-guix-derivations-in-nix %}) is the tool that translates Guix derivation graphs into Nix derivations.
2. [GuixPkgs]({% post_url 2026-06-25-guixpkgs-every-guix-package-as-a-nix-flake %}) is the flake with all Guix packages, all built from the 357-byte seed, although there is a Cachix cache provided.
3. **Guix by Nix** assembles ~42 of those packages, a subset of the overall set, into a useable machine.

> **Warning**
> AI was leveraged to write the initrd and activation scripts.
> That seems to trigger people lately, so consider yourself warned.
{: .alert .alert-warning }

- The **initrd** is a custom shell script, interpreted by Guix Bash, that loads eight modules, mounts the root disk and the 9p store, and `switch_root`s.
- **Activation** (accounts, `/etc`, the setuid `sudo` copy) is another custom Nix-generated script run by Guix Bash.
- **PID 1** is `shepherd` from Guix, with a small Scheme config that starts `eudev`, `dhcpcd`, `openresolv`, and a serial `getty`. `herd status` works like you'd expect.
- `/etc/profile` is compiled from Guix's own search-path specifications, so `GUILE_LOAD_PATH` and friends point where Guix intended.

Every program that can be executed, every ELF file, every script interpreter, all traces back to a translated Guix derivation. The only things Nix authored are text files: the init scripts, the Shepherd config, `/etc`.

This is _Guix by Nix_.

## Don't trust me. Read the receipt.

"Every executable byte comes from Guix" is exactly the kind of claim that's easy to say and easy to fudge. 🤥

A booted demo is great but that can't prove it. A VM where `ls` secretly came from Nixpkgs boots _identically_.

The flake ships an audit-check that classifies **every store path in the shipped closure** by provenance, unpacks the compressed initrd[^2], and inspects every executable payload. The audit derivation fails if anything is unclassified, any ELF file or script interpreter doesn't trace to a translated Guix output, any `/gnu/store` reference survived translation, or anything systemd-shaped appears anywhere.

```console
$ nix build --accept-flake-config github:adeci/guix-by-nix#status-report
$ jq '{rejected, claims}' result/status.json
{
  "rejected": {
    "wrapperPaths": 0,
    "nonGuixElf": 0,
    "externalScriptInterpreters": 0,
    "untranslatedGnuStoreReferences": 0,
    "unclassifiedPaths": 0,
    "systemdDbusLogindPaths": 0
  },
  "claims": {
    "translatedLinuxLibre": true,
    "wrapperFreeGuest": true,
    "allElfFromGuix": true,
    "allScriptInterpretersGuixDerived": true,
    "systemdFreeGuest": true,
    "fullyClassified": true,
    "emptyFirmwareBoundary": true
  }
}
```

The report includes a lot more information such as the exact Guix channel commit everything was translated from. There's also some NixOS VM tests for good-measure. 🕵

> **Note**
> The kernel is Guix's `linux-libre-lts`, translated and built by `nix-daemon` like everything else. Nix wraps it in a thin adapter so NixOS's VM tooling accepts it by augmenting with some additional metadata only; the `bzImage` is byte-for-byte Guix's.
{: .alert .alert-note }


## What's next

One obvious next step would be a _normal_ NixOS machine, where every package that exists in GuixPkgs shadows its Nixpkgs equivalent on `$PATH`. GuixPkgs offers such an overlay, but it needs quite a lot of CPU to build all of it....

A more realistic use case is to mix and match GuixPkgs and Nixpkgs packages in a single system. Get the best of both. I heard there were people in the Nix community who still want a non-systemd system, à la [sixos](https://codeberg.org/amjoseph/sixos). 🫠

For now, this project remains a minimal VM demo. If you make it PID 1 on real hardware, please send photos. 🙇

[^1]: It has been extremely fun and rewarding to work with Alex on this project. We nix-pilled him at [PlanetNix](https://planetnix.org/) 2 years ago and since then he has been pushing the boundaries of what Nix can do and is currently employed at [Shopify](https://www.shopify.com/) working on Nix.
[^2]: Nix's reference scanner can't see inside archives and sneaky paths hide there.