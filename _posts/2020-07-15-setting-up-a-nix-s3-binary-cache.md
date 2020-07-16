---
layout: post
title: setting up a Nix S3 binary cache
date: 2020-07-15 21:13 -0700
excerpt_separator: <!--more-->
---

> If you just want a very easy-to-use binary cache, consider using [cachix](https://cachix.org/).

[Nix](https://nixos.org/) is an amazing tool, however the learning curve can be ~~very~~ high. The online wiki has a lot of great documentation however I find it is often very geared towards NixOS specifically.

I wanted to better understand how to setup my own **binary cache**.

<!--more-->

> A binary cache builds Nix packages and caches the result for other machines. Any machine with Nix installed can be a binary cache for another one, no matter the operating system.

As mentioned above, there are a few solutions already offered in Nix:
- cache.nixos.org: The default binary cache included with all Nix installations
- [cachix](https://cachix.org/): A _sass_ product that has a great free tier as long as your caches are public.
- [nix-serve](https://github.com/edolstra/nix-serve): A _perl_ standalone HTTP binary cache implementation.
-  Any machine can be used as a cache through SSH protocol

I specifically wanted to document & explore Nix support for binary caching using [AWS S3](https://aws.amazon.com/s3/).

> The following guide assumes you have an AWS account & have setup CLI credentials .

### Our custom derivation

In order to test our new cache; we'll create a derivation that is **definitely** not on [nixpkgs](https://github.com/NixOS/nixpkgs); especially the default cache service.

Let's create a _slightly_ modified version of the [GNU hello](https://www.gnu.org/software/hello/) program.

Let's save the below derivation in a file _lolhello.nix_.

```nix
{ pkgs ? import <nixpkgs> { }, stdenv ? pkgs.stdenv, fetchurl ? pkgs.fetchurl }:
stdenv.mkDerivation {
  name = "lolhello";

  src = fetchurl {
    url = "mirror://gnu/hello/hello-2.3.tar.bz2";
    sha256 = "0c7vijq8y68bpr7g6dh1gny0bff8qq81vnp4ch8pjzvg56wb3js1";
  };

  patchPhase = ''
    sed -i 's/Hello, world!/hello, Nix!/g' src/hello.c
  '';
}
```

> This guide isn't meant to cover on how to write derivations, however hopefully this one is simple enough to follow along.

Since Nix is **reproducible**, the _/nix/store_ path for the output of this derivation will always be **/nix/store/95hmzgcfq0499l4ln72p3b4wv4smp9qw-lolhello**.

### Create a bucket

Le's create a bucket at the moment to act as the root of our _/nix/store_.

I chose _s3://fmzakari-nixcache_

## Generate Binary Cache Key

```bash
nix-store --generate-binary-cache-key fmzakari-nixcache \
 cache-priv-key.pem cache-pub-key.pem
```

We will be utilizing Nix's ability to validate that the contents of cached paths in the store through a cryptographic signature.

## Build & Sign

```bash
# build it locally so it's present in /nix/store
nix-build --no-out-link lolhello.nix
# sign the /nix/store path
nix sign-paths --key-file cache-priv-key.pem \
    $(nix-build --no-out-link lolhello.nix)
```

`$(nix-build --no-out-link lolhello.nix)` is just a quick way to return the _nix/store/_ output path _/nix/store/95hmzgcfq0499l4ln72p3b4wv4smp9qw-lolhello_.

## Upload

```bash
# upload the contents to your S3
nix copy --to s3://fmzakari-nixcache $(nix-build --no-out-link lolhello.nix)
```

## Purge the local store

```bash
# This deletes the /nix/store paths & the database entries
nix-store --delete $(nix-build --no-out-link lolhello.nix)
```

## Build (from the cache!)

```bash
nix-build --no-out-link lolhello.nix
these paths will be fetched (0.03 MiB download, 0.18 MiB unpacked):
>   /nix/store/95hmzgcfq0499l4ln72p3b4wv4smp9qw-lolhello
> copying path '/nix/store/95hmzgcfq0499l4ln72p3b4wv4smp9qw-lolhello' from 's3://fmzakari-nixcache'...
> /nix/store/95hmzgcfq0499l4ln72p3b4wv4smp9qw-lolhello

# run the modified hello after it was pulled from the cache
/nix/store/95hmzgcfq0499l4ln72p3b4wv4smp9qw-lolhello
> hello, Nix!

```

If you wanted to avoid having to add the `--option` for _nix-store_ or even have the caching work with _nix-build_, the **~/.config/nix/nix.conf** file will have to updated.

Here are the contents for the same s3 cache used above however placed within the _nix.conf_.
```
substituters = https://cache.nixos.org https://looker.cachix.org s3://fmzakari-nixcache

trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= looker.cachix.org-1:9iVdEFDyfK4uFDz54S51bBuTPCSKly1PmY/tScSbja0=
```

> There doesn't seem to be a simple programmatic way to update *nix.conf*; so you'll have to hand edit or sed :)

Using S3 was surprising a pretty straightforward way to achieve a personal binary cache; although distributing the public keys are a bit of a hassle.

Biggest pain points though seem to be:
1. Not a simple way to programmatically update the **nix.conf** file for the new binary caches.
2. Somewhat scary if you'd like to have multiple contributors to your new binary cache by sharing the single private key.
