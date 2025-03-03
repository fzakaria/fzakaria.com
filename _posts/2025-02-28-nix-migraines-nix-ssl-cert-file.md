---
layout: post
title: 'Nix migraines: NIX_SSL_CERT_FILE'
date: 2025-02-28 19:07 -0800
redirect_from:
  - /2025/03/01/nix-migraines-nix-ssl-cert-file.html
  - /2025/03/01/nix-migraines-nix-ssl-cert-file
  - /2025/03/01/nix-migraines-nix-ssl-cert-file/
---

> This will be a self-post to describe [nixpkgs#issue385955](https://github.com/NixOS/nixpkgs/issues/385955). I refused to just "copy code" from other packages and wanted to better understand what was going on.

If you're on a "proper" operating system (i.e. Linux), Nix protects you from accidental impurities by enforcing a filesystem **and network** sandbox.

_This is not the case in MacOS._ You can optionally enable the sandbox but it **does not include a network** sandbox.

> 🤔 I have some pretty strong opinions here. Although I am using Nix on MacOS, I would advocate for Nix/Nixpkgs *dropping* MacOS (& eventual Windows/BSD) support. Constraints are when you can find simplicity and beauty.

I had packaged up my personal blog (_this site right here!_ 📝) into a [flake.nix](https://github.com/fzakaria/fzakaria.com/blob/7b6e7621a25bfef0bd64bb88e7885b6f68545cd6/flake.nix) that worked on Linux but was failing on MacOS.

Turns out that one of the [jekyll](https://jekyllrb.com/) plugins I am using, `jekyll-github-metadata`, tries to contact [github.com](https://github.com) to fetch a bunch of data _I don't even need_ 😤.

It would immediately fail with a _cryptic_ SSL error.

```
SSL_connect SYSCALL returned=5 errno=0
peeraddr=140.82.116.5:443 state=error:
certificate verify failed
(unable to get local issuer certificate)
(Faraday::SSLError)
```

> I was able to replicate this on NixOS with `nix build --no-sandbox`

Okay 🤔 it's failing to verify the SSL certificate chain.

Let's add `curl` to our derivation to debug and see what that says.

```console
> curl: (77) error setting certificate file: /no-cert-file.crt
```

Okay, so we need to set the SSL certificate file which might not be present.

Searching some exmaples and the documentation of OpenSSL looks like we _should_ set `SSL_CERT_FILE`.

```nix
env = {
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
};
```

Now `curl` passes, so it seems to successfully validate the TLS certificate chain _but the jekyll build is still failing_ 🤦‍♂️.

Looking _further_ online, there seems to be a second environment variable, `NIX_SSL_CERT_FILE`. Let's set that one too.

```nix
env = rec {
  SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  NIX_SSL_CERT_FILE = SSL_CERT_FILE
};
```

Okay great now everything builds 🎉.

Turns out that if you add the package `cacert` it includes a [setup-hook](https://github.com/NixOS/nixpkgs/blame/47c271667487cdcaa24c88d9b18b2df2bc47c30f/pkgs/data/misc/cacert/setup-hook.sh) that sets both of these environment variables.

```nix
nativeBuildInputs = with pkgs; [
  cacert
];
```

But, why are there **2** environment variables !?... 🤷

It's not particularly clear which packages respect one rather than the other. If you have insight into this, please comment on [nixpkgs#issue385955](https://github.com/NixOS/nixpkgs/issues/385955).

`NIX_SSL_CERT_FILE` is clear that it should work with OpenSSL via this [patch in nixpkgs](https://github.com/NixOS/nixpkgs/blob/release-24.11/pkgs/development/libraries/openssl/3.0/nix-ssl-cert-file.patch) that leverages it.

`curl` and `ruby` both use OpenSSL so why are their behavior divergent.

Nix migraine 🤕.