---
layout: post
title: 'Crazy shit linkers do: Common Data (COMDAT) sections'
date: 2026-02-03 09:49 -0800
---

Managing code at scale is hard and comes with a lot of weird quirks in your toolchain. I wrote [previously]({% post_url 2026-01-30-crazy-shit-linkers-do-relaxation %}) about some of the _crazy shit_ linkers can do and that is really the tip of the iceberg.

Let's take a peek at `COMDAT` (Common Data) sections and some of the weird hiccups you can run into.

What even is `COMDAT` ?

Well, to understand what a `COMDAT` section, let's create a simple example to demonstrate.

Consider this example where we will create a `Cache<T>` helper class and leverage it across two different translation units: `library.o` and `main.o`

> **Note**
> This example was inspired from [@grigorypas](https://github.com/grigorypas) on the discussion on the [LLVM discourse](https://discourse.llvm.org/t/rfc-lld-preferring-small-code-model-comdat-sections-over-large-ones-when-mixing-code-models/89550).
{: .alert .alert-note }

We can compile each individually such as `gcc -std=c++17 -g -O0 -c library.cpp -o library.o`. The -O0 is important here otherwise this simple code will be inlined, and `-std=c++17` allows us to use inline static variables.

```cpp
// cache.h
#pragma once

template<typename T>
struct Cache {
    inline static T data;
    static void set(T val) { data = val; }
};

// library.cpp
#include "cache.h"

void foo() {
    Cache<int>::set(42);
}

// main.cpp
#include "cache.h"

void bar() {
    Cache<int>::set(31);
}

extern void foo();

int main() {
    foo();
    bar();
    return 0;
}
```

Because `Cache<T>` is a template, the compiler must generate the machine code for `Cache<int>::set` in every object file (`.o`) that uses it. If you compile `main.cpp` and `library.cpp` and they both use `Cache<int>`, both object files will contain this code.

We can double check this with `objdump` and sure enough, both `main.o` and `library.o` contain a duplicate section, meaning the instructions, for `_ZN5CacheIiE3setEi` which is the mangled version of `Cache<int>::set`.

```
> objdump -d -j .text._ZN5CacheIiE3setEi main.o

Disassembly of section .text._ZN5CacheIiE3setEi:

0000000000000000 <_ZN5CacheIiE3setEi>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	89 7d fc             	mov    %edi,-0x4(%rbp)
   7:	8b 45 fc             	mov    -0x4(%rbp),%eax
   a:	89 05 00 00 00 00    	mov    %eax,0x0(%rip)
  10:	90                   	nop
  11:	5d                   	pop    %rbp
  12:	c3                   	ret


> objdump -d -j .text._ZN5CacheIiE3setEi library.o

Disassembly of section .text._ZN5CacheIiE3setEi:

0000000000000000 <_ZN5CacheIiE3setEi>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	89 7d fc             	mov    %edi,-0x4(%rbp)
   7:	8b 45 fc             	mov    -0x4(%rbp),%eax
   a:	89 05 00 00 00 00    	mov    %eax,0x0(%rip)
  10:	90                   	nop
  11:	5d                   	pop    %rbp
  12:	c3                   	ret
```

Wow! Given the prevailing use of templates in C++ -- this is already seemingly increadibly wasteful since every `.o` has to include the instructions for the same templates. 😲

At link time, the linker has to resolve the function use to one of these implementations.

What do we do with all the other duplicate implementations?

That's where `COMDAT` comes in! 🤓

To prevent your final binary from being 10x larger than necessary, the compiler marks these duplicate sections as `COMDAT` (Common Data). The linker's job is simple: pick one, discard the rest.

We can inspect these groupings using `readelf -g`.

```
> readelf -g main.o -W

COMDAT group section [    1] `.group' [_ZN5CacheIiE3setEi] contains 2 sections:
   [Index]    Name
   [    6]   .text._ZN5CacheIiE3setEi
   [    7]   .rela.text._ZN5CacheIiE3setEi
```

Here is the pickle. How does the linker pick which section to use?

Traditionally (not specified by any ABI), the linker selects the first `.o` provided to it on the command-line.

Is this problematic?

Well, what if the two object files were build with different code-models (i.e. `mcmodel`). Let's build `main.cpp` with large code-model `mcmodel=large`.

```
> gcc -g -O0 -mcmodel=large -c main.cpp -o main.o

> objdump -d -j .text._ZN5CacheIiE3setEi main.o

Disassembly of section .text._ZN5CacheIiE3setEi:

0000000000000000 <_ZN5CacheIiE3setEi>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	89 7d fc             	mov    %edi,-0x4(%rbp)
   7:	48 ba 00 00 00 00 00 	movabs $0x0,%rdx
   e:	00 00 00 
  11:	8b 45 fc             	mov    -0x4(%rbp),%eax
  14:	89 02                	mov    %eax,(%rdx)
  16:	90                   	nop
  17:	5d                   	pop    %rbp
  18:	c3                   	ret

> objdump -d -j .text._ZN5CacheIiE3setEi library.o

Disassembly of section .text._ZN5CacheIiE3setEi:

0000000000000000 <_ZN5CacheIiE3setEi>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	89 7d fc             	mov    %edi,-0x4(%rbp)
   7:	8b 45 fc             	mov    -0x4(%rbp),%eax
   a:	89 05 00 00 00 00    	mov    %eax,0x0(%rip)
  10:	90                   	nop
  11:	5d                   	pop    %rbp
  12:	c3                   	ret
```

Although the section names are the same, the instructions generated are now different. The large code-model uses `movabs` which has worse performance characteristics.

Let's verify what `lld` does by linking them.

```
# Link library.o first
> gcc library.o main.o -o a.out
> objdump -d a.out
0000000000401117 <_ZN5CacheIiE3setEi>:
  401117:	55                   	push   %rbp
  401118:	48 89 e5             	mov    %rsp,%rbp
  40111b:	89 7d fc             	mov    %edi,-0x4(%rbp)
  40111e:	8b 45 fc             	mov    -0x4(%rbp),%eax
  401121:	89 05 ed 2e 00 00    	mov    %eax,0x2eed(%rip)
  401127:	90                   	nop
  401128:	5d                   	pop    %rbp
  401129:	c3                   	ret

# Link main.o first
> gcc main.o library.o -o a.out
> objdump -d a.out
0000000000401141 <_ZN5CacheIiE3setEi>:
  401141:	55                   	push   %rbp
  401142:	48 89 e5             	mov    %rsp,%rbp
  401145:	89 7d fc             	mov    %edi,-0x4(%rbp)
  401148:	48 ba 14 40 40 00 00 	movabs $0x404014,%rdx
  40114f:	00 00 00 
  401152:	8b 45 fc             	mov    -0x4(%rbp),%eax
  401155:	89 02                	mov    %eax,(%rdx)
  401157:	90                   	nop
  401158:	5d                   	pop    %rbp
  401159:	c3                   	ret
```

We see that the section selected does depend on the `.o` order provided. 😬

Why does all this matter?

We are pursuing moving some code to the medium code-model to overcome some relocation overflows, however we have some prebuilt code built in the small code-model. We noticed that although our goal was to leverage the medium code-model, the linker might chose the small code-model variant of a section if it happened to be found first.

If the linker blindly picks the "small model" version (which uses 32-bit relative offsets) but places the data more than 2GB away, you won't just get the wrong performance characteristics—you will get a linker failure due to relocation truncation.

But wait, it gets worse.

The fact that we may instantiate multiple incarnations of a particular symbol but only select one is often known as the **One Definition Rule** (ODR). The ODR implies that the definition of a symbol must be identical across all translation units. But the linker generally doesn't check this (unless you use LTO, and even then, it's fuzzy). It just checks the symbol name.

Imagine if `library.cpp` was compiled with `-DLOGGING_ENABLED` which injected `printf` calls into `Cache::set`, while `main.cpp` was compiled in release mode without it.

If the linker picks the `main.o` (release) version of the `COMDAT` group, your "Debug" library implementation loses its logging features effectively muting your debug logic. Conversely, if it picks the `library.o` version, your high-performance release binary suddenly has debug logging in critical hot paths.

You aren't just gambling with instruction selection that may affect performance such as in the case of code-models; you are gambling with program logic. Given that the section name is purely based on the name of the symbol, it's easy to see that you can get yourself into oddities if you accidentally link implementations that wildly differ.