---
layout: post
title: 'Every package is already installed'
date: 2026-09-24 19:14 -0700
excerpt_separator: <!--more-->
---

> **tl;dr;** [omnibin](https://github.com/fzakaria/omnibin) is a FUSE filesystem that puts **every binary nixpkgs ever shipped** on your `$PATH`. Nothing is installed. Nothing needs building. 0 bytes on disk until something actually reads a file. 😈
{: .alert .alert-note }

It's 2026, why am I still installing packages individually?[^dhh]

[^dhh]: Yes, I am a little inspired after watching [DHH's keynote at RailsConf 2026](https://www.youtube.com/watch?v=vDjW_dRyKXY). I feel the same way about package management.

[![dhh yelling about how little he is doing](/assets/images/dhh_yelling_about_doing_little.png)](/assets/images/dhh_yelling_about_doing_little.png)
{: style="--image-width: 20rem"}

Why must I go through the ritual of adding a package to my `configuration.nix`, running `nix-shell` or succumb to the hellscape of `nix-env -iA`.

<!--more-->

Nix gives us the power of having packages installed side-by-side without conflict. Why do I have to pick which ones I want to install? 

Why can't I just have them all?

What if the machine just had all of them?

```console
$ nix run github:fzakaria/omnibin
omnibin: tree at /run/user/1000/omnibin, cache at /home/you/.cache/omnibin

$ ls /omnibin/bin | wc -l
51468

$ python3 --version
Python 3.14.6

$ python3@3.6.2 --version
Python 3.6.2
```

That is <u>over fifty thousand</u>[^larger] top-level binaries available on my `$PATH`, from 2013 to 2026 built by [Nixpkgs](https://github.com/NixOS/nixpkgs), available on-demand, without installing anything.

[^larger]: There are actually 881,933 binaries in the tree, but `ls /omnibin/bin` only lists the latest version of each binary. The versioned forms are still available, but they are not listed.

[![oprah shouting you get every version](/assets/images/oprah_every_version_omnibin.png)](/assets/images/oprah_every_version_omnibin.png)
{: style="--image-width: 20rem"}

This is the magic 🧙‍♂️ of [Nix](https://nixos.org), but it's not restricted to Nix.

Everyone seems to still love [Docker](https://www.docker.com/) and [OCI](https://www.opencontainers.org/), why am I still picking which base image to use? Why can't I just have them all?

```dockerfile
# syntax=docker/dockerfile:1
FROM fmzakari/omnibin:latest

COPY <<'SH' /demo.sh
python3@3.6.2 -c 'import sys; print(sys.version.split()[0])'
jq --version
gcc@10.2.0 --version | head -1
SH

CMD ["bash", "/demo.sh"]
```

Is this the ultimate agent harness? It's a container with everything in it, right from the start. Try it at [fmzakari/omnibin](https://hub.docker.com/r/fmzakari/omnibin).

```console
$ docker build -t example .
$ docker run --rm --device /dev/fuse --cap-add SYS_ADMIN example
3.6.2
jq-1.8.1
gcc (GCC) 10.2.0
```

Of course, I cannot forget our NixOS friends. You no longer have to curate your `environment.systemPackages` or `home.packages`, you can just have them all.

```nix
{
  imports = [ inputs.omnibin.nixosModules.default ];
  services.omnibin.enable = true;
}
```

What is "package management" if every package is already installed?

## What is this sorcery?

Turns out that Hydra writes a `.ls` file next to every single narinfo on [cache.nixos.org](https://cache.nixos.org) that describes the contents of the archive as JSON:

```console
$ curl -s --compressed https://cache.nixos.org/3n4qphl9s728sz8frmpqqrv9b1m87g68.ls | jq
{
  "root": {
    "entries": {
      "bin": {
        "entries": {
          "python3": { "target": "python3.14", "type": "symlink" },
          "python3.14": { "executable": true, "size": 14264, "type": "regular" }
```

That metadata turns out to be the perfect index for a [FUSE filesystem](https://www.kernel.org/doc/html/next/filesystems/fuse.html) that can lazily fetch the NARs from the cache and unpack them on-demand. 🤓

None of this would mean anything without [nixpkgs-multiverse]({% post_url 2026-08-09-nixpkgs-multiverse-every-version-that-ever-existed %}), which already resolves any `(attribute, version)` in nixpkgs history to the store path Hydra built for it on [cache.nixos.org](https://cache.nixos.org).

When you combine the two, you get a filesystem that can answer the question "where is `python3@3.6.2`" and then fetch it from the cache and unpack it for you, all without ever having to install it.

I crawled all of it the `.ls` files in under twelve minutes. 🤯

Once you have that, the filesystem writes itself:

```console
$ ls /nix/store/2lb6nn8ivk1alhckv43n7734lqwbw7h9-python3-3.6.2/bin
2to3      idle     pydoc     python   python3.6         python3-config  pyvenv
2to3-3.6  idle3    pydoc3    python3  python3.6-config  python-config   pyvenv-3.6
          idle3.6  pydoc3.6           python3.6m        python3.6m-config
```

That is CPython 3.6.2, from 2017. That `ls` _downloaded nothing_, it is answered from the pre-crawled index.

## Do not `ls` the tree

Agents are "a thing". Making them useful is a thing. Making them useful without installing anything is a thing.

If your agent tried to `ls /omnibin/bin` and stat every single entry, it would have a really bad time. There are 881,933 binaries in the tree, and it would take a long time to stat them all.

[![zoolander meme of saying how hot agents are](/assets/images/zoolander_omnibin_meme.png)](/assets/images/zoolander_omnibin_meme.png)
{: style="--image-width: 20rem"}

To help the agents out a bit, `ls /omnibin/bin` lists only the bare names, one per executable, each resolving to the newest package that provides it.

The versioned forms all resolve, but they are not listed. For example, `python3` resolves to the latest Python 3, which is 3.14.6 at the time of writing, but `python3@3.6.2` resolves to the 2017 version.

For everything else there is the index, which is sitting right there in the mount:

```console
$ sqlite3 /omnibin/index.db \
    "SELECT attr, version
    FROM bins
    WHERE name = 'python3'
    ORDER BY version"
```

That UX is a little rough, so you can also use the `omnibin` CLI to query the index:

```console
$ omnibin which python3
/nix/store/gxzhl7aaiid7zp3y47jqqiq7zg5mqpwp-python3-3.14.6/bin/python3

$ omnibin which --all python3 | wc -l
610

$ omnibin which --all ffmpeg | head -2
ffmpeg@3.1.7  ffmpeg  0.4 MB  /nix/store/0adpc3…-ffmpeg-3.1.7-bin/bin/ffmpeg
ffmpeg@3.2.4  ffmpeg  0.4 MB  /nix/store/nhfgdv…-ffmpeg-3.2.4-bin/bin/ffmpeg
```

Lastly, there is a `/omnibin/README.md` whose entire job is to tell whatever is exploring the filesystem to stop exploring the filesystem and query the database instead. 🤖

## What's the catch?

At this point it should be obvious, but you pay for this on startup for the first access.

```console
$ time python3@3.6.2 -c 'import sys; print(sys.version.split()[0])'
3.6.2
real    0m2.690s

$ time python3@3.6.2 -c 'print(6*7)'
42
real    0m0.035s
```

The first run took 2.7 seconds to fetch the NARs and unpack them, the second run was instantaneous because the store paths were already present.

Other than that? Not really, which is pretty amazing.

For any long-lived machine, you would expect your `/nix/store` to already be warmed up with the packages you need, so the first access penalty is not a big deal.

I remember one of the first things that blew my mind and sold me on Nix, was seeing a demo by [@burke](https://github.com/burke) on [comma](https://github.com/nix-community/comma). The capability to test a package, at a single nixpkgs revision, without "installing it"; revolutionary! I believe this to be a spiritual successor and I hope to imbue others with the same sense of wonder and amazement that I felt back then as a beacon of the power of Nix.

The repo is at [github.com/fzakaria/omnibin](https://github.com/fzakaria/omnibin).

Please `ls` responsibly.