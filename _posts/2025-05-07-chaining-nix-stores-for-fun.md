---
layout: post
title: Chaining Nix stores for fun
date: 2025-05-07 16:12 -0700
---

I recently realized that you can **chain** Nix _stores_ 🤯 -- although I'm not 100% clear on why I may want to do it.

Nevertheless, the concept is pretty cool -- and I'm sure I can come up with some interesting use-cases.

What do I even mean?

Well by default `nix` attempts to locate which "store" to use automatically:
1. Use the local store `/nix/store` if `/nix/var/nix` is writable by the current user.
2. If `/nix/var/nix/daemon-socket/socket` exists, connect to the Nix daemon listening on that socket.
3. For Linux only, use the local chroot store `~/.local/share/nix/root`, which will be created automatically if it does not exist.

You can be more _explicit_ and tell `nix` the store to use via `--store` on the CLI.

There are a variety of store types: _dummy_, _ssh_, _overlay-fs_, _s3_, _http_ and so on.

To test this out, I have created a new `nix daemon` which is listening on a new socket `/tmp/nix_socket_1`.

This _daemon_ will set it's store to `/tmp/chain-example`. When a filesystem store other than `/nix/store` is used, Nix will create `/nix/store` within it and `chroot` so that `/nix/store` appears to be the root.

> If you don't do this, then we cannot make use of all the pre-computed binaries offered by the NixOS cache. The documentation has a nice blurb on this [ref](https://nix.dev/manual/nix/2.28/store/types/local-store).

```console
> NIX_DAEMON_SOCKET_PATH=/tmp/nix_socket_1 nix daemon \
      --debug --store /tmp/chain-example
```

I know create a _second daemon_ that will listen on `/tmp/nix_socket_2` and whose store is `unix:///tmp/nix_socket_1`, the first daemon.

```console
> NIX_DAEMON_SOCKET_PATH=/tmp/nix_socket_2 nix daemon \
      --debug --store unix:///tmp/nix_socket_2
```

Now we can do our build!

We execute `nix build` but execute it against the _second daemon_ (`nix_socket_2`).

```bash
> nix build nixpkgs#hello \
    --store unix:///tmp/nix_socket_2 \
    --print-out-paths
# bunch of debug messages
/nix/store/y1x7ng5bmc9s8lqrf98brcpk1a7lbcl5-hello-2.12.1
```

Okay -- so we just tunneled our command through a daemon... cool?

Well we can maybe write an interceptor to log all the traffic and see what's going on.

Here we can use `socat` to pipe all the data to `nix_socket_1` but also `-v` will debug print everything.

```bash
> socat -v UNIX-LISTEN:/tmp/nix_socket_1,fork \
       UNIX-CONNECT:/tmp/nix_socket_2
```

I'm wondering whether it makes sense to support multiple "read" stores and only one that gets written to.

Although at this point I'm not sure about the distinction between _store_ and _substituters_...
