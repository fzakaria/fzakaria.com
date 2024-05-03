---
layout: post
title: Speeding up ELF relocations for store-based systems
date: 2024-05-03 16:41 +0000
excerpt_separator: <!--more-->
---

Since the introduction of Nix and similar store-based systems such as [Guix](https://guix.gnu.org/) or [Spack](https://spack.io/), I have been fascinated about finding improvements that take advantage of the new paradigms they introduce. Linux distributions are traditionally dynamic in nature, with shared libraries and executables being linked at runtime. Store-based systems, however, are static in nature, with all dependencies being resolved at build time. This determinism allows for not only reproducibility but also the ability to optimize various aspects of our toolchain.

Work that I've have [written previously]({% post_url 2022-03-14-shrinkwrap-taming-dynamic-shared-objects %}) about shows that there are worthwhile speedups that can be gained. While previously, I focused on improving the _stat storm_ that occurs when resolving dependencies, I have recently been looking at speeding up the ELF relocations that occur when executing a program.

> You can check out my publication [Mapping Out the HPC Dependency Chaos](https://arxiv.org/abs/2211.05118) about the development of [shrinkwrap](https://github.com/fzakaria/shrinkwrap) if you are interested in the topic.

Extending the idea further, I have been looking at how we can optimize the ELF relocations that occur when executing a program. In this post, I will discuss the basics of ELF relocations and symbol resolution and how we can optimize these processes for store-based systems.

<!--more-->

## ELF Relocations and Symbol Resolution

ELF (Executable and Linkable Format) files are the defacto format for executables and shared libraries on Linux systems. A crucial part of this structure involves relocations.

### What Are ELF Relocations?

Relocations are actions that the dynamic linker performs to connect symbolic references or addresses in the compiled program to actual physical addresses in memory during program execution.
These are necessary because the actual addresses where functions and data will reside in memory are not known at the time of compilation such as when code is making calls to external functions in shared libraries.

Suppose I have the two following files: `main.c` and `foo.c`.

```c
#include <stdio.h>

void foo() {
    printf("Calling the foo function.\n");
}
```

```c
#include <stdio.h>
#include <dlfcn.h>

extern void foo();

int main() {
    foo();
    return 0;
}
```

I setup a simple `Makefile` to create the shared-library and the executable. I additionally set _RPATH_ to the current directory to ensure the dynamic linker can find the shared library.

```makefile
CC = ../build/bin/musl-gcc
CFLAGS = -g -O0

libfoo.so: foo.c
    $(CC) $(CFLAGS) -o $@ -shared $^ '-Wl,--no-as-needed,--enable-new-dtags'

main: main.c libfoo.so
    $(CC) $(CFLAGS) -o $@ $^ -L. -lfoo '-Wl,--no-as-needed,--enable-new-dtags,-rpath,$$ORIGIN'
```

If we inspect the resulting executable file with _readelf_ we can see the relocations that are present, specifically the one for the `foo` function.

```console
❯ readelf -r main
...
Relocation section '.rela.plt' at offset 0x530 contains 5 entries:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
000000004000  000600000007 R_X86_64_JUMP_SLO 0000000000000000 foo + 0
```

There are various types of relocation structures (REL vs. RELA) and types (R_X86_64_JUMP_SLOT, R_X86_64_GLOB_DAT, etc.) that can be present in an ELF file.
I am concerned about JUMP_SLOT relocations, which are used to resolve function calls to shared libraries.

### Why Is Symbol Resolution Necessary?

When a program is loaded into memory, it might be placed at a different base address than the one for which it was originally compiled, more-so now that ASLR (Address space layout randomization) is the default. Additionally, it often depends on multiple shared libraries, which are also not fixed in memory ahead of time. The relocation entries in an ELF file tell the dynamic linker how to modify the program's code and data sections to correctly reference memory locations, whether they're functions or variables.

Symbol resolution is the process of finding the correct addresses for these symbolic references. For each undefined symbol in the program, the linker must search through all loaded libraries to find the correct definition. This process can be **time-consuming**, particularly when there are many symbols to resolve and multiple libraries to search through.

**How time consuming?**

Let's look at an extreme example where we dynamically link in a shared-object with 1000 to 1 million symbols.
Working with the [musl](https://www.musl-libc.org/) dynamic loader, I've augmented it to include timing information.

![basic nix-shell](/assets/images/relocation_time_graph_symbols.svg)

🤯 Relocation can take nearly **4.5 seconds** for **1 million** symbols!

Profiling the linker with _perf_ and visualizing the results with _FlameGraph_ (click the image below to explore), we can see that the majority (+60% of cycles) of the time is spent in symbol resolution in the _find_sym_ function.

[![flamegraph of unoptimized linker](/assets/images/flame_graph_unoptimized_linker.svg)](/assets/images/flame_graph_unoptimized_linker.svg)

The reason is that the cost of relocations is : O(R + nr log s), where R is the number of _relative_ relocations, n is the number of shared libraries, r is the number of named relocations, and s is the number of symbols.

In fact, the cost of relocations is even worse. Each check for a symbol involves a `strcmp` which is O(m); ELF and C/C++ (GNU GCC) have no upper-limit for the length of a symbol name. This means that the cost of relocations can be O(R + n log s*m).

> 🕵️ name-mangling for C++ means that the prefix for many symbols are common which necessitates checking most of the string during the `strcmp` if the symbols reside in the same class.

### Traditional Methods for Optimizing Symbol Resolution

A popular historic method for optimizing relocations involved the [prelink](https://wiki.gentoo.org/wiki/Prelink) tool that effectively performed all relocations ahead-of-time and saved the resulting
binary to disk. This method, however, has become obsolete with the advent of ASLR since the prelinked binary and it's dependent shared libraries are no longer loaded at the same base address.

The GNU toolchain includes an alternative symbol table `DT_GNU_HASH` that can be used to speedup symbol resolution. The main effecicieny improvement is to include a bloom-filter in the ELF file that can be used to quickly determine if a symbol is present in the symbol table. This can reduce the number of `strcmp` calls that are made and walking the symbol table.

The `DT_GNU_HASH` method is helpful but fundamentally fails to take advantage of the static nature of store-based systems. The symbol table is still loaded into memory and symbols must be re-resolved at runtime. Given the deterministic set of shared-libraries, we can do something similar to that of _prelink_ but with a twist. 🌀

## Optimizing ELF Relocations for Store-Based Systems

The major insight for store-based systems is that we can perform all symbol resolutions for relocations ahead-of-time and save the resulting binary to disk. This is similar to _prelink_ but with the twist that we are not performing the actual relocations but rather saving the resolved shared-object for each relocation.

This works on store-based systems, such as Nix, since the set of shared libraries is fixed and immutable.

Let's start of with the results of this optimization by looking at the _extreme case_ of 1 million symbols.

```console
❯ hyperfine --warmup 1 --runs 3 'DEBUG=1 RELOC_READ=1 ./1_million_functions.bin > /dev/null'
Benchmark 1: DEBUG=1 RELOC_READ=1 ./1_million_functions.bin > /dev/null
  Time (mean ± σ):     623.4 ms ±  15.1 ms    [User: 524.7 ms, System: 98.6 ms]
  Range (min … max):   608.1 ms … 638.3 ms    3 runs
```

🎆 We cutdown the time to run the program down from **4.5 seconds -> ~600 milliseconds**.

🏎️ That is a **7.5x speedup**! 🏎️

To achieve this improvement, I have a basic implementation built atop musl's dynamic loader.

1. I've added support for a new environment variable `RELOC_WRITE` that when set will write the resolved symbols for each relocation to disk in a file set by the variable.

    ```console
    ❯ RELOC_WRITE=relo.bin ./1_million_functions.bin &>/dev/null
    ```

    The resolves symbols are serialized as the simple structure below.

    ```c
    typedef struct {
      // Type of the relocation
      int type;
      // Symbol value which is typically the offset
      size_t st_value;
      // Offset of the relocation
      size_t offset;
      // Aboslute path of the DSO where symbol was found
      char symbol_dso_name[255];
      // Name of the DSO that needs the relocation
      char dso_name[255];
    } CachedRelocInfo;
    ```

    This file contains **all symbol relocations** for the binary and it's dependent shared libraries.

2. We add this serialized file to the ELF binary as a new section using _objcopy_

    ```console
    ❯ objcopy --add-section .reloc.cache=relo.bin \
        --set-section-flags .reloc.cache=noload,readonly 1_million_functions.bin  \
        1_million_functions.bin
    ```

3. Run the program again, and the dynamic linker will use the cached symbol resolutions if the section `.reloc.cache` is present.

    ```console
    ❯ ./1_million_functions.bin
    ```

    The dynamic linker will load the symbol resolutions and apply them to the relocations in the binary. The DSO names for each entry
    are needed so that the base address for the offset of the relocation and the symbol value can be calculated. This allows this
    optimization to work despite ASLR.

> 🕵️ Further optimizations can be done by removing the name of the shared objects in the structure and replacing it with an index
> into the array of shared objects that are loaded. This is possible since the load order of shared objects must be deterministic
> to ensure reproducibility for symbol resolution.

❗ This optimization is only possible for store-based systems since the set of shared libraries is fixed and immutable. In a traditional
Linux distribution, each shared library could be updated at any time, which would invalidate the cached symbol resolutions and their
offsets.

Store-based systems allow us to revisit many of the assumptions that have been made in the past and I believe can lead to either a simpler
or more efficient toolchain. So far, these systems have adopted the same assumptions, but hopefully with improvements such as this or
[shrinkwrap](https://github.com/fzakaria/shrinkwrap) we can begin to see the benefits of the new paradigms they introduce.
