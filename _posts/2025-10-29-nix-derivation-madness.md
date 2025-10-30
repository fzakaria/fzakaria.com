---
layout: post
title: Nix derivation madness
date: 2025-10-29 20:08 -0700
---

I've written _a bit_ about [Nix](https://nixos.org) and I still face moments where foundational aspects of the package system confounds and surprises me.

Recently I hit an issue that stumped me as it break some basic comprehension I had on how Nix works. I wanted to produce the build and runtime graph for the Ruby interpreter.

```bash
> nix-shell -p ruby

> which ruby
/nix/store/mp4rpz283gw3abvxyb4lbh4vp9pmayp2-ruby-3.3.9/bin/ruby

> nix-store --query --include-outputs --graph \
  $(nix-store --query --deriver $(which ruby))
error: path '/nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv' is not valid

> ls /nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv
ls: cannot access '/nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv':
No such file or directory
```

Huh. 🤔

I have Ruby but I don't seem to have the derivation, `24v9wpp393ib1gllip7ic13aycbi704g`, file present on my machine.

No worries, I think I can `--realize` it and download it from the NixOS cache.

```bash
> nix-store --realize /nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv
don't know how to build these paths:
  /nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv
error: cannot build missing derivation '/nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv'
```

I guess the NixOS cache doesn't seem to have it. 🤷

