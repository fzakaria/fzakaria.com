---
layout: post
title: quassel core on NixOS with Let's Encrypt
date: 2020-09-02 21:35 -0700
excerpt_separator: <!--more-->
---

I have been wanting to take part of the NixOS community more; specifically the IRC channels. I have been heavily using the [Discord](https://discord.gg/RbvHtGa) server but I found many other contributors are only on the IRC network. ✊

[#nixos](irc://irc.freenode.net/#nixos)
[#nix-community](irc://irc.freenode.net/#nix-community)

<!--more-->

I am however an _admitted_ IRC n00b; and one of the biggest pain-points of IRC are that due to the decentralized nature of it, you don't get to see any log messages when you are offline. _How frustrating!_

I tried <https://matrix.org/> however the IRC bridge is not really great as it will not send large messages.

> If I wasn't enthusiastic about setting up a NixOS server I might just have used <https://www.irccloud.com/>.

A colleague however introduced me to [Quassel](https://quassel-irc.org/).

> Quassel IRC is a modern, cross-platform, distributed IRC client, meaning that one (or multiple) client(s) can attach to and detach from a central core.

Great! Let's set that up on NixOS.

### Prerequisites

I have a _laptop_ which I will be running the _Quassel client_.

I have a NixOS _server_ which I will be running the _Quassel core server_.

I have a registered sub-domain <https://quassel.example.com> which I've pointed to my _server_.

### Requirements

I would like to run Quassel with TLS using _Let's Encrypt_; a free TLS certificate provider.

### NixOS Setup

#### TLS / ACME

First I create a module _acme.nix_; that will take care of fetching a TLS certificate from _Let's Encrypt_ using the ACME protocol.

I've _heavily_ commented the below example to explain what's going-on.
```nix
{ config, ...}: {

  # We will setup HTTP challenge to receive our ACME (Let's encrypt) certificate
  # https://nixos.org/manual/nixos/stable/#module-security-acme-nginx
  security.acme.acceptTerms = true;
  security.acme.email = "acme+example@gmail.com";
  services.nginx = {
    enable = true;
    virtualHosts = {
      "quassel.example.com" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = { root = "/var/www"; };
      };
    };
  };

  # open the ports for HTTP & HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Create a new group `acme` and set the group of the ACME daemon to run as it.
  # We also allow any user in the `acme` group to access the certificate & key
  users.groups = { acme = { }; };
  security.acme.certs."quassel.example.com".allowKeysForGroup = true;
  security.acme.certs."quassel.example.com".group = "acme";
}
```

With the above module imported; the ACME daemon will perform the [HTTP challenge](https://letsencrypt.org/docs/challenge-types/#http-01-challenge) to prove ownership of the FQDN _quassel.example.com_ and receive a TLS certificate & key.

#### Quassel Core

Luckily there's already a [Quassel NixOS module](https://github.com/NixOS/nixpkgs-channels/blob/nixos-unstable/nixos/modules/services/networking/quassel.nix) that does most of the heavy lifting.

I simply configure it by forcing _SSL_ and setting the certificate material to the one downloaded by the ACME daemon above.

```nix
{ config, pkgs, ... }: {

  # The quassel module will create a default user `quassel`
  # Add quassel to the acme group so that it can access the certificate
  users.groups.acme.members = [ "quassel" ];

  services.quassel = {
    enable = true;
    requireSSL = true;
    # set the certificate material to that downloaded by the HTTP challenge above
    certificateFile =
      "${config.security.acme.certs."quassel.example.com".directory}/full.pem";
    # Listen on the public interface
    interfaces = [ "0.0.0.0" ];
  };

  # make sure the quassel default port is open on the firewall
  networking.firewall.allowedTCPPorts = [ 4242 ];
}
```

_Voila!_

Now I just need to figure out a nice view setup for my Quassel client to _look pretty_. Hopefully you find this guide informational and it helps you also join the IRC NixOS community.