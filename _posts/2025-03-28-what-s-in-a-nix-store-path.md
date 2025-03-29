---
layout: post
title: What's in a Nix store path
date: 2025-03-28 15:19 -0700
---

This is a follow up to my post on [nix vanity store paths]({% post_url 2025-03-27-nix-vanity-store-paths %}). Check it out if you want to jazz-up your `/nix/store` paths with some vanity prefixes ✨.

> ❗Warning this post goes into the nitty gritty of how Nix calculates the hashes for store paths. It assumes some base familiarity with Nix.

Learning [Nix](https://nixos.org), one of the things you first learn are that the hashes that are part of the `/nix/store` are input-derived or "pessimistic" as I like to refer to them as.

What does _input-derived_ (pessimistic) mean?

In contrast to something that is _content-addressed_ the hash is constructed from the contents of the derivation file rather than the bytes of the output. [[ref]](https://hydra.nixos.org/build/293701648/download/1/manual/store/derivation/outputs/input-address.html)

Since the derivations contain references to the source code and other derivation files, that means even the _teeniest change_, such as a comment, that might have no consequential change to the output artifact causes a whole new store path.

Since derivation files contain paths to other derivation files, these changes can easily cause massive rebuilds.

Consider this example that simply changes the derivation by adding a comment to the bash script.

```console
nix-repl> a = derivation { 
    name = "simple";
    builder = "/bin/sh";
    system = builtins.currentSystem;
    args = ["-c" ''                    
      # this is a comment
      echo "Hello World" > $out
    ''];  
    }

nix-repl> a
«derivation /nix/store/bk2gy8i8w1la9mi96abcial4996b1ss9-simple.drv»

nix-repl> :b a

This derivation produced the following outputs:
  out -> /nix/store/wxrsdk4fnvr8n5yid94g7pm3g2cr6dih-simple

nix-repl> b = derivation { 
    name = "simple";
    builder = "/bin/sh";
    system = builtins.currentSystem;
    args = ["-c" ''                    
      echo "Hello World" > $out
    ''];  
    }                                                                                                      
nix-repl> b
«derivation /nix/store/w4mcfbibhjgri1nm627gb9whxxd65gmi-simple.drv»

nix-repl> :b b

This derivation produced the following outputs:
  out -> /nix/store/r4c710xzfqrqw2wd6cinxwgmh44l4cy2-simple
```

The change in a inconsequential comment results in two distinct hashes: `wxrsdk4fnvr8n5yid94g7pm3g2cr6dih` and `r4c710xzfqrqw2wd6cinxwgmh44l4cy2`.

This pedantic pessimistic hashing is one of the _super-powers_ of Nix.

In my simple-brain I figured it simplified down to simply taking the hash of the _drv_ file.

```console
❌ $ nix-hash /nix/store/w4mcfbibhjgri1nm627gb9whxxd65gmi-simple.drv
```

Turns out it is a little more complicated and that components in the drv need to be _replaced_.

Confused ? 🤔 Let's see an example.

Let's take a detour and refresh ourselves about _fixed-output derivations_ (FOD).

Put simply, a FOD is a derivation with a fixed content-address.

You often see these in Nix expression when defining `src` since having the content-hash is one way to allow network access in a derivation.

```nix
derivation {
  name = "simple-fod";
  builder = "/bin/sh";
  system = builtins.currentSystem;
  args = [
    "-c"
    ''
      echo "Hello World" > "$out"
    ''
  ];
  outputHash = "sha256-0qhPS4tlCTfsj3PNi+LHSt1akRumTfJ0WO2CKdqASiY=";  
}
```

Instantiating this derivation gives us a derivation at `/nix/store/1g48s6lkc0cklvm2wk4kr7ny2hiwd4f1-simple-fod.drv`

```console
> nix-instantiate example.nix
/nix/store/1g48s6lkc0cklvm2wk4kr7ny2hiwd4f1-simple-fod.drv

> nix-store --realize /nix/store/1g48s6lkc0cklvm2wk4kr7ny2hiwd4f1-simple-fod.drv
/nix/store/3lx7snlm14n3a6sm39x05m85hic3f9xy-simple-fod
```

We can validate that the file has the same `outputHash`

```console
> nix-hash --type sha256 --flat \
    --base32 --sri \
    /nix/store/3lx7snlm14n3a6sm39x05m85hic3f9xy-simple-fod
sha256-0qhPS4tlCTfsj3PNi+LHSt1akRumTfJ0WO2CKdqASiY=
```

If we were to change that derivation slightly by adding a comment to the bash command.

```patch
@@ -5,7 +5,6 @@
   args = [
     "-c"
     ''
+      # This is a comment
       echo "Hello World" > "$out"
     ''
   ];
```

We get a completely new derivation path at `/nix/store/dn14xa8xygfjargbvqwqd2izrr7wnn1p-simple-fod.drv`.

```console
> nix-instantiate example.nix
/nix/store/dn14xa8xygfjargbvqwqd2izrr7wnn1p-simple-fod.drv

> nix-store --realize /nix/store/1g48s6lkc0cklvm2wk4kr7ny2hiwd4f1-simple-fod.drv
/nix/store/3lx7snlm14n3a6sm39x05m85hic3f9xy-simple-fod
```

This derivation however gives us the exact same final output (`3lx7snlm14n3a6sm39x05m85hic3f9xy`) when realized.

Let's recap! 📝 For _fixed-output deivations_ (FOD), you get **the same output paths** but **different derivation paths**.

Now let's construct a derivation that depends on this FOD.

```nix
derivation {
  name = "simple";
  builder = "/bin/sh";
  system = builtins.currentSystem;
  args = [
    "-c"
    ''
      cat ${simple-fod} > "$out"
    ''
  ];
}
```

If we were to inspect the JSON output of this derivation we would see
it depends on a single `inputDrv` which is that of `simple-fod`.

```jsonc
{
  "/nix/store/cf6b516yzc4xbm6ddg9b9mklqmxk2ili-simple.drv": {
    "args": [
      "-c",
      "cat /nix/store/3lx7snlm14n3a6sm39x05m85hic3f9xy-simple-fod > \"$out\"\n"
    ],
    // pruned for brevity
    "inputDrvs": {
      "/nix/store/1g48s6lkc0cklvm2wk4kr7ny2hiwd4f1-simple-fod.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      }
    },
  }
}
```

Turns out that if simply hashed the `drv` to calculate the store path then we would still need a rebuild if the fixed-output derivation path changed, even though it's output content has not! 😱

That would be a big bummer and defeat a lot of the purpose of having _fixed-output derivations_.

Aha! Turns out that when the hash of the derivation is calculated, the `inputDrv` paths are replaced with some other value. 😲

> n.b. I could not find any documentation of this replacement aside from code or the [PhD thesis](https://edolstra.github.io/pubs/phd-thesis.pdf).

By replacing the `inputDrv` when calculating the hash, the path is considered "modulo fixed-output derivation", meaning that the calculated path should **not change** if the derivation path for a fixed-output input changes.

Okay let's see if we can do this by hand 🔨. I love trying to learn things from _first principles_. 😎

The desired output path we want to derive is `/nix/store/n4sa1zr7y8y60wgsn1abyj52ksg1qjqc-simple`.

```bash
> nix derivation show \
  /nix/store/cf6b516yzc4xbm6ddg9b9mklqmxk2ili-simple.drv \
  | grep path
"path": "/nix/store/n4sa1zr7y8y60wgsn1abyj52ksg1qjqc-simple"
```

So let's take our derivation and perform the following:
1. clear out the `outputs.out` attribute
2. clear out the `env.out` environment variable
3. substitute the `inputDrv` with it's "replacement"

Our sole `inputDrv` is `/nix/store/1g48s6lkc0cklvm2wk4kr7ny2hiwd4f1-simple-fod.drv` which is a _fixed-output derivation_.

First we must construct the [fingerprint](https://hydra.nixos.org/build/293701648/download/1/manual/protocols/store-path.html) for it following the documentation which claims it should be `fixed:out:sha256:<base16 hash>:<store path>`.

```bash
# let's convert our SRI hash to base16
> nix hash convert --hash-algo sha256 --to base16 \
    --from sri \
    sha256-0qhPS4tlCTfsj3PNi+LHSt1akRumTfJ0WO2CKdqASiY=
d2a84f4b8b650937ec8f73cd8be2c74add5a911ba64df27458ed8229da804a26

# calculate the fingerprint
> echo -n "fixed:out:sha256:d2a84f4b8b650937ec8f73cd8be2c74add5a911ba64df27458ed8229da804a26:/nix/store/3lx7snlm14n3a6sm39x05m85hic3f9xy-simple-fod" | \
    sha256sum
1e9d789ac36f00543f796535d56845feb5363d4e287521d88a472175a59fb2d8
```

We have the replacement value `1e9d789ac36f00543f796535d56845feb5363d4e287521d88a472175a59fb2d8`.

We then take the original ATerm (`.drv`) for `simple` and clear out the out variables as mentioned earlier and replace the `inputDrv` with this replacement value.

I've added some pretty-printing below to make it slightly easier to read.

```nix
Derive(
    [("out", "", "", "")],
    [("1e9d789ac36f00543f796535d56845feb5363d4e287521d88a472175a59fb2d8", ["out"])],
    [],
    "x86_64-linux",
    "/bin/sh",
    ["-c", "cat /nix/store/3lx7snlm14n3a6sm39x05m85hic3f9xy-simple-fod > \"$out\"\n"],
    [
        ("builder", "/bin/sh"),
        ("name", "simple"),
        ("out", ""),
        ("system", "x86_64-linux")
    ]
)
```

Performing a `sha256sum` on this derivation give us `fbfae16395905ac63e41e0c1ce760fe468be838f1b88d9e589f45244739baabf`.

We then need to construct another _fingerprint_, hash it and compress it down to 20 bytes 😭.

I could not seem to find an analagous CLI utility [[ref]](https://github.com/NixOS/nix/blob/fd98f30e4ea652070553c901aaa7557f79bde76b/src/libutil/hash.cc#L387C1-L394C2) to perform the compression, but we can easily create a simple Go program to compute it mimicing the C++ reference code.

> 🤷 I am not sure why the hash has to be compressed or the fingerprint itself needs to be hashed. The fingerprint itself should be stable prior to hashing.

```c++
Hash compressHash(const Hash & hash, unsigned int newSize)
{
    Hash h(hash.algo);
    h.hashSize = newSize;
    for (unsigned int i = 0; i < hash.hashSize; ++i)
        h.hash[i % newSize] ^= hash.hash[i];
    return h;
}
```

```bash
# hash this final fingerprint
> echo -n "output:out:sha256:fbfae16395905ac63e41e0c1ce760fe468be838f1b88d9e589f45244739baabf:/nix/store:simple" |\
     sha256sum
0fb43a8f107d1e986cc3b98d603cf227ffa034b103ff26118edf5627387343fc
```

Using [go-nix](https://github.com/nix-community/go-nix) we can write a small CLI utility to do the final compression and emit the `/nix/store` path.

```golang
func main() {
	hash := "0fb43a8f107d1e986cc3b98d603cf227ffa034b103ff26118edf5627387343fc"
	raw, _ := hex.DecodeString(hash)
	compressed := nixhash.CompressHash(raw, 20)
	path := "/nix/store/" + nixbase32.EncodeToString(compressed) + "-" + "simple"
	fmt.Println(path)
}
```

Running this outputs our expected value `/nix/store/n4sa1zr7y8y60wgsn1abyj52ksg1qjqc-simple` 🙌🏾

Wow calculating the `/nix/store` path was way more involved than what I originally thought, which was "simply hashing the derivation".

Demystifying Nix is pretty fun but there is definitely a lack of documentation beyond the thesis for how it all works.

I found other Nix implementations, beyond [CppNix](https://github.com/nixos/nix), such as [go-nix](https://github.com/nix-community/go-nix) helpful in understanding the steps needed.