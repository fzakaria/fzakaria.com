---
layout: post
title: NixOS, Raspberry Pi & Me
date: 2024-08-13 08:52 -0700
excerpt_separator: <!--more-->
---

I have written [a lot](/archive) about [NixOS](https://nixos.org/), so it's no surprise that when I went to go
dust off my old Raspberry Pi 4, I looked to rebrand it as a new NixOS machine.

Before I event went to play with my Pi, I was unhappy with my current home-networking setup and looked to give it a refresh.

I have had always a positive experience with [Ubiquiti](https://www.ui.com/introduction) line of products. I installed two new AP (access points) and setup a _beautiful_ home rack server that is _completely unecessary_ since my Internet provider is Comcast with top upload speeds of 35 Mbps 🥲.

<!--more-->

[![Image of my home rack](/assets/images/home_rack_50p.jpg)](/assets/images/home_rack.jpg)

> I'm currently building a home-server that will fill a few of the empty slots on the rack.

If you are interested in the setup here is the list of materials I used:
* [Dream Machine Special Edition](https://store.ui.com/us/en/collections/unifi-dream-machine/products/udm-se)
* [U6 Access Point](https://store.ui.com/us/en/collections/unifi-wifi-flagship-compact)
* [9U Wall Mount Rack](https://amzn.to/4fGP59A)
* [1U Universal Rack Shelf](https://amzn.to/3AvYFMc)
* [Cat6 Keystone Coupler 5-Pack](https://amzn.to/4fGcHLr)
* [Blank Keystone Jack Inserts](https://amzn.to/4dnyo1a)
* [Cat6 Ethernet Cable 0.5ft 5 Pack](https://amzn.to/3YHTLWr)
* [24-Port Blank Keystone 1U Patch Panel](https://amzn.to/46OzalE)
* [1U PDU Power Strip Surge Protector](https://amzn.to/3yE1iv6)

Now, getting back to the Raspberry Pi, there's quite a few blogs online on how to run NixOS but they all vary slightly in their setup
and few are set up to use _flake.nix_.

Now I'm throwing mine to the mix 🥳.

You can find below [my minimal configuration.nix](https://github.com/fzakaria/nix-home/blob/1a3aee1f2bf31bdeb638276bf2b6e8076e3413c1/machines/kuato/configuration.nix) for my Raspberry Pi (the link goes to GitHub permalink).

Notable points I had to do:
* Feedback from the community on Matrix was to avoid [nixos-hardware](https://github.com/NixOS/nixos-hardware) since the base image _should just work_.
Unfortunately `nixos-hardware.nixosModules.raspberry-pi-4` was necessary, as was the vendored Linux kernel it installs.
* Cross compiling NixOS I believe _is possible_ but I couldn't find a simple set up with _flake.nix_ to work. The ultimate workaround is to add
support for emulation on your build host. This also does let you use the NixOS cache but **be warned** that if you install custom software might come to a crawl.
```
binfmt.emulatedSystems = ["aarch64-linux"];
```
* I disabled ZFS to save a lot of time building my image.
* `compressImage` is disabled since it takes a long time with emulation.
* `makeModulesClosure` snippet below is needed since some Linux kernel modules fail to compile. 🤷

_Final thoughts_ 🤔

While it's cathartic to have your Pi running NixOS and _"declarative"_, the whole experience left much to be desired.
While cross-compiling feels tenable at the individual package level, it was confusing and challenging to setup (I gave up!) to build a complete image.

Given the popularity of Raspberry Pi and the _Internet of things_, there is a strong opportunity to bring a simple setup for Pi's into mainline Nixpkgs
with clear support and guidance on how to cross-compile the image.

❗ If you think my _configuration.nix_ could be improved or you have the solution to cross-compiling, let me know!

### configuration.nix

Having a starting NixOS configuration means you can avoid the base installer and 
directly create the initial image via
```bash
❯ nix build '.#nixosConfigurations.kuato.config.system.build.sdImage'
```

Subsequent updates can happen via _ssh_. I build the image on my `x86_64` machine via _emulation_ using
the following command which then copies the _/nix/store_ closure and activates the new generation.
```bash
❯ nixos-rebuild switch --flake .#kuato \
                       --target-host fmzakari@kuato \
                       --use-remote-sudo
```

```nix
{
  config,
  pkgs,
  inputs,
  outputs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    # had a big discussion on Matrix on which to use for the Raspberry Pi 4
    # looks like there are pi specific modules but they told me to not use them.
    # Also don't use the vendored Linux kernel and just use the regular one.
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    ../../modules/nix.nix
    # Feedback from Matrix was to disable this and it's unecessary unless you are using
    # some esoteric hardware.
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];

  # let's not build ZFS for the Raspberry Pi 4
  boot.supportedFilesystems.zfs = lib.mkForce false;
  # compressing image when using binfmt is very time consuming
  # disable it. Not sure why we want to compress anyways?
  sdImage.compressImage = false;
  # enable the touch screen
  hardware.raspberry-pi."4".touch-ft5406.enable = true;

  # we don't import ../../modules/nixpkgs.nix since we don't want the overlay
  # rebuilding for the Raspberry Pi 4 is expensive; try to stick to what is in the cache.
  nixpkgs = {
    hostPlatform = lib.mkDefault "aarch64-linux";
    config = {
      allowUnfree = true;
    };
    overlays = [
      # Workaround: https://github.com/NixOS/nixpkgs/issues/154163
      # modprobe: FATAL: Module sun4i-drm not found in directory
      (final: super: {
        makeModulesClosure = x:
          super.makeModulesClosure (x // {allowMissing = true;});
      })
    ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = ["noatime"];
    };
  };

  networking = {
    networkmanager.enable = true;
    hostName = "kuato";
  };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];

  services = {
    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      desktopManager = {
        gnome.enable = true;
      };
      displayManager = {
        # Enable the GNOME Desktop Environment
        gdm = {
          enable = true;

          # FIXME: I want to disable wayland but the touch screen seems
          # to not work otherwise.
          # wayland = false;
        };
      };
    };
  };

  # Normally we would re-use the same user configurations in the users directory
  # but since this is a Raspberry Pi 4, lets make a much smaller closure.
  users.users.fmzakari = {
    isNormalUser = true;
    shell = pkgs.bash;
    extraGroups = ["wheel" "networkmanager"];
    description = "Farid Zakaria";
    openssh.authorizedKeys.keyFiles = [
      ../../users/fmzakari/keys
    ];
    # Allow the graphical user to login without password
    initialHashedPassword = "";
  };

  # simplify sudo
  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  # Allow the user to log in as root without a password.
  users.users.root.initialHashedPassword = "";

  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "23.11";
}
```