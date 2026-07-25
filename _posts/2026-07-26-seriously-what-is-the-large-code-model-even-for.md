---
layout: post
title: Seriously, what is the large code-model even for?
date: 2026-07-26 18:59 -0700
---

I have been working on making _massive binaries_ possible at `$DAYJOB$`. One of the Hail Marys that you should be able to rely on is the large code-model (`mcmodel=large`) as it makes no assumptions about size and distance of relocations.

> **Large code model**: The large code model makes no assumptions about addresses and
> sizes of sections. [[cite](https://gitlab.com/x86-psABIs/x86-64-ABI)]

In a [previous post]({% post_url 2026-03-27-does-anyone-actually-use-the-large-code-model %}), I documented how I hit simple performance bottlenecks that made me believe that the code-model is largely theoretical in practice. In those cases, the fixes were evident and relatively small; however their omission was a hint at how no one uses the code-model because without them the performance penalty was a non-starter.

I hinted at some other ways I found the large code-model to still be lacking however I had not yet fully understood the pain of those failure modes.
I left a small teaser near the bottom about Thread Local Storage (`.tdata` / `.tbss`) being one of the "fun failure modes".

Turns out that it is worse than I thought. The instruction sequences the compiler emits for TLS are 32-bit _by construction_, and `-mcmodel=large` has nothing to swap them for. 🤦🏻‍♂️

To put that very bluntly, `mcmodel=large` is incapable of building complex large binaries despite its stated goal. 

### How do you even make a >2GiB binary?

The annoying part of this whole line of research is producing a test subject. Emitting 2GiB of _real_ instructions into `.text` is genuinely painful, you'd have to generate and assemble billions of instructions, and the object file is enormous. Beyond that the cardinality of the problem space grows when you consider whether the code is position-independent, do we use a procedure-linkage-table (PLT), TLS, GOT and all the various nuances each compiler brings with how they layout and order sections in their default linker scripts.

But relocation overflow isn't about how many bytes are on disk, it's about **virtual-address distance** between a reference and its target. So we have a few options.

Uninitialized globals land in `.bss`, which is a `NOBITS` section: it occupies virtual address space but **zero bytes on disk** (the same sparse-file trick I wrote about in [massively huge fake files]({% post_url 2026-02-11-creating-massively-huge-fake-files-and-binaries %})). So a few thousand 1MiB arrays gives us gigabytes of address space essentially for free.

We can synthetically produce this pretty easily with the following script.

```python
# N * 1-MiB globals, plus a function that touches each one
# so the compiler emits one relocation per array.
import sys
N, CHUNK = int(sys.argv[1]), 1024 * 1024
for i in range(N):
    print(f"char s{i}[{CHUNK}];")
print("long sum(void){ long a = 0;")
for i in range(N):
    print(f"  a += s{i}[0];")
print("  return a; }")
print("int main(void){ return (int)sum(); }")
```

```console?comments=true
$ python3 gen.py 4096 > huge.c
$ gcc -c huge.c -o huge.o
# 4 GiB of address space, 288 KiB on disk
$ du -h huge.o
288K    huge.o
```

Link it with the (default) small code-model and it falls over exactly where you'd expect, at the 2GiB signed-32-bit boundary:

```console
$ gcc -no-pie huge.o -o huge
huge.c:(.text+0x780f): relocation truncated to fit: R_X86_64_PC32 against symbol `s2048' ...
```

{: .aside}
`s2048` sits at `2048 * 1MiB` = precisely 2GiB.

Recompile the _same source_ with `-mcmodel=large` and it links cleanly:

```console
$ gcc -c -mcmodel=large huge.c -o huge_large.o
$ gcc -no-pie -mcmodel=large huge_large.o -o huge_large
```

The large model did its job: it replaced the 32-bit `R_X86_64_PC32` references with 64-bit `R_X86_64_GOTOFF64` sequences: a `movabs` of a 64-bit offset + an `add`.

The `.bss` trick is great for exercising the linker, but it's a little unsatisfying and overly synthetic. I often want to mimic relocation failures as they traverse a large `.text` segment.
We can leverage the assembler's `.fill` directive to repeat instructions. We can generate a tiny source of N functions spaced 1MiB apart with a `NOP` sea between them, plus one dispatcher that `call`s every function. This requires each `call` to have a relocation and the calls to functions past the 2GiB mark overflow. 🔥

<details markdown="1">
<summary>Generator: <code>gen_realtext.py</code></summary>

```python
# N tiny functions spaced 1 MiB apart, plus a dispatcher that calls each one.
# .fill is a memset, so the assembler emits the bytes without codegen.
import sys

N, CHUNK = int(sys.argv[1]), 1024 * 1024   # e.g. 4096 -> ~4 GiB of .text

print(".text")
print(".globl main")
print("main:")
for i in range(N):
    print(f"  call f{i}")               # one relocation per function
print("  ret")

for i in range(N):
    print(f".globl f{i}")
    print(f"f{i}:")
    print("  ret")
    print(f"  .fill {CHUNK}, 1, 0x90")   # 1 MiB of real NOP bytes -> real .text
```

</details>

### A quick primer on TLS access models

Now let's do the exact same thing, but using `__thread`.

When you access a thread-local variable, the compiler doesn't just load an address, it emits one of four _access models_, from fastest/least-flexible to slowest/most-flexible:

**Local Exec (LE)**
  : The variable lives in the main executable's own TLS block. The offset from the thread pointer (`%fs`) is a link-time constant, baked directly into the instruction as a 32-bit immediate; uses `R_X86_64_TPOFF32`.

**Initial Exec (IE)**
  : The variable is in a module loaded at startup. The 64-bit thread-pointer offset is stored in a **GOT slot**, and the code loads it with a RIP-relative reference; uses `R_X86_64_GOTTPOFF` to reach the slot & `R_X86_64_TPOFF64` to fill the slot.

**General Dynamic (GD)** / **Local Dynamic (LD)**
  : The fully general case for `dlopen`'d modules, a call into `__tls_get_addr`; uses `R_X86_64_TLSGD` & `R_X86_64_TLSLD`.

Notice the pattern: the value that reaches the thread pointer can be 64-bit (i.e. it lives in a GOT slot), but **every instruction that participates in a TLS access uses a 32-bit field**. `TPOFF32`, `GOTTPOFF`, `TLSGD`, `TLSLD` are all 32-bit.

<details markdown="1">
<summary>Generator: <code>gen_tls.py</code></summary>

```python
# Same as gen.py, but every array is thread-local (__thread) so it lands in
# .tbss and each access emits a TLS relocation instead of a plain data one.
import sys

N, CHUNK = int(sys.argv[1]), 1024 * 1024   # e.g. 4096 -> ~4 GiB of .tbss

for i in range(N):
    print(f"__thread char t{i}[{CHUNK}];")

print("long sum(void){ long a = 0;")
for i in range(N):
    print(f"  a += t{i}[0];")
print("  return a; }")
print("int main(void){ return (int)sum(); }")
```

</details>


```console
$ python3 gen_tls.py 4096 > tls_huge.c   # like gen.py but each array is `__thread`
$ gcc -c -mcmodel=large tls_huge.c -o tls_huge.o
$ du -h tls_huge.o
288K    tls_huge.o
```

4GiB of `.tbss`, still tiny on disk. Now look at the relocations the **large** code-model generated:

```console
$ readelf -r tls_huge.o | awk '{print $3}' | grep R_X86 | sort | uniq -c
      1 R_X86_64_GOTOFF64
      2 R_X86_64_GOTPC64
      2 R_X86_64_PC32
   4096 R_X86_64_TPOFF32
```

Every single TLS access is `R_X86_64_TPOFF32` which is **32-bit**, even under `-mcmodel=large`. 🫣

```console
$ gcc -no-pie -mcmodel=large tls_huge.o -o tls_huge
tls_huge.c:(.text+0x25): relocation truncated to fit: R_X86_64_TPOFF32 against symbol `t0' defined in .tbss ...
tls_huge.c:(.text+0x36): relocation truncated to fit: R_X86_64_TPOFF32 against symbol `t1' ...
```

The **exact same large code-model** that just happily linked 4GiB of ordinary `.bss` **fails** on 4GiB of `.tbss`.

This isn't a GNU quirk either. LLVM (`clang` & `lld`) does exactly the same thing, albeit with `lld`'s diagnostic being a bit friendly by printing the actual offset and the window it has to fit in:

```console
$ clang -c -mcmodel=large tls_huge.c -o tls_huge.o
$ clang -no-pie -fuse-ld=lld -mcmodel=large tls_huge.o -o tls_huge
ld.lld: error: tls_huge.o:(function sum: .ltext+0x17): relocation R_X86_64_TPOFF32
  out of range: -4294967296 is not in [-2147483648, 2147483647]; references 't0'
```

`-4294967296` is exactly `-4GiB`, `t0` sitting at the far bottom of the TLS block, and `[-2147483648, 2147483647]` is the signed 32-bit window `TPOFF32` has to live in. 

{: .aside}
`lld` even parks large-model code in a `.ltext` section.

### Why the large model is powerless here

I was a little confused at first: `R_X86_64_TPOFF64` **exists**. Why doesn't the compiler use it, especially with `mcmodel=large` ?

A relocation type **is glued to the specific field it patches** and is determined by the code-sequence emitted by the compiler. Here's the **local-exec** sequence `-mcmodel=large` emits:

```console
   4: 64 48 8b 04 25 00 00   mov    %fs:0x0,%rax
   d: 48 05 00 00 00 00      add    $0x0,%rax
                             R_X86_64_TPOFF32  x
  13: 8b 00                  mov    (%rax),%eax
```

The offset is applied with `add $imm32, %rax`. The x86-64 encoding for that instruction has **only a 32-bit immediate field**. There is no 64-bit form of it. The only relocation that can physically patch that field is a 32-bit one: `TPOFF32`.

So where _is_ `TPOFF64` used? It's not in the code (`.text`) at all. It lives as a dynamic relocation on the **GOT slot** used by **initial-exec**. The code side only holds the 32-bit `GOTTPOFF` that *points* at the slot:

```console
   4: 48 8b 0d 00 00 00 00   mov    0x0(%rip),%rcx
                             R_X86_64_GOTTPOFF  y
   b: 64 48 8b 04 25 00 00   mov    %fs:0x0,%rax
  14: 48 01 c8               add    %rcx,%rax
  17: 8b 00                  mov    (%rax),%eax
```

`TPOFF64` patches the 8-byte (64bit) _data word_ in the GOT. The instruction that _reaches_ that word (`GOTTPOFF`) is a 32-bit PC-relative relocation. So even initial-exec has a 32-bit link in the chain: the GOT slot must sit within 2GiB of the code. 😭


### It fails for exactly the mode it's meant for

**local-exec** is the mode you _want_ for a big statically-linked executable's own thread-locals. It's the fast path: the thread-pointer offset is a link-time constant, so the access is a direct `add $imm32` with no memory load, no GOT, no indirection. Unfortunately, `TPOFF32` is limited to 32bits and overflows.

{: .aside}
I would argue it's also the mode most likely to _need_ a large binary, since it's what a giant static executable uses for its own TLS.

What if we fall back to a slower mode? Unfortunately, each one of them has a 32-bit field too:

- **initial-exec** `GOTTPOFF` is 32-bit RIP-relative reach to the GOT slot.
- **general-dynamic** `TLSGD` is 32-bit RIP-relative.

The use of `GOTTPOFF` seems especially confusing. The large code-model already reaches the GOT at 64 bits everywhere else: GOTPC64 for the base, GOT64 for the slot, so the omission seems surprising. The 64-bit machinery is right there. TLS just doesn't use it. 🥲

### This is a hole in the ABI, not a compiler bug

After having dug into it, it's not simply a bug in GCC or LLVM. Look again at what `clang` emits for a single **local-exec** access under `-mcmodel=large`:

```console
   4: movq %fs:0x0, %rax
   d: addq $0x0, %rax           # R_X86_64_TPOFF32 x
  13: movl (%rax), %eax
```

It's a plain `addq $imm32, %rax`. There is nothing stopping clang from emitting a 64-bit form instead:

```
movabs $x@tpoff, %rdx      # a TPOFF64 in a movabs immediate
addq   %fs:0, %rdx
```

`TPOFF64` could patch that immediate, exactly the way `GOTOFF64` already patches a `movabs` immediate for ordinary data. 

Oddly, **the relocation type is not the missing piece.** What's missing is a _code sequence_ in the [x86-64 psABI](https://gitlab.com/x86-psABIs/x86-64-ABI) that uses a 64-bit TLS offset as an instruction immediate. The ABI simply never defined a large code-model TLS access model, so `TPOFF64`/`DTPOFF64` only ever appear in GOT slots, never in code, and no toolchain can emit what the spec doesn't describe.

The large code-model "exists", but it doesn't actually deliver arbitrarily-large binaries. For thread-local storage it can't, because the specification never defined how to.

This is one more reason I'm working toward making massive binaries possible. If you want to follow along, the discussion is over in the [x86-64-abi](https://groups.google.com/g/x86-64-abi/c/hz28LNnlBEc/m/J211uZASAgAJ) google-group where I've posted an RFC, and we have started an LLVM [Massive Binaries working group](https://discourse.llvm.org/t/rfc-forming-a-massive-binaries-working-group-in-lld/91031) and hold monthly meetings.