> This was actually perplexing me at this moment. In fact there are [multiple](https://discourse.nixos.org/t/how-to-get-a-missing-drv-file-for-a-derivation-from-nixpkgs/2300/1) [discourse](https://discourse.nixos.org/t/why-isnt-deriver-and-realize-identity-functions-see-example/47490/1) posts about it.

My mental model however of Nix though is that I must have first evaluated the derivation (drv) in order to determine the output path to even substitute. How could the NixOS cache not have it present?

Is this derivation wrong somehow? Nope. This is the derivation Nix believes that produced this Ruby binary from the `sqlite` database. 🤨

```bash
> sqlite3 "/nix/var/nix/db/db.sqlite" 
    "select deriver from ValidPaths where path = 
    '/nix/store/mp4rpz283gw3abvxyb4lbh4vp9pmayp2-ruby-3.3.9'"
/nix/store/24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv
```

What does the binary cache itself say? Even the cache itself thinks this particular derivation, `24v9wpp393ib1gllip7ic13aycbi704g`, produced this particular Ruby output.

```bash
> curl -s https://cache.nixos.org/mp4rpz283gw3abvxyb4lbh4vp9pmayp2.narinfo |\
  grep Deriver
Deriver: 24v9wpp393ib1gllip7ic13aycbi704g-ruby-3.3.9.drv
```

What if I try a different command? 

```bash
> nix derivation show $(which ruby) | jq -r "keys[0]"
/nix/store/kmx8kkggm5i2r17s6l67v022jz9gc4c5-ruby-3.3.9.drv

> ls /nix/store/kmx8kkggm5i2r17s6l67v022jz9gc4c5-ruby-3.3.9.drv
/nix/store/kmx8kkggm5i2r17s6l67v022jz9gc4c5-ruby-3.3.9.drv
```

So I seem to have a completely different derivation, `kmx8kkggm5i2r17s6l67v022jz9gc4c5`, that resulted in the same output which _is not_ what the binary cache announces. WTF? 🫠

Thinking back to a previous post, I remember touching on [modulo fixed-output derivations]({% post_url 2025-03-28-what-s-in-a-nix-store-path %}). Is that what's going on? Let's investigate from first principles. 🤓

Let's first create `fod.nix` which is our _fixed-output derivation_.

```nix
let
  system = builtins.currentSystem;
in derivation {
  name = "hello-world-fixed";
  builder = "/bin/sh";
  system = system;
  args = [ "-c" ''
    echo -n "hello world" > "$out"
  '' ];
  outputHashMode = "flat";
  outputHashAlgo = "sha256";
  outputHash = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9";
}
```

☝️ Since this is a _fixed-output derivation_ (FOD) the produced `/nix/store` path will not be affected to changes to the derivation beyond the contents of `$out`.

```bash
> nix-instantiate fod.nix
/nix/store/k2wjpwq43685j6vlvaarrfml4gl4196n-hello-world-fixed.drv

> nix-build fod.nix
/nix/store/ajk19jb8h5h3lmz20yz6wj9vif18lhp1-hello-world-fixed
```

Now we will create a derivation that uses this FOD.

```nix
{ fodDrv ? import ./fod.nix }:

let
  system = builtins.currentSystem;
in
builtins.derivation {
  name = "uses-fod";
  inherit system;
  builder = "/bin/sh";
  args = [ "-c" ''
    echo ${fodDrv} > $out
    echo "Good bye world" >> $out
  '' ];
}
```

The `/nix/store` for the output for this derivation _will change_ on changes to the derivation **except** if the derivation path for the FOD changes. This is in fact what makes it "modulo" the fixed-output derivations.

```bash
> nix-instantiate uses-fod.nix
/nix/store/85d15y7irq7x4fxv4nc7k1cw2rlfp3ag-uses-fod.drv

> nix-build uses-fod.nix
/nix/store/sd12qjak7rlxhdprj10187f9an787lk3-uses-fod
```

Let's test this all out by changing our `fod.nix` derivation.
Let's do this by just adding some _garbage_ attribute to the derivation.

```patch
@@ -4,6 +4,7 @@
   name = "hello-world-fixed";
   builder = "/bin/sh";
   system = system;
+  garbage = 123;
   args = [ "-c" ''
     echo -n "hello world" > "$out"
   '' ];
```

What happens now?

```bash
> nix-instantiate fod.nix
/nix/store/yimff0d4zr4krwx6cvdiqlin0y6vkis0-hello-world-fixed.drv

> nix-build fod.nix
/nix/store/ajk19jb8h5h3lmz20yz6wj9vif18lhp1-hello-world-fixed
```

The path of the derivation itself, `.drv`, has changed but the output path `ajk19jb8h5h3lmz20yz6wj9vif18lhp1` remains consistent.

What about the derivation that leverages it?

```bash
> nix-instantiate uses-fod.nix
/nix/store/85wkdaaq6q08f71xn420v4irll4a8g8v-uses-fod.drv

> nix-build uses-fod.nix
/nix/store/sd12qjak7rlxhdprj10187f9an787lk3-uses-fod
```

It also got a new derivation path but the output path remained unchanged. 😮

That means changes to _fixed-output-derivations_ didn't cause new outputs in either derivation _but_ it did create a complete new tree of `.drv` files. 🤯

That means in [nixpkgs](https://github.com/NixOS/nixpkgs) changes to _fixed-output_ derivations can cause them to have new store paths but result in dependent derivations to have the same path. If the output path had alreayd been stored in the NixOS cache, then we lose that information.

The amount of churn that we are creating in derivations was unbeknownst to me.

It can get even weirder! This example came from [@ericson2314](https://github.com/ericson2314).

We will duplicate the `fod.nix` to another file `fod2.nix` whose only difference is the value of the garbage.

```patch
@@ -4,7 +4,7 @@
   name = "hello-world-fixed";
   builder = "/bin/sh";
   system = system;
-  garbage = 123;
+  garbage = 124;
   args = [ "-c" ''
     echo -n "hello world" > "$out"
   '' ];
```

Let's now use both of these in our derivation.

```nix
{ fodDrv ? import ./fod.nix,
  fod2Drv ? import ./fod2.nix
}:
let
  system = builtins.currentSystem;
in
builtins.derivation {
  name = "uses-fod";
  inherit system;
  builder = "/bin/sh";
  args = [ "-c" ''
    echo ${fodDrv} > $out
    echo ${fod2Drv} >> $out
    echo "Good bye world" >> $out
  '' ];
}
```

We can now instantiate and build this as normal.

```bash
> nix-instantiate uses-fod.nix
/nix/store/z6nr2k2hy982fiynyjkvq8dliwbxklwf-uses-fod.drv

> nix-build uses-fod.nix
/nix/store/211nlyx2ga7mh5fdk76aggb04y1wsgkj-uses-fod
```

What is weird about that?

Well, let's take the JSON representation of the derivation and remove one of the inputs.

```bash
> nix derivation show \
    /nix/store/z6nr2k2hy982fiynyjkvq8dliwbxklwf-uses-fod.drv \
    jq 'values[].inputDrvs | keys[]'
"/nix/store/6p93r6x0bwyd8gngf5n4r432n6l380ry-hello-world-fixed.drv"
"/nix/store/yimff0d4zr4krwx6cvdiqlin0y6vkis0-hello-world-fixed.drv"
```

We can do this because although there are two input derivations, we know they both produce the same output!

```patch
@@ -12,12 +12,6 @@
       "system": "x86_64-linux"
     },
     "inputDrvs": {
-      "/nix/store/6p93r6x0bwyd8gngf5n4r432n6l380ry-hello-world-fixed.drv": {
-        "dynamicOutputs": {},
-        "outputs": [
-          "out"
-        ]
-      },
       "/nix/store/yimff0d4zr4krwx6cvdiqlin0y6vkis0-hello-world-fixed.drv": {
         "dynamicOutputs": {},
         "outputs": [
```

Let's load this modified derivation back into our `/nix/store` and build it again!

```bash
> nix derivation add < derivation.json
/nix/store/s4qrdkq3a85gxmlpiay334vd1ndg8hm1-uses-fod.drv

> nix-build /nix/store/s4qrdkq3a85gxmlpiay334vd1ndg8hm1-uses-fod.drv
/nix/store/211nlyx2ga7mh5fdk76aggb04y1wsgkj-uses-fod
```

Not only do we have a `1:N` trait for our output paths to derivations but we can also take certain derivations and completely change them by removing inputs and still get the same output! 😹

The road to Nix enlightenment is no joke and full of dragons.

