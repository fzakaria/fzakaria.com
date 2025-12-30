---
layout: post
title: 'Huge binaries: papercuts and limits'
date: 2025-12-30 08:34 -0800
---

In a [previous post]({% post_url 2025-12-28-huge-binaries %}), I synthetically built a program that demonstrated a relocation overflow for a `CALL` instruction.

However, the demo required I add `-fno-asynchronous-unwind-tables` to disable some additional data that might cause **other overflows** for the purpose of this demonstration.

What's going on? 🤔

This is a good example that only a select few are facing the size-pressure of massive binaries.

Even with `mcmodel=medium` which already is beginning to articulate to the compiler & linker: "Hey, I expect my binary to be pretty big."; there are surprising gaps where the linker overflows.

On Linux, an ELF binary includes many other sections beyond text and data necessary for code execution. Notably there are sections included for debugging (DWARF) and language-specific sections such as `.eh_frame` which is used by C++ to help unwind the stack on exceptions.

Turns out that even with `mcmodel=large` you might still run into overflow errors! 🤦🏻‍♂️

> **Note**
> Funny enough, there is a very recent opened issue for this with [LLVM #172777](https://github.com/llvm/llvm-project/issues/172777); perfect timing!
{: .alert .alert-note }

For instance, `lld`  assumes 32-bit `eh_frame_hdr` values regardless of the code model. There are similar 32-bit assumptions in the data-structure of `eh_frame` as well.

I also mentioned earlier about a pattern about using multiple GOT, Global Offset Tables, to also avoid the 31-bit (±2GiB) relative offset limitation.

Is there even a need for the large code-model?

How far can that take us before we are forced to use the large code-model?

Let's think about it:

First, let's think about any limit due to overflow accessing the multiple GOTs. Let's say we decide to space out our duplicative GOT every 1.5GiB.

```
|<---- 1.5GiB code ----->|<----- GOT ----->|<----- 1.5GiB code ----->|<----- GOT ----->|
```

That means each GOT can grow at most 500MiB before there could exist a `CALL` instruction from the code section that would result in an overflow.

Each GOT entry is 8 bytes, a 64bit pointer. That means we have roughly ~65 million possible entries.

A typical GOT relocation looks like the following and it requires 9 bytes: 7 bytes for the `movq` and 2 bytes for `movl`.

```assembly
movq    var@GOTPCREL(%rip), %rax  # R_X86_64_REX_GOTPCRELX
movl    (%rax), %eax
```

That means we have 1.5GiB / 9 = ~178 million possible _unique_ relocations.

So theoretically, we can require more **unique** symbols in our code section than we can fit in the nearest GOT, and therefore cause a relocation overflow. 💥

The same problem exists for thunks, since the thunk is larger than the relative call in bytes.

At some point, there is no avoiding the large code-model, however with multiple GOTs, thunks and other linker optimizations (i.e. LTO, relaxation), we have a lot of headroom before it's necessary. 🕺🏻