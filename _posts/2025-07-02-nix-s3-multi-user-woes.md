---
layout: post
title: Nix S3 multi-user woes
date: 2025-07-02 20:37 -0700
---

For the longest time before embarking on my [NixOS](https://nixos.org/) journey on my wonderful Framework 13 AMD laptop -- I was a **big** advocate for running Nix atop a traditional Linux distribution like Debian.

I loved the simplicity of it all. I got to have my cake and eat it too. 🍰

The cherry on top was that I would install Nix in [single user](https://nix.dev/manual/nix/2.28/installation/single-user) mode which was the default at first.

> I would `chown` the `/nix` directory to my user so I wouldn't even have to `sudo`. It was simple and fantastic.

Somehow along the way, the community has changed the default installation to the [multi user](https://nix.dev/manual/nix/2.28/installation/multi-user) mode which necessitates `systemd` and leverages a Nix daemon.

To be honest, I'm not clear why the change was made and it looks like others [are just as confused](https://discourse.nixos.org/t/what-are-the-specific-differences-between-and-perhaps-use-cases-for-single-user-and-multi-user-nix-installations/25671). 🤨

> Most uses of Nix are either on individual laptop or on ephemeral CI machines. Who are the majority of users on multi-user systems or mainframes that were the genesis for the default change?

This complexity came back recently when I tried to revive my old playbook of using AWS S3 as a binary cache -- [a topic I've written about before]({% post_url 2020-07-15-setting-up-a-nix-s3-binary-cache %})

I faced a variety of issues, and thought I'd write them here to hopefully save _you_ or _future me_ some time. 🤗

**problem**: I wanted to upload to my cache using `nix copy` on our CI runs but found that now the AWS credentials on my current user need to be pased to the daemon.

**solution**: Create a file at `/root/.aws/credentials` with the current AWS session.

```bash
sudo -E sh -c 'echo "[default]
    aws_access_key_id=$AWS_ACCESS_KEY_ID
    aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
    aws_session_token = $AWS_SESSION_TOKEN" \
> /root/.aws/credentials'
```

Annoyingly some commands seem to use your local user and others via the daemon which complicates knowing who needs the credential, especially if it's short lived via STS (AWS Security Token Service).

**problem**: I leveraged `nixConfig` in my `flake.json` but I wanted to avoid the prompt asking me to approve the binary cache on CI.

```nix
nixConfig = {
    extra-substituters = [
        "s3://my-super-secret-bucket"
    ];
    extra-trusted-public-keys = [
        "my-cache:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
    ];
};
```

**solution**: Add `--accept-flake-config` to your `nix` commands.

Don't forget, I also had to add myself as a `trusted-user` when I installed Nix.

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- install linux --no-confirm --init systemd \
    --extra-conf "trusted-users = $(whoami)"
```

**problem**: I wanted to validate that my binary cache was working so I wrote a simple package to test and validated it would pull from the cache with `--max-jobs 0`.

```nix
pkgs.writeText "text.txt" "hello world!"
```

**solution**: Unfortunately, the trivial builder `pkgs.writeText` purposefully avoids substitution because it's likely more expensive than rebuilding the file.

Use `writeTextFile` instead and make sure to enable `allowSubstitutes`.

```nix
pkgs.writeTextFile {
    name = "test.txt";
    text = "Hello World!";
    allowSubstitutes = true;
    preferLocalBuild = false;
};
```

**problem**: I want to build and cache all my `homeConfigurations`.

**solution**: Use `symlinkJoin` to create a _meta_ derivation that links them all together.

`homeConfigurations` are not nested usually within a particular system (i.e. `aarch64-linux`) so I make sure to filter the set of the current system with the `pkgs.system` attached to a given home-manager configuration.

```nix
all = nixpkgs.legacyPackages.${system}.linkFarm "all-home-configs-${system}" (
    nixpkgs.lib.mapAttrs
    (_: config: config.activationPackage)
    (nixpkgs.lib.filterAttrs (_: config: config.pkgs.system == system) self.homeConfigurations)
);
```
