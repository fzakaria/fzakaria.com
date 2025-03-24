---
layout: post
title: Nix derivations by hand
date: 2025-03-23 20:19 -0700
---

My recent posts on _dynamic-derivations_ had me thinking more about working with [Nix](https://nixos.org) more directly.

I thought it might be "fun" 🙃 to try and write a derivation by hand, add it to the `/nix/store` and build it!

Can we even do this? 🤔 Let's see!

First off, all derivations in the `/nix/store` are written in this simple but _archaic_ format called [ATerm](https://homepages.cwi.nl/~daybuild/daily-books/technology/aterm-guide/aterm-guide.html).

Tooling for it is a bit lackluster, so I decided to work purely in JSON!.

Looks like the new `nix derivation` command can accept JSON rather than the ATerm format.

Okay! Let's start _deriving_ 🤓

The [Nix manual](https://nix.dev/manual/nix/2.25/language/derivations) let's us know that we need 3 **required** arguments: name, system & builder

```json
{
  "name": "simple",
  "system": "x86_64-linux",
  "builder": "/bin/sh"
}
```

```console
> nix derivation add < simple.json 
error:
  … while reading key 'outputs'
  error: Expected JSON object to contain key 'outputs'
  but it doesn't...
```

Okay let's add an output. I checked the [derivation JSON format](https://nix.dev/manual/nix/2.21/protocols/json/derivatio) on the Nix manual to see what it looks like.

I just put some random 32 letter path I came up for now.

```json
{
  "name": "simple",
  "system": "x86_64-linux",
  "builder": "/bin/sh",
  "outputs": {
    "out": {
      "path": "/nix/store/7s0z3d6p9y2v5x8b1c4g1w5r2q9n0f8a-simple"
    }
  }
}
```

```console
> nix derivation add < simple.json
error:
  … while reading key 'inputSrcs'
  error: Expected JSON object to contain
  key 'inputSrcs' but it doesn't:...
```

Okay, well I don't want any inputs.. 🤨
Let's leave it blank for now.

> **inputSrcs**: A list of store paths on which this derivation depends.

```json
{
  "name": "simple",
  "system": "x86_64-linux",
  "builder": "/bin/sh",
  "outputs": {
    "out": {
      "path": "/nix/store/7s0z3d6p9y2v5x8b1c4g1w5r2q9n0f8a-simple"
    }
  },
  "inputSrcs": []
}
```

```console
> nix derivation add < simple.json
error:
  … while reading key 'inputDrvs'
  error: Expected JSON object to contain
  key 'inputDrvs' but it doesn't:...
```

Let's keep following this thread and add the missing `inputDrvs`.

> **inputDrvs**: A JSON object specifying the derivations on which this derivation depends, and what outputs of those derivations.

Turns out we also need `env` and `args`. `args` is particularly useful, since can use it to `echo hello world` to `$out` making our derivation meaningful.

```json
{
  "name": "simple",
  "system": "x86_64-linux",
  "builder": "/bin/sh",
  "outputs": {
    "out": {
      "path": "/nix/store/7s0z3d6p9y2v5x8b1c4g1w5r2q9n0f8a-simple"
    }
  },
  "inputSrcs": [],
  "inputDrvs": {},
  "env": {},
  "args": [
    "-c",
    "echo 'hello world' > $out"
  ]
}
```

```console
> nix derivation add < simple.json
error: derivation '/nix/store/03py9f4kw48gk18swsw6g7yjbj21hrsw-simple.drv'
has incorrect output '/nix/store/7s0z3d6p9y2v5x8b1c4g1w5r2q9n0f8a-simple',
should be '/nix/store/hpryci895mgx4cfj6dz81l6a57ih8pql-simple'
```

That's helpful! Thank you for telling me the correct hash.

Giving the correct hash will probably be useful for AI-centric workflows, so they can fix their own mistakes. 😂

```json
{
  "name": "simple",
  "system": "x86_64-linux",
  "builder": "/bin/sh",
  "outputs": {
    "out": {
      "path": "/nix/store/hpryci895mgx4cfj6dz81l6a57ih8pql-simple"
    }
  },
  "inputSrcs": [],
  "inputDrvs": {},
  "env": {},
  "args": [
    "-c",
    "echo 'hello world' > $out"
  ]
}
```

```console
> nix derivation add < simple.json
error: derivation '/nix/store/pz7m6zp2hxjldxq8jp846p604qicn73d-simple.drv'
has incorrect environment variable 'out',
should be '/nix/store/hpryci895mgx4cfj6dz81l6a57ih8pql-simple'
```

Okay this makes sense. I'm using `$out` in my `builder` but I never set it to anything in the environment variables. Let's fix that by adding it to our derivation explicitly.

We will also have to fix our path to be `5bkcqwq3qb6dxshcj44hr1jrf8k7qhxb` which Nix will dutifully tell us is the right hash.

```json
{
  "name": "simple",
  "system": "x86_64-linux",
  "builder": "/bin/sh",
  "outputs": {
    "out": {
      "path": "/nix/store/5bkcqwq3qb6dxshcj44hr1jrf8k7qhxb-simple"
    }
  },
  "inputSrcs": [],
  "inputDrvs": {},
  "env": {
    "out": "/nix/store/5bkcqwq3qb6dxshcj44hr1jrf8k7qhxb-simple"
  },
  "args": [
    "-c",
    "echo 'hello world' > $out"
  ]
}
```

```console
> nix derivation add < simple.json
/nix/store/vh5zww1mqbcshfcblrw3y92v7kkzamfx-simple.drv
```

Huzzah! Nix accepted our derivation. 🎉

Can we build it?

```console
> nix-store --realize /nix/store/vh5zww1mqbcshfcblrw3y92v7kkzamfx-simple.drv
this derivation will be built:
  /nix/store/vh5zww1mqbcshfcblrw3y92v7kkzamfx-simple.drv
building '/nix/store/vh5zww1mqbcshfcblrw3y92v7kkzamfx-simple.drv'...
warning: you did not specify '--add-root'; the result might be removed by the garbage collector
/nix/store/5bkcqwq3qb6dxshcj44hr1jrf8k7qhxb-simple

> cat /nix/store/5bkcqwq3qb6dxshcj44hr1jrf8k7qhxb-simple
hello world
```

Success! 🤑 We got our expected output as well.

You might be curious why I did `/bin/sh` instead of something like `/bin/bash` ?

Well I wante dto keep our derivation _extremely simple_ and even something like `bash` needs to be an explicit dependency on our derivation.

Turns out though that `/bin/sh` is by default always present in the Nix sandbox for POSIX compliance. 🤓