---
layout: post
title: A Nix Binary Cache Specification
date: 2021-08-12 14:20 -0700
excerpt_separator: <!--more-->
---

I wanted to better understand how to work with Nix binary caches. Interestingly the Nix manual which usually is a great source of knowledge, has [a very limited section](https://nixos.org/manual/nix/unstable/package-management/binary-cache-substituter.html) on the Binary Cache.

> It basically just points you to [nix-serve](https://github.com/edolstra/nix-serve/), a Perl CGI script in [Eelco's](https://github.com/edolstra) (original author of Nix) personal repository.

This guide will serve to be a _loose_ Nix Binary Cache specification.
If you are interested in browsing the end result, please checkout my [OpenAPI Nix HTTP Binary Cache Specification](https://fzakaria.github.io/nix-http-binary-cache-api-spec) 🎆

> You can also visit the GitHub repository [https://github.com/fzakaria/nix-http-binary-cache-api-spec](https://github.com/fzakaria/nix-http-binary-cache-api-spec) to contribute.

<!--more-->

Since there's no specification (aside from the code), I will use the canonical binary cache [https://cache.nixos.org](https://cache.nixos.org) and using _Ruby_ for investigation.

Let's start off and use `nix path-info` to query some information. I find it always more useful to use `--json` to see the displayed results.

```bash
❯ nix path-info nixpkgs.ruby --store https://cache.nixos.org --json | jq
[
  {
    "path": "/nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3",
    "narHash": "sha256:1impfw8zdgisxkghq9a3q7cn7jb9zyzgxdydiamp8z2nlyyl0h5h",
    "narSize": 18735072,
    "references": [
      "/nix/store/0d71ygfwbmy1xjlbj1v027dfmy9cqavy-libffi-3.3",
      "/nix/store/0dbbrvlw2rahvzi69bmpqy1z9mvzg62s-gdbm-1.19",
      "/nix/store/0i6vphc3vnr8mg0gxjr61564hnp0s2md-gnugrep-3.6",
      "/nix/store/0vkw1m51q34dr64z5i87dy99an4hfmyg-coreutils-8.32",
      "/nix/store/64ylsrpd025kcyi608w3dqckzyz57mdc-libyaml-0.2.5",
      "/nix/store/65ys3k6gn2s27apky0a0la7wryg3az9q-zlib-1.2.11",
      "/nix/store/9m4hy7cy70w6v2rqjmhvd7ympqkj6yxk-ncurses-6.2",
      "/nix/store/a4yw1svqqk4d8lhwinn9xp847zz9gfma-bash-4.4-p23",
      "/nix/store/hbm0951q7xrl4qd0ccradp6bhjayfi4b-openssl-1.1.1k",
      "/nix/store/hjwjf3bj86gswmxva9k40nqx6jrb5qvl-readline-6.3p08",
      "/nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3",
      "/nix/store/sbbifs2ykc05inws26203h0xwcadnf0l-glibc-2.32-46"
    ],
    "deriver": "/nix/store/bidkcs01mww363s4s7akdhbl6ws66b0z-ruby-2.7.3.drv",
    "signatures": [
      "cache.nixos.org-1:GrGV/Ls10TzoOaCnrcAqmPbKXFLLSBDeGNh5EQGKyuGA4K1wv1LcRVb6/sU+NAPK8lDiam8XcdJzUngmdhfTBQ=="
    ],
    "url": "nar/1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3.nar.xz",
    "downloadHash": "sha256:1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3",
    "downloadSize": 4029176
  }
]
```

How did the Nix tool determine this information and what does it mean? 🕵️

Every Nix Binary Cache needs to support querying for [NARInfo](https://hackage.haskell.org/package/nix-narinfo-0.1.0.1/docs/Nix-NarInfo.html) files for a particular store path. 

For instance for our Ruby path _/nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3_, we take the cryptographic hash portion and use that to cURL the metadata [https://cache.nixos.org/p4pclmv1gyja5kzc26npqpia1qqxrf0l.narinfo](https://cache.nixos.org/p4pclmv1gyja5kzc26npqpia1qqxrf0l.narinfo).

```bash
❯ curl -i https://cache.nixos.org/p4pclmv1gyja5kzc26npqpia1qqxrf0l.narinfo
HTTP/2 200 
x-amz-id-2: Qpz5ZRR31fiF+A3lN9Gl5SVP1kC4/9jgEWUibbFX/p+rVazDVznQMtT4qgskwlkDcwOtDGtegjY=
x-amz-request-id: 5G9ZDZB9TFR665RN
last-modified: Wed, 19 May 2021 10:43:55 GMT
etag: "0faa37071023836830facecbcf99b384"
content-type: text/x-nix-narinfo
server: AmazonS3
via: 1.1 varnish, 1.1 varnish
accept-ranges: bytes
date: Thu, 12 Aug 2021 21:39:39 GMT
age: 47939
x-served-by: cache-bwi5123-BWI, cache-pao17429-PAO
x-cache: HIT, HIT
x-cache-hits: 1, 1
x-timer: S1628804380.563848,VS0,VE0
content-length: 1058

StorePath: /nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3
URL: nar/1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3.nar.xz
Compression: xz
FileHash: sha256:1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3
FileSize: 4029176
NarHash: sha256:1impfw8zdgisxkghq9a3q7cn7jb9zyzgxdydiamp8z2nlyyl0h5h
NarSize: 18735072
References: 0d71ygfwbmy1xjlbj1v027dfmy9cqavy-libffi-3.3 0dbbrvlw2rahvzi69bmpqy1z9mvzg62s-gdbm-1.19 0i6vphc3vnr8mg0gxjr61564hnp0s2md-gnugrep-3.6 0vkw1m51q34dr64z5i87dy99an4hfmyg-coreutils-8.32 64ylsrpd025kcyi608w3dqckzyz57mdc-libyaml-0.2.5 65ys3k6gn2s27apky0a0la7wryg3az9q-zlib-1.2.11 9m4hy7cy70w6v2rqjmhvd7ympqkj6yxk-ncurses-6.2 a4yw1svqqk4d8lhwinn9xp847zz9gfma-bash-4.4-p23 hbm0951q7xrl4qd0ccradp6bhjayfi4b-openssl-1.1.1k hjwjf3bj86gswmxva9k40nqx6jrb5qvl-readline-6.3p08 p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3 sbbifs2ykc05inws26203h0xwcadnf0l-glibc-2.32-46
Deriver: bidkcs01mww363s4s7akdhbl6ws66b0z-ruby-2.7.3.drv
Sig: cache.nixos.org-1:GrGV/Ls10TzoOaCnrcAqmPbKXFLLSBDeGNh5EQGKyuGA4K1wv1LcRVb6/sU+NAPK8lDiam8XcdJzUngmdhfTBQ==
```

We see that it points to another URL at _nar/1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3.nar.xz_.

Let's get some statistics about it.

> NAR is the Nix ARchive. Not all archive formats are reproducible, so Nix had to create it's own!

```bash
❯ nix-hash --type sha256 --flat \
       --base32 <(curl --silent https://cache.nixos.org/nar/1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3.nar.xz | unxz)

1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3
```

Cool 😎! Looks like we computed the correct hash for the _FileHash_.

> How did I know it was base32! Everything in Nix is base32 😞
> This is needed to shrink the necessary space to work within the POSIX filepath limits.
> Frustratingly, [sha256sum](https://linux.die.net/man/1/sha256sum) doesn't have a base32 option.

The NAR hash should be calcuated in a very similar fashion.

Let's try by piping it into [unxz](https://linux.die.net/man/1/unxz).

```bash
❯ nix-hash --type sha256 --flat \
       --base32 <(curl --silent https://cache.nixos.org/nar/1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3.nar.xz | unxz)
1impfw8zdgisxkghq9a3q7cn7jb9zyzgxdydiamp8z2nlyyl0h5h
```

What about _References_, what's that?

We see a very similar concept in the `nix-store --query` CLI and it produces the same list.
```bash
❯ nix-store --query \
    --references /nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3

/nix/store/sbbifs2ykc05inws26203h0xwcadnf0l-glibc-2.32-46
/nix/store/0d71ygfwbmy1xjlbj1v027dfmy9cqavy-libffi-3.3
/nix/store/0dbbrvlw2rahvzi69bmpqy1z9mvzg62s-gdbm-1.19
/nix/store/0i6vphc3vnr8mg0gxjr61564hnp0s2md-gnugrep-3.6
/nix/store/0vkw1m51q34dr64z5i87dy99an4hfmyg-coreutils-8.32
/nix/store/64ylsrpd025kcyi608w3dqckzyz57mdc-libyaml-0.2.5
/nix/store/65ys3k6gn2s27apky0a0la7wryg3az9q-zlib-1.2.11
/nix/store/9m4hy7cy70w6v2rqjmhvd7ympqkj6yxk-ncurses-6.2
/nix/store/a4yw1svqqk4d8lhwinn9xp847zz9gfma-bash-4.4-p23
/nix/store/hbm0951q7xrl4qd0ccradp6bhjayfi4b-openssl-1.1.1k
/nix/store/hjwjf3bj86gswmxva9k40nqx6jrb5qvl-readline-6.3p08
/nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3
```

> --references
>       Prints the set of references of the store paths paths, that is, their immediate dependencies.
>       (For all dependencies, use --requisites.)

Looks like it just prints the **immediate dependencies**. 
In order for our _Ruby_ to run successfully on a machine, one would have to though download the **full transitive closure of runtime dependencies**.

If we _extract_ the NAR above, we see it's just the contents of our Nix derivation.

```bash
❯ curl --silent https://cache.nixos.org/nar/1w1fff338fvdw53sqgamddn1b2xgds473pv6y13gizdbqjv4i5p3.nar.xz \
       | unxz | nix-store --restore /tmp/ruby

❯ ls -l /tmp/ruby

drwxr-xr-x - fmzakari 12 Aug 15:16 bin
drwxr-xr-x - fmzakari 12 Aug 15:16 include
drwxr-xr-x - fmzakari 12 Aug 15:16 lib
drwxr-xr-x - fmzakari 12 Aug 15:16 nix-support
drwxr-xr-x - fmzakari 12 Aug 15:16 share
```

Finally browsing the _nix-serve_ source, I see there's a _/nix-cache-info_ path.
```bash
❯ curl https://cache.nixos.org/nix-cache-info
StoreDir: /nix/store
WantMassQuery: 1
Priority: 40
```

It seems to give some information about this particular cache.

The important one is the _StoreDir_ since the store-path is part of the build recipe.
When you build a derivation, the Nix store directory is encoded within.

If you pick an arbitrary Nix store dir such as `~/nix/store` you will be unable to use
the default NixOS binary cache.

For instance, even though above I extracted the Ruby NAR to **/tmp/ruby**, if we read where
it expects to find the dynamic libraries, we see it still references _/nix/store_.

```bash
❯ ldd /tmp/ruby/bin/ruby
	linux-vdso.so.1 (0x00007ffd6e57b000)
	libruby-2.7.3.so.2.7 => /nix/store/p4pclmv1gyja5kzc26npqpia1qqxrf0l-ruby-2.7.3/lib/libruby-2.7.3.so.2.7 (0x00007f7a819e2000)
    ibz.so.1 => /nix/store/65ys3k6gn2s27apky0a0la7wryg3az9q-zlib-1.2.11/lib/libz.so.1 (0x00007f7a819c5000)
...
```

Wow! I ended up encoding this discovery into an [OpenAPI](https://swagger.io/resources/open-api/) specification that you can check out.

Please visit [https://fzakaria.github.io/nix-http-binary-cache-api-spec/#/](https://fzakaria.github.io/nix-http-binary-cache-api-spec/#/) or contribute to the specification at [https://github.com/fzakaria/nix-http-binary-cache-api-spec](https://github.com/fzakaria/nix-http-binary-cache-api-spec).
