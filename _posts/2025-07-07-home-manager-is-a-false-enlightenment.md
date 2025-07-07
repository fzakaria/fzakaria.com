---
layout: post
title: home-manager is a false enlightenment
date: 2025-07-07 15:21 -0700
---

> This is sort of a response, or companion, piece to [@jade's](https://github.com/lf-) blog post ["You don't have to use Nix to manage your dotfiles
"](https://jade.fyi/blog/use-nix-less/). I highly recommend the read as well. 📖

One of the quick appeals and early exposures to [Nix](https://nixos.org) is through [home-manager](https://github.com/nix-community/home-manager) -- a framework for managing a user environment, primarily _dotfiles_, via Nix.

The seeming reproducibility of one's personal development environment is _intoxicating_. A common source of struggle for many developers becomes simple and straightforward with the power of Nix.

There is some [recent discourse](https://jade.fyi/blog/use-nix-less/) about the usefulness of managing dotfiles through Nix -- a common discussion in the community about the merits of Nix as a consequence for the complexity it induces.

While the use of home-manager does introduce a level of reproducibility that is missing from other dotfile management tools (i.e. [chezmoi](https://www.chezmoi.io/) or [rcm](https://github.com/thoughtbot/rcm)) by dependency edges from a graph to the necessary packages and tools it requires; those that leverage home-manager are [missing the forest through the trees](https://en.wiktionary.org/wiki/see_the_forest_for_the_trees#English).

> I am giving this opinion as someone who also [uses home-manager](https://github.com/fzakaria/nix-home) as I'm prone to pragmatism while I like to wax and wane on perfectionism. 🧘

Nix is designed around "packages", entries in the `/nix/store` and creating links between them. Symlinking into your `~` home folder breaks this philosophy and ruins the reproducibility we hope to achieve.

### A tale of two bats

Let's look at a small example with [bat](https://github.com/sharkdp/bat) and how we can adopt two _similar philosophies_ however one is in the spirit of Nix and has some profound implications.

We can enable `bat` and define a config for it via home-manager.

```nix
bat = {
  enable = true;
  config = {
    theme = "Dracula";
  };
};
```

This will make `bat` available on our `$PATH` and also create a `~/config/bat/config` with our theme, which the program is expected to read which is a symlink to a file in the `/nix/store`

```bash
> cat ~/.config/bat/config
--theme=Dracula

> ls -l ~/.config/bat/config
lrwxrwxrwx - fmzakari  7 Jul 15:44 /home/fmzakari/.config/bat/config -> /nix/store/fkr3bqlmds81i5122ypyn35486d5va6v-home-manager-files/.config/bat/config
```

Unfortunately with this approach there is no way to easily copy the `/nix/store` closure to another machine via `nix copy` and have my wonderful `bat` tool work correctly 😭.

Looks like `bat` has support to read from alternate locations that can be specified via `$BAT_CONFIG_PATH` [[ref](https://github.com/sharkdp/bat/blob/e2aa4bc33cca785cab8bdadffc58a4a30b245854/src/bin/bat/config.rs#L25)] 💡.

That means you could generate a wrapper for `bat` using [wrapProgram](https://nixos.org/manual/nixpkgs/stable/#fun-wrapProgram) to set this environment variable to the generated config file.

```nix
let batrc = ''
--theme=Dracula
'';
in
mkDerivation {
  # other fields omitted for brevity
  postFixup = ''
    wrapProgram "$out/bin/bat" \
      --set BAT_CONFIG_PATH : "${batrc}"
  '';
}
```

Some modules within home-manager adopt this pattern already such as `vim` 🕵️.

Here is a `vim` program configured with home-manager and we can see that it wraps the program and provides the `vimrc` file directly.

```bash
> cat $(which vim)
#! /nix/store/8vpg72ik2kgxfj05lc56hkqrdrfl8xi9-bash-5.2p37/bin/bash -e
exec "/nix/store/kjzs8h7bv3xck90m3wdb7gcb71i2w5sv-vim-full-9.1.1122/bin/vim" \
-u '/nix/store/1zbxnmk90iv9kbz3c7y9akdws3xywcj7-vimrc'  "$@" 
```

Why do this ? 🤔

I concur with [@jade's](https://github.com/lf-) that Nix should be more strictly used for "packages" and by coupling the configuration file with the program we are creating complete distinct **deployable** packages.

With the improvements made to `bat`, you could `nix copy` them onto another machine, or make them available via your flake, and have access to your esoteric setup wherever you are!

When possible, you should strive to remove as many files symlinked into your home folder. Upstream changes for programs that do not support providing their configuration file to make it possible -- or patch it since you are building from source! 🙃