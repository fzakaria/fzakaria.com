---
layout: post
title: 'A Nix store is three functions'
date: 2026-09-11 20:00 -0700
---

While building [trynix]({% post_url 2026-09-04-any-nix-package-live-in-your-browser %})
I needed somewhere to host a store-path that did not exist on
[cache.nixos.org](https://cache.nixos.org).[^cachix] I wanted to demonstrate that non-Nixpkgs store paths could be booted just as easily.

[^cachix]: I was also waiting for [@domenkozar](https://github.com/domenkozar) to enable CORS on [cache.nixos.org](https://cache.nixos.org) so I could use it.

The only requirement seemed to be a lenient [Cross-Origin Resource Sharing (CORS)](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS) policy, `access-control-allow-origin: *`, because the fetch happens in JavaScript.

Turns out that GitHub Pages sets that header on every file it
serves. 😈 I committed the output of `nix copy --to file://` to my [Git repository](https://github.com/fzakaria/trynix/tree/main/site/examples/cache) and voilà, I have a _free_ Nix substituter.

I seem to be late to the party on this discovery. [tomberek's github-store](https://github.com/tomberek/github-store) is a cache assembled out of GitHub release assets.[^nar]

[^nar]: In order to be a Nix binary cache, the `nar/` prefix is stripped from the `URL` field in the narinfo, because GitHub releases are a flat namespace.

```console
$ B=https://github.com/tomberek/github-store/releases/latest/download

$ curl -sL $B/nix-cache-info
StoreDir: /nix/store

$ curl -sL $B/1zy01hjzwvvia6h9dq5xar88v77fgh9x.narinfo
StorePath: /nix/store/1zy01hjzwvvia6h9dq5xar88v77fgh9x-glibc-2.38-44
URL: 0hkyywarmj4frwvs6p4lz4yl6z5q5halphswlqksh7lbkn4r75si.nar.xz
Compression: xz
FileHash: sha256:0hkyywarmj4frwvs6p4lz4yl6z5q5halphswlqksh7lbkn4r75si
FileSize: 6514112
NarHash: sha256:1ikxmc8yxzmm9vzzaa313w9yzrrgm0p6cgscy8arq3z32kynpi94
NarSize: 30244048
References: 1zy01hjzwvvia6h9dq5xar88v77fgh9x-glibc-2.38-44 a3n1vq6fxkpk5jv4wmqa1kpd3jzqhml9-libidn2-2.3.4 …
Deriver: 3fd7s6gjwi6rxfqw00bjq9ghnvazvnnn-glibc-2.38-44.drv
Sig: cache.nixos.org-1:YWkvHMXyvOw1iqWblEdvju+OZbGOvwYXyjyRUxuXluFq17xwJFSzHb0HrIuRr9BXYjV6GxfmGGv+ckVNvAOpDQ==

$ curl -sL $B/0hkyywarmj4frwvs6p4lz4yl6z5q5halphswlqksh7lbkn4r75si.nar.xz | wc -c
6514112
```

GitHub Pages and Releases are static file servers. They have no idea what Nix is. If a humble file server can be a Nix binary cache, what else could we use?

## The interface

Turns out that in order to be a Nix binary cache, you must implement only three simple functions. The Nix client does not care what medium you use to implement them, although HTTP is the most common and included by default in [CppNix](https://github.com/NixOS/nix).[^cppnix]

[^cppnix]: You can write a Nix plugin to implement a new protocol if you wanted.

```
GET nix-cache-info
 →  StoreDir: /nix/store
GET <32-char hash>.narinfo
 →  metadata naming an archive
GET <the narinfo's URL field>
 →  the compressed archive
```

That's it.

Anything that can answer those three requests can be used as a remote _Nix store_.[^store]

[^store]: We will see that they need not all be on the same medium, protocol or domain even!

## What about the signatures!?

[![simpson meme about signatures](/assets/images/simpsons_meme_children_signatures.png)](/assets/images/simpsons_meme_children_signatures.png)
{: style="--image-width: 20rem"}

The reason we can be this careless about transport is that Nix does not trust it. A narinfo's signature (`Sig`) field covers `StorePath`, `NarHash`, `NarSize` and `References`. It does not cover `URL`, `FileHash`, `FileSize` or `Compression`.

Once the archive is fetched, Nix decompresses it and checks that the `NarHash` matches.

This is the _special sauce_ of how packages that were signed by [cache.nixos.org](https://cache.nixos.org) can be fetched from any other binary cache as an intermediary, and the signature still validates.

The `URL` field does not even have to be on the same host as the narinfo. It can be anywhere on the internet, and it can be a different protocol than HTTP. Nix does not care. The only thing that matters is that the archive fetched from `URL` has the same `NarHash` as the narinfo.

## Alternative Stores

For protocols that are not included by default in the Nix client, you can always write an HTTP proxy that translates the three functions to whatever medium you want.

In research for this post, I found a few interesting ones.

**[gachix](https://github.com/EphraimSiegfried/gachix)**: puts the archives in git's object database. Git content-addresses and delta-compresses blobs already, so the store dedupes itself; the author reports roughly 82% smaller than the equivalent plain cache.

**DNS**: I wrote a proof-of-concept that puts the narinfo and 4 KiB slices of the archive in TXT records. The narinfo is small enough to fit on one record but the archive needs to be chunked.

**[pastebin](https://pastebin.com/)**: a pastebin can hold the narinfo and the archive. The narinfo is small enough to fit on one paste, but the archive needs to be chunked. Many pastebins have an expiry policy which acts as a natural garbage collector.

**[nixcache-oci](https://github.com/cmspam/nixcache-oci)**: uses an OCI registry to store Nix archives.

**[infinite storage glitch](https://github.com/KKarmugil/Infinite_Storage_Glitch)**: encodes data within a video and uploads it to YouTube.

## npm

> "Everything is available on npm"
> -- Some person on the internet

Unsurprisingly, npm is a _great_ binary cache and it has some interesting properties for release management we can ~~ab~~use.

`nix copy --to file://` emits a directory and npm publishes directories: a match made in heaven. 💑

Let's walk through a small `hello` example.

```nix
packages.${system}.default = pkgs.hello.overrideAttrs (old: {
  pname = "hello-npm";
  # The upstream test suite greps for the original greeting.
  doCheck = false;
  postPatch = (old.postPatch or "") + ''
    substituteInPlace src/hello.c \
      --replace-fail 'Hello, world!' 'Hello from the npm registry!'
  '';
});
```

It is dynamically linked against glibc, so the closure is five paths and
roughly 36 MiB:

```console
$ nix path-info -rSh result
/nix/store/yh8rykx8wakl1ccn8rc351f6r2wbg4cn-libunistring-1.4.2	   2.0 MiB
/nix/store/nga9d6m9iplygw3iqghk2g840nz7b0gy-libidn2-2.3.8     	   2.3 MiB
/nix/store/ssvq1r0xd8f7paf6zqgpfql1a4drwhy2-xgcc-15.3.0-libgcc	 193.0 KiB
/nix/store/n51dhmdbik1kfrsm62j5knavmigwrl1a-glibc-2.42-84     	  36.0 MiB
/nix/store/3ssib4ic89qw7x1gha10s6mdf42fk15v-hello-npm-2.12.3  	  36.2 MiB
```

We copy it to a local cache, signed with our own key, and add the one file
npm needs (`package.json`):

```console
$ nix key generate-secret --key-name hello-npm-1 > cache-key.sec
$ nix key convert-secret-to-public < cache-key.sec > cache-key.pub
$ nix copy --to "file://$PWD/cache?secret-key=$PWD/cache-key.sec" .#
$ cd cache && rm -rf log build-trace-v2 && npm init --scope=@fzakaria -y
```

`npm publish` then dutifully packages our complete closure for us:

```console
$ npm publish --access public
npm notice 606B   3ssib4ic89qw7x1gha10s6mdf42fk15v.narinfo
npm notice 767B   n51dhmdbik1kfrsm62j5knavmigwrl1a.narinfo
npm notice 7.3MB  nar/06fsxd8j9ck4ls5b8xj4r4zk2642xzxzmdj6bl93zfwcm4pqzx0z.nar.xz
npm notice 467.5kB nar/1asdj56kfpvbqh8bpg5wns4v0yd1p3ldl6p2swv6nfwfdgvbwklc.nar.xz
npm notice 21B    nix-cache-info
npm notice name: @fzakaria/hello-nix-cache
npm notice version: 1.0.0
npm notice package size: 8.0 MB   total files: 12
```

[`@fzakaria/hello-nix-cache`](https://www.npmjs.com/package/@fzakaria/hello-nix-cache)
is now a real package on the public npm registry.

It is now a substituter you can point Nix at directly:

```console
$ nix copy --from https://unpkg.com/@fzakaria/hello-nix-cache@latest/ \
    --to ./npmstore \
    --trusted-public-keys 'hello-npm-1:u4SntZm2u3sob9zBw2OG6yePvJGoRRQUk00LQh4pnKA=' \
    /nix/store/3ssib4ic89qw7x1gha10s6mdf42fk15v-hello-npm-2.12.3
copying 5 paths...
copying path '/nix/store/ssvq1r0xd8f7paf6zqgpfql1a4drwhy2-xgcc-15.3.0-libgcc' from 'https://unpkg.com/@fzakaria/hello-nix-cache@latest'...
copying path '/nix/store/n51dhmdbik1kfrsm62j5knavmigwrl1a-glibc-2.42-84' from 'https://unpkg.com/@fzakaria/hello-nix-cache@latest'...
copying path '/nix/store/3ssib4ic89qw7x1gha10s6mdf42fk15v-hello-npm-2.12.3' from 'https://unpkg.com/@fzakaria/hello-nix-cache@latest'...

$ bwrap --ro-bind ./npmstore/nix/store /nix/store --proc /proc --dev /dev \
    /nix/store/3ssib4ic89qw7x1gha10s6mdf42fk15v-hello-npm-2.12.3/bin/hello
Hello from the npm registry!
```

> **Note**
> We have to use `bwrap` to run the binary because `./npmstore` is a _chroot store_ and all the paths
> are still under `/nix/store`. If we had [relocatable binaries]({% post_url 2026-06-21-nix-needs-relocatable-binaries %}) we could run it directly.
{: .alert .alert-note }

That is Nix fetching the complete closure from npm and running it. 🤯
We can distribute Nix packages to non-Nix users, let the infection spread!

As an added bonus, similar to Nixpkgs and NixOS we can get nice "channel" semantics by using npm's dist-tags. The `latest` tag is mutable and points to the latest version, while each version is immutable and points to a specific store path.

```console
$ npm dist-tag add @fzakaria/hello-nix-cache@1.0.5 staging
$ npm dist-tag add @fzakaria/hello-nix-cache@1.0.4 production
```

The major downside of this approach is that npm has no incremental publishing.
Every version is a whole tarball, so fifty closures sharing glibc upload glibc fifty times.

We _could_ fix that by publishing each store path as a separate package, and then having a small index package that points at them. Each store path would then be uploaded exactly once.

I won't build that though as it's not in good faith to the npm ecosystem.

What other store implementations can we find?