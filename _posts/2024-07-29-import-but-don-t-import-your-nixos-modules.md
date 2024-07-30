---
layout: post
title: Import but don't import your NixOS modules
date: 2024-07-29 19:38 -0700
excerpt_separator: <!--more-->
---

> This is a follow-up post to my prior one [NixOS Option Inspection]({% post_url 2024-07-28-nixos-option-inspection %}). Many thanks to [@roberth](https://github.com/roberth) who followed up on my [issue](https://github.com/NixOS/nix/issues/11210) and helped explain it. 🙏

If you are using [NixOS](https://nixos.org), you've likely encountered the _module system_. It's NixOS's super-power and what makes it incredibly easy to share, reuse and configure systems based on Nix

```nix
{
  imports = [ ./hello.nix ];
  
  services.hello = {
    enable = true;
    greeter = "Bob";
  };
}
```

In a [prior post]({% post_url 2024-07-28-nixos-option-inspection %}), I wrote about how it can be challenging to work backwards ⏪ from a NixOS option's value to where it was defined.

Turns out, the answer in the post was _relatively simple_ and Nixpkgs has a gesture for discovering the answer via `definitionsWithLocations`.

Turns out, in order to get `definitionsWithLocations` to play nice, you have to avoid a suprisingly common [footgun](https://notes.rmhogervorst.nl/post/2022/11/21/what-is-a-footgun/) 🥵.

<!--more-->

Let's use an incredibly simple example to demonstrate the bug.

First let's make our module `greet.nix`; it's a trivial module with a single option. We also have a `config.nix` which you could think of as our `configuration.nix` in a typical NixOS installation.

```nix
# greet.nix
{...}: {
    greet.name = "hi";
}

# config.nix
let 
modules = {
  greet = import ./greet.nix;
};
system = {lib, ...}: {
  imports = [
    modules.greet
  ];

  options = {
    greet.name = lib.mkOption {
        type = lib.types.str;
    };
  };
};
in (import <nixpkgs/lib>).evalModules {
  modules = [ system  ];
}
```

Next, let's import this module, à la `imports` keyword attribute in a NixOS module. 

❗I have chosen to create a container attrset _modules_ to mimic what we might accomplish in a Nix Flakes.

Everything looks OK, and evaluates correctly.
```console
❯ nix-instantiate --eval config.nix -A config.greet.name
"hi"
```

If we try `definitionsWithLocations` however we don't get what we expected. 🤮

```console
❯ nix repl 
Nix 2.23.2
nix-repl> :l ./config.nix
Added 7 variables.

nix-repl> :p options.greet.name.definitionsWithLocations
[
  {
    file = "<unknown-file>";
    value = "hi";
  }
]
```

Did you spot the problem ? 🕵️‍♂️🧐🤔

It was the `import ./greet.nix` 🤯

We _imported_ the Nix expression into our modules container and as a result lost any traceability back to the originating file.

Luckily, the fix is simple! **Don't `import` within an `imports`** 👌

```nix
# This is better ✅
modules = {
  greet = ./greet.nix;
};

# This is also good ✅
imports = [
    ./greet.nix
];
```

With the applied fix, the results are what we want, and the world makes sense again. 😌

```console
❯ nix repl
Nix 2.23.2
Type :? for help.
nix-repl> :l ./config.nix                                
Added 7 variables.

nix-repl> :p options.greet.name.definitionsWithLocations
[
  {
    file = "greet.nix";
    value = "hi";
  }
]
```

How common is this _footgun_ ?

Turns out incredibly common (anecdotally) since there is nothing from preventing one from doing it; and it still "works". The Nix Flake's format makes this setup increasingly more common as well.

For a demonstration of how easy the fix is, I contributed a patch to [agenix](https://github.com/ryantm/agenix) in [#277](https://github.com/ryantm/agenix/pull/277) that fixes the issue.

```diff
diff --git a/flake.nix b/flake.nix
index 587138e..3a68940 100644
--- a/flake.nix
+++ b/flake.nix
@@ -23,13 +23,13 @@
   }: let
     eachSystem = nixpkgs.lib.genAttrs (import systems);
   in {
-    nixosModules.age = import ./modules/age.nix;
+    nixosModules.age = ./modules/age.nix;
     nixosModules.default = self.nixosModules.age;
 
-    darwinModules.age = import ./modules/age.nix;
+    darwinModules.age = ./modules/age.nix;
     darwinModules.default = self.darwinModules.age;
 
-    homeManagerModules.age = import ./modules/age-home.nix;
+    homeManagerModules.age = ./modules/age-home.nix;
     homeManagerModules.default = self.homeManagerModules.age;
 
     overlays.default = import ./overlay.nix;
```

**Don't `import` within an `imports`**