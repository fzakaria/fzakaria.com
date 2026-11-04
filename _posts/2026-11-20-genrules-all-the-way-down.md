---
layout: post
title: 'Genrules all the way down'
date: 2026-11-20 10:00 -0800
---

I remember having a chat with [@siggisim](https://github.com/siggisim), [BuildBuddy](https://buildbuddy.io) co-founder, that what made [Bazel](https://bazel.build) special at Google was not necessarily its technological-chops but rather Google's monorepo (`/google3/`) and their strict requirement that all third-party software be built and managed within that monorepo by Bazel.

Bazel has [gotten a lot wider adoption](https://www.webazel.dev/) outside of Google in recent years, especially with the increase code-authoring that has been ushered in by large language models. Although some package-specific libraries have made their way into the [Bazel Registry](https://registry.bazel.build/), the majority of third-party software is still hand-rolled for Bazel repeatedly by each organization or developer.

I asked [@siggisim](https://github.com/siggisim), _"Why is there no global monorepo for third-party software like Google has with `/google3/third_party`?"_

The closest thing to such a global monorepo for third-party software is [Nixpkgs](https://github.com/NixOS/nixpkgs), but it is not for Bazel. 😈

In [Build systems à la trace]({% post_url 2026-11-18-build-systems-a-la-trace %}) I recorded a Nix build with [Rewind](https://rewindvm.dev) and transpiled the recording into Bazel `genrule`s with the output being bit-for-bit identical to what Nix would have produced.

> **Aside**
> There was a _slight cheat_ in the approach. Every rule ran in a sandbox that mounted the host's `/nix/store`. GCC, glibc and zlib were just there. Bazel had no idea where they came from, so each converted package was an island.
{: .alert .alert-note}

The month prior I [compiled all of nixpkgs to TypeScript]({% post_url 2026-10-12-nixpkgs-for-the-frontend-impaired %}) because
any alternative Nix language needs to interop with twenty years of work encapsulated in nixpkgs to be useful.

What happens if I do the same but for Bazel?

What if I point [genrulify](https://github.com/fzakaria/genrulify) at Nixpkgs and create the largest Bazel workspace of `genrule`s ever?

<video autoplay loop muted playsinline width="400" height="300">
  <source src="/assets/images/genrule_ballmer_meme.mp4" type="video/mp4">
  <a href="/assets/images/genrule_ballmer_meme.mp4">Video: Steve Ballmer pacing a stage, clapping and chanting. The caption builds up to "genrules! genrules! genrules!"</a>
</video>

> **tl;dr**
> I have created the largest Bazel workspace of `genrule`s ever.
> [fzakaria/genrulify-nixpkgs](https://github.com/fzakaria/genrulify-nixpkgs) is a transpiled version of Nixpkgs into Bazel `genrule`s. At the moment it contains 219 packages as 2,386 `genrule`s as a demonstration of the approach.
{: .alert .alert-note }


## Mass converting nixpkgs

Originally `genrulify` sandbox mounted the host's `/nix/store`, and Bazel never actually had to manage the dependencies of GCC or glibc. To support many packages in one workspace, each store path has to be a proper Bazel target.

The recorded commands still use absolute paths though and this cannot change. The binaries have the `/nix/store` embedded in the `RUNPATH` and so forth, the binaries are [not yet relocatable]({% post_url 2026-06-21-nix-needs-relocatable-binaries %}). 

```python
cc_object(
    name = "s10006_gcc",
    src = ":s1268_tar/build/zlib-1.3.2/compress.c",
    out = "s10006_gcc/build/zlib-1.3.2/objs/compress.o",
    data = [":closure", "//genrulify:sandbox.sh", ...],
    cmd = [
        # …
        "/nix/store/xg9jq55q…-xgcc-16.2.0/bin/gcc -fPIC -O2 … -c -o objs/compress.o compress.c",
    ],
)
```

We still rely on Bazel to bind-mount the store paths at their expected locations in `/nix/store` before running the recorded commands, however the paths are now proper Bazel targets rather than relying on the host's store. The host's store is no longer mounted.

`:closure` lists every store path the command could read:

```python
filegroup(
    name = "closure",
    srcs = [
        "//store/xg9jq55qj9k603jabx1j5wwsgq7ma1bq-xgcc-16.2.0:path",
        "//store/h4wfwic161kxrr74jlzla5lsm28hgary-glibc-2.44-25:path",
        "//store/10dxp0qxqxxsyiljrh2kp0xqhz6arhcx-bash-5.3p15:path",
        # …
    ],
)
```

> **Aside**
> Unpacking a compiler for every action would cost more than the action. The sandbox script unpacks a NAR once into `/var/tmp/genrulify-store-$UID/<sha256 of the NAR>` and bind-mounts it at its `/nix/store` name. So Bazel ends up with a content-addressed store that it mounts at input-addressed paths, which is [the intensional model]({% post_url 2026-11-06-the-intensional-model-in-disguise %}) again, by accident.
{: .alert .alert-note }

To support partial migration, the workflow separates the conversion of individual packages from the linking of the entire workspace. This allows one to incrementally convert packages to Bazel `genrule`s without needing to have the entire workspace converted at once.

`genrulify convert` writes one package as `pkgs/NAME/BUILD.bazel` with no knowledge of other packages or the global store.
We then run `genrulify link` afterwards over the whole workspace to link all the converted packages together.

We convert each package to one of the following types:

1. A package in the workspace builds it, and the result matches the cache: `nix_built`.
2. [cache.nixos.org](https://cache.nixos.org) has it: `nix_fetched`.
3. Neither. The NAR is packed from the local store and checked in: `nix_source`.

<figure>
<svg viewBox="0 0 600 190" role="img" style="display:block;margin-inline:auto;max-width:40rem;width:100%;height:auto;font-family:var(--mono)"
     aria-label="Three boxes on the left feed one box on the right labelled //store/NAME:path. The first, nix_built, is an archive a package of the workspace builds, used when its hash equals the cache's. The second, nix_fetched, is an http_file from cache.nixos.org. The third, nix_source, is an archive kept in the workspace.">
  <g font-size="12" fill="var(--ink)">
    <rect x="8" y="10" width="330" height="46" rx="6" fill="none" stroke="var(--accent)" stroke-width="2"/>
    <text x="20" y="29" fill="var(--accent)">nix_built</text>
    <text x="20" y="46" fill="var(--ink-muted)">//pkgs/…-zlib-1.3.2:archive_out</text>
    <rect x="8" y="72" width="330" height="46" rx="6" fill="none" stroke="var(--ink)" stroke-width="1.5"/>
    <text x="20" y="91">nix_fetched</text>
    <text x="20" y="108" fill="var(--ink-muted)">http_file(cache.nixos.org/nar/….nar.zst)</text>
    <rect x="8" y="134" width="330" height="46" rx="6" fill="none" stroke="var(--ink)" stroke-width="1.5"/>
    <text x="20" y="153">nix_source</text>
    <text x="20" y="170" fill="var(--ink-muted)">store/NAME/nar, checked in</text>
    <rect x="420" y="72" width="172" height="46" rx="6" fill="none" stroke="var(--ink)" stroke-width="1.5"/>
    <text x="506" y="91" text-anchor="middle">//store/NAME:path</text>
    <text x="506" y="108" text-anchor="middle" fill="var(--ink-muted)">nar + nar.sha256</text>
  </g>
  <g stroke="var(--ink-muted)" stroke-width="1.5" fill="none">
    <path d="M338,33 C385,33 370,95 408,95"/>
    <path d="M338,95 L408,95"/>
    <path d="M338,157 C385,157 370,95 408,95"/>
  </g>
  <polygon points="408,90 418,95 408,100" fill="var(--ink-muted)"/>
</svg>
<figcaption>Every store path is one target. Where its bytes come from is decided at link time.</figcaption>
</figure>

Having a hermetic C++ toolchain as part of the build process is now trivial.

```python
# MODULE.bazel
http_file(
    name = "nar_5q6bdxkp7lc70gn9mnf4yiybrx8ry5xq",
    sha256 = "62a323202e2a0b91528b63359e8f9d12d2a1fcb74f14cd49a6fce2ec6192d2d4",
    urls = ["https://cache.nixos.org/nar/0z42bz5lk01cc8zyar0n1gb0s8rg139gqg0h7pz4ci5kqh784dms.nar.zst"],
)

# store/5q6bdxkp7lc70gn9mnf4yiybrx8ry5xq-gcc-16.2.0/BUILD.bazel
nix_fetched(
    name = "path",
    src = "@nar_5q6bdxkp7lc70gn9mnf4yiybrx8ry5xq//file",
    compression = "zstd",
    sha256 = "ba36820ec4b34446fe3d103cfcd2082f230dd60b1664e53f622c8049cb5f827c",
)
```

The `http_file` hash is of the compressed download. The `nix_fetched` hash is of the NAR inside it.
{: .aside}


The above is how GCC is converted and linked into the workspace.
The Bazel community has spent a decade trying to achieve hermetic C++ toolchains, and for Nixpkgs it is table stakes.

[![Oprah meme. Oprah points at her audience and shouts "You get an http_file! Everybody gets an http_file!"](/assets/images/genrule_oprah_http_file_meme.png)](/assets/images/genrule_oprah_http_file_meme.png)
{: style="--image-width: 22rem"}

## Why not all 74,957

Why did I only convert a subset of the 74,957 top-level derivations in Nixpkgs?

Because it is slow. I need more compute. 🤦

[genrulify](https://github.com/fzakaria/genrulify) works by running the build in [Rewind](https://rewindvm.dev) and forking the VM at each command to inspect the process and its filesystem, nine forks per command. Each fork takes 0.3 to 2 seconds depending on load, so the run converts about 70 derivations an hour on my machine.

All of nixpkgs at that rate is at least 45 days on one machine. 🙁

[![Waiting skeleton meme. A skeleton sits on a park bench, captioned "Me waiting for all 74,957 derivations".](/assets/images/genrule_waiting_skeleton_meme.png)](/assets/images/genrule_waiting_skeleton_meme.png)
{: style="--image-width: 16rem"}

## Is this useful?

Did I actually build the world's largest Bazel workspace? No.

Did the exploration though yield any insights? Yes.

Converting many packages revealed patterns and behaviors that were not obvious from individual derivations.

1. Bazel builds less than Nix would. Many packages only need a subset of their dependencies' commands to run, and Bazel only executes those. Having a finer granularity of execution allows Bazel to skip unnecessary work. 💪

2. Derivations are no longer the smallest unit of work. A single derivation can be split into multiple actions that Bazel schedules independently.

One honest challenging gap is that actions in Bazel are meant to be bit-reproducible by design, otherwise all caching benefit breaks. Since Nixpkgs does not enforce or guarantee bit-reproducibility, converting certain Nix derivations may cause Bazel actions to produce different outputs and avoid early cutoff optimizations.

If we throw enough compute power at the problem, and fix the non-bit-reproducible actions, Bazel could potentially build the entire workspace efficiently, leveraging its fine-grained scheduling and caching mechanisms.

What awaits us is the largest Bazel workspace ever constructed, in all its Nix glory.