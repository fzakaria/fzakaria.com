---
layout: post
title: Management Time
date: 2024-07-24 07:48 -0700
excerpt_separator: <!--more-->
---

> **Note**  
> This is the third ([part1]({% post_url 2024-05-03-speeding-up-elf-relocations-for-store-based-systems %}) & [part2]({% post_url 2024-07-21-scaling-past-1-million-elf-symbol-relocations %})) installment on my series of improving ELF symbol relocation processing.
Consider reading them if this post interests you. 📖

I have written [previously]({% post_url 2024-05-03-speeding-up-elf-relocations-for-store-based-systems %}) about [improvements]({% post_url 2024-07-21-scaling-past-1-million-elf-symbol-relocations %}) to the dynamic linking process, specifically processing relocations for entries with symbols.

The key insight into the improvements, that have let the dynamic linking process scale to 1 million relocation entries and up to **22x** speedup compared to the traditional methadology, is memoizing the relocation entries.

This memoization is possible since the linking order of the loader is _deterministic_ and in store-based systems such as [NixOS](https://nixos.org/) the libraries to be loaded are _fixed & static_.

<!--more-->

The key datastructure used to freeze the relocations is a relatively simple struct.

```c
typedef struct {
    int type;                   // Type of the relocation
    size_t addend;              // Addend of the relocation
    size_t st_value;            // Symbol value
    size_t st_size;             // Symbol size
    size_t offset;              // Offset of the relocation
    // 0-based index starting from the head of the DSO list
    size_t symbol_dso_index;
    // 0-based index starting from the head of the DSO list
    size_t dso_index;
    char symbol_name[255];       // Name of the symbol
    char symbol_dso_name[255];   // Name of the DSO
    char dso_name[255];          // Name of the DSO
} CachedRelocInfo;
```

These _fixed-width_ entries are serialized to a separate file that is told to the loader to be loaded through the use of an environment variable `RELOC_READ`

```console
❯ RELOC_READ='hello_world_relo.bin' hello_world
```

In practice, the binaries are _wrapped_ when deployed through NixOS so that this is all transparent to the user via a simple gesture in Nix.

```nix
optimized_hello_world =
     optimizeRelocationLinking {
        # You can pass any nixpkgs attribute here
        executable = hello_world;
    };
```

```bash
# Wrapped file hello_world-optimized
#! /nix/store/xxx-bash-5.2-p15/bin/bash -e
export RELOC_READ='/nix/store/xxx-patched_hello_world/bin/hello_world_relo.bin'
exec "/nix/store/xxx-patched_hello_world/bin/hello_world"  "$@" 
```

ℹ️ I've chosen to encode the cached relocation infos as a separate file since NixOS has solved the _multi-file update problem_; and I find having a separate file simpler to work with. The cached relocations could also be placed within a segment/section on the ELF file itself as well.

🕵️ Turns out though that having this information _frozen_ is not only useful to optimize the process itself but can be used for workflows relating to **auditing**, **validation** and **modification**.

Some of these workflows may occur today during *compile time* or *runtime*.
Performing them in between, has led us (coined by my advisor [Prof. Andrew Quinn](https://arquinn.github.io/)) to label it **management time**.

To demonstrate _management time_, I wrote a small Python utility [sak](https://github.com/fzakaria/musllibc/blob/management-time/examples/swiss-army-knife/sak.py) (swiss army knife).

## Converting to JSON/SQLite and back

The current file format is a binary protocol and not suitable for auditing. We can easily transform it to JSON or a SQLite database, to perform audits.

```console
❯ sak file-to-sqlite ./hello_world_relo.bin \
                     --db hello_world.sqlite

❯ sqlite3 hello_world.sqlite
sqlite> .mode json
sqlite> select * from CachedRelocInfo LIMIT 1;
[
  {
    "id": 1,
    "type": 7,
    "addend": 0,
    "st_value": 562266,
    "st_size": 193,
    "offset": 16336,
    "symbol_dso_index": 2,
    "dso_index": 1,
    "symbol_name": "puts",
    "symbol_dso_name": "/nix/store/xxx-musl/lib/libc.so",
    "dso_name": "/nix/store/xxx-libfoo/lib/libfoo.so"
  }
]
```
This file is a _frozen snapshot_ of the exact symbol bindings that will occur during process startup. If you've ever wanted to easily audit whether a particular CVE may have affected you, you can either construct a `jq` or `SQL` query to demonstrably prove it.

😮 You can even modify the JSON file or SQLite perform serializing it back to the binary format. You could change the binding of symbols effectively customizing the interposition (shadow) order. Effectively akin to Solaris's [direct binding](https://en.wikipedia.org/wiki/Direct_binding) but done during _management time_, as opposed to compile time.

> A workflow I am developing is supporting new libraries injected into the format so that you can do extremely targeted `LD_PRELOAD` equivalent workflows.

## Upgrades Made Easy

Knowing the surface area the transitive closure (_not just the application_) uses for a given library gives us a _fingerprint_ with which to test new libraries against whether they can be upgraded.

We can validate that we could replace a library with a different version, or even a different library that may offer the same symbols, without needing to run our application.

```console
❯ sak has-necessary-symbols hello_world_relo.bin \
        --new-library /nix/store/xxx-libfoo-1.1/lib/libfoo.so \
        --symbol-dso-name "/nix/store/xxx-libfoo-1.0/lib/libfoo.so"
The following symbols are missing:
bar
```

The power of this workflow boils down to a simple `LEFT JOIN` since the data is all present.

```sql
-- ELFSymbols is a table with the symbol entries solely
-- from the new library you are hoping to supplant with
SELECT cri.symbol_name
FROM CachedRelocInfo cri
LEFT JOIN ELFSymbols es
ON cri.symbol_name = es.symbol_name
WHERE es.symbol_name IS NULL AND
      cri.symbol_dso_name = <SYMBOL_DSO_NAME>
```

ℹ️ SQL is a powerful language to introspect binaries. Check out [sqlelf](https://github.com/fzakaria/sqlelf) for a more general utility. I have also published a paper on the benefits of using SQL to drive ELF analysis; [sqlelf: a SQL-centric Approach to ELF Analysis](https://arxiv.org/abs/2405.03883).

I have only begun to scratch the surface of the possibilities of _management time_. Having memoized linking information frozen within something like the _/nix/store_ for every package availble within [nixpkgs](https://github.com/NixOS/nixpkgs) opens pretty imaginative workflows that no other distribution could compete with 🤯.

We've all taken the underpinnings of our toolchain for granted. It's true we are building on the shoulders of giants, but it's imperative to look back and rethink decisions that may have existed for decades especially in-light of newer development models (i.e. NixOS) that offer us a chance to radically deviate from pre-existing conventions.