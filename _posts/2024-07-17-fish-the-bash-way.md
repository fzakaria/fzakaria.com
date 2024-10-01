---
layout: post
title: Fish the bash way
date: 2024-07-17 20:20 -0700
excerpt_separator: <!--more-->
---

I have been a big fan of the [fish shell](https://fishshell.com/) lately mostly because it delivers what it promises; _works out of the box™️_.

The **obvious downside** to fish is that it is non-standard POSIX `sh` -- meaning some (not all!) of the 1-line scripts you find on the Internet _may not work_.

> I use to be a pretty big _zsh_ fan but I hit enough oddities with my setup that I gave up in anger one day.  😤

<!--more-->

In practice, it should not that bad since scripts can set a shebang like `#! /usr/bin/env bash` to make sure they are portable. **In reality**, I've been bit too much by tools that run commands without explicitly setting the shell and relying on my login `$SHELL`. 🙅‍♂️🤯

Here is a little trick I've used to get the _best of both_.

1. Set your login shell to bash, _even though we intend to use fish_.

    ```nix
    users.extraUsers.fmzakari = {
        isNormalUser = true;
        shell = pkgs.bash;
        extraGroups = ["wheel" "networkmanager"];
        description = "Farid Zakaria";
    };
    ```
2. Set your `.bash_profile` or (`.bashrc` conditional on interactive shell) to exec into fish.

    ```nix
    bash = {
        enable = true;
        initExtra = ''
        # I have had so much trouble running fish as my login shell
        # instead run bash as my default login shell but just exec into it.
        # Check if the shell is interactive.
        if [[ $- == *i* && -z "$NO_FISH_BASH" ]]; then
            exec ${pkgs.fish}/bin/fish
        fi
        '';
    };
    ```
3. Create a bash function in fish that starts bash with the _secret_ environment variable `NO_FISH_BASH` so that we don't get into an endless loop.

    ```nix
    programs.fish = {
        enable = true;
        functions = {
            # to avoid going into a loop from bash -> fish -> bash
            # set the environment variable which stops that.
            bash = {
            body = ''
                NO_FISH_BASH="1" command bash $argv
            '';
            wraps = "bash";
            };
        };
    };
    ```

Now when you start your shell, via an interactive session, it will automatically exec into a fish shell 🎉.

**AND**

Your `$SHELL` remains bash, which means that any non-interactive use by programs will get the common bash they unfortunately implicitly rely on.

```console
❯ ps -p $fish_pid
    PID TTY          TIME CMD
  71116 pts/2    00:00:00 fish

❯ echo $SHELL
/run/current-system/sw/bin/bash

❯ bash -c "echo $SHELL"
/run/current-system/sw/bin/bash
```