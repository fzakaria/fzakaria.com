---
layout: post
title: Huge binaries
date: 2025-12-28 14:13 -0800
---

A problem I experienced when pursuing my PhD and submitting academic articles was that I had built solutions to problems that required dramatic scale to be effective and worthwhile. Responses to my publication submissions often claimed such problems did not exist; however, I had observed them during my time within industry, such as at Google, but I couldn't cite it!

One problem that is only present at these mega-codebases is _massive binaries_. What's the largest binary (ELF file) you've ever seen? I had observed binaries beyond 25GiB, including debug symbols. How is this possible? These companies prefer to statically build their services to speed up startup and simplify deployment. Statically including all code in some of the world's largest codebases is a recipe for massive binaries.

Similar to the sound barrier, there is a point at which code size becomes problematic and we must re-think how we link and build code. For x86_64, that is the 2GiB "Relocation Barrier."

Why 2GiB? 🤔

Well let's take a look at how position independent code is put-together.

Let's look at a simple example.

```c
extern void far_function();

int main() {
    far_function();
    return 0;
}
```

If we compile this `gcc -c simple-relocation.c -o simple-relocation.o` we can inspect it with `objdump`.

```bash
> objdump -dr simple-relocation.o

0000000000000000 <main>:
   0:	55                   	push   %rbp
   1:	48 89 e5             	mov    %rsp,%rbp
   4:	b8 00 00 00 00       	mov    $0x0,%eax
   9:	e8 00 00 00 00       	call   e <main+0xe>
			a: R_X86_64_PLT32	far_function-0x4
   e:	b8 00 00 00 00       	mov    $0x0,%eax
  13:	5d                   	pop    %rbp
  14:	c3                   	ret
```

There's a lot going on here, but one important part is `e8 00 00 00 00`. `e8` is the `CALL` opcode [[ref](https://c9x.me/x86/html/file_module_x86_id_26.html)] and it takes a **32bit signed relative offset**, which happens to be 0 (four bytes of 0) right now. `objdump` also lets us know there is a "relocation" necessary to fixup this code when we finalize it. We can view this relocation with `readelf` as well.

> **Note**
> If you are wondering why we need `-0x4`, it's because the offset is relative to the instruction-pointer which has already moved to the next instruction. The 4 bytes is the operand it has skipped over.
{: .alert .alert-note }

```bash
> readelf -r simple-relocation.o -d

Relocation section '.rela.text' at offset 0x170 contains 1 entry:
  Offset          Info           Type           Sym. Value    Sym. Name + Addend
00000000000a  000400000004 R_X86_64_PLT32    0000000000000000 far_function - 4
```

This is additional information embedded in the binary which tells the linker in susbsequent stages that it has code that needs to be fixed. Here we see the address `00000000000a`, and `a` is 9 + 1, which is the offset of the start of the operand for our `CALL` instruction.

Let's now create the C file for our missing function.

```c
void far_function() {
}
```

We will now compile it and link the two object files together using our linker.

```bash
> gcc simple-relocation.o far-function.o -o simple-relocation
```

Let's now inspect that same callsite and see what it has.

```bash
> objdump -dr simple-relocation

0000000000401106 <main>:
  401106:	55                   	push   %rbp
  401107:	48 89 e5             	mov    %rsp,%rbp
  40110a:	b8 00 00 00 00       	mov    $0x0,%eax
  40110f:	e8 07 00 00 00       	call   40111b <far_function>
  401114:	b8 00 00 00 00       	mov    $0x0,%eax
  401119:	5d                   	pop    %rbp
  40111a:	c3                   	ret

000000000040111b <far_function>:
  40111b:	55                   	push   %rbp
  40111c:	48 89 e5             	mov    %rsp,%rbp
  40111f:	90                   	nop
  401120:	5d                   	pop    %rbp
  401121:	c3                   	ret
```

We can see that the linker did the right thing with the relocation and calculated the relative offset of our symbol `far_function` and fixed the `CALL` instruction.

Okay cool...🤷 What does this have to do with huge binaries?

Notice that this call instruction, `e8`, only takes 32bits **signed** which means it's limited to 2^31 bits. This means a callsite can only jump roughly 2GiB forward or 2GiB backward. The "2GiB Barrier" represents the total reach of a single relative jump.

What happens if our callsite is over 2GiB away?

Let's build a synthetic example by asking our linker to place `far_function` _really really far away_. We can do this using a "linker script", which is a mechanism we can instruct the linker how we would like our code sections laid out when the program starts.

```
SECTIONS
{
    /* 1. Start with standard low-address sections */
    . = 0x400000;
    
    /* Catch everything except our specific 'far' object */
    .text : { 
        simple-relocation.o(.text.*) 
    }
    .rodata : { *(.rodata .rodata.*) }
    .data   : { *(.data .data.*) }
    .bss    : { *(.bss .bss.*) }

    /* 2. Move the cursor for the 'far' island */
    . = 0x120000000; 
    
    .text.far : { 
        far-function.o(.text*) 
    }
}
```

If we now try to link our code we will see a "relocation overflow".

> **TIP**
> I used `lld` from [LLVM](https://lld.llvm.org/) because the error messages are a bit prettier.
{: .alert .alert-tip }

```bash
> gcc simple-relocation.o far-function.o -T overflow.lds -o simple-relocation-overflow -fuse-ld=lld

ld.lld: error: <internal>:(.eh_frame+0x6c):
relocation R_X86_64_PC32 out of range:
5364513724 is not in [-2147483648, 2147483647]; references section '.text'
ld.lld: error: simple-relocation.o:(function main: .text+0xa):
relocation R_X86_64_PLT32 out of range:
5364514572 is not in [-2147483648, 2147483647]; references 'far_function'
>>> referenced by simple-relocation.c
>>> defined in far-function.o
```

When we hit this problem what solutions do we have?
Well this is a complete other subject on "code models", and it's a little more nuanced depending on whether we are accessing data (i.e. static variables) or code that is far away. A great blog post that goes into this is [the following](https://maskray.me/blog/2023-05-14-relocation-overflow-and-code-models) by [@maskray](https://github.com/maskray) who wrote `lld`.

The simplest solution however is to use `-mcmodel=large` which changes all the relative `CALL` instructions to absolute 64bit ones; kind of like a `JMP`.

```bash
> gcc simple-relocation.o far-function.o -T overflow.lds -o simple-relocation-overflow

> gcc -c simple-relocation.c -o simple-relocation.o -mcmodel=large -fno-asynchronous-unwind-tables

> gcc simple-relocation.o far-function.o -T overflow.lds -o simple-relocation-overflow

./simple-relocation-overflow
```

> **Note**
> I needed to add `-fno-asynchronous-unwind-tables` to disable some additional data that might cause overflow for the purpose of this demonstration.
{: .alert .alert-note }

What does the disassembly look like now?

```bash
> objdump -dr simple-relocation-overflow 

0000000120000000 <far_function>:
   120000000:	55                   	push   %rbp
   120000001:	48 89 e5             	mov    %rsp,%rbp
   120000004:	90                   	nop
   120000005:	5d                   	pop    %rbp
   120000006:	c3                   	ret

00000000004000e6 <main>:
  4000e6:	55                   	push   %rbp
  4000e7:	48 89 e5             	mov    %rsp,%rbp
  4000ea:	b8 00 00 00 00       	mov    $0x0,%eax
  4000ef:	48 ba 00 00 00 20 01 	movabs $0x120000000,%rdx
  4000f6:	00 00 00 
  4000f9:	ff d2                	call   *%rdx
  4000fb:	b8 00 00 00 00       	mov    $0x0,%eax
  400100:	5d                   	pop    %rbp
  400101:	c3                   	ret
```

There is no longer a sole `CALL` instruction, it has become `MOVABS` & `CALL` 😲. This changed the instructions from 5 (opcode + 4 bytes for 32bit relative offset) to a whopping 12 bytes (2 bytes for `ABS` opcode + 8 bytes for absolute 64 bit address + 2 bytes for `CALL`).

This has notable downsides among others:
* *Instruction Bloat*: We’ve gone from 5 bytes per call to 12. In a binary with millions of callsites, this can add up.
* *Register Pressure*: We’ve burned a general-purpose register, `%rdx`, to perform the jump.

> **Caution**
> I had a lot of trouble building a benchmark that demonstrated a worse lower IPC (instructions per-cycle) for the large `mcmodel`, so let's just take my word for it. 🤷
{: .alert .alert-caution }

Changing to a larger code-model is possible but it comes with these downsides. Ideally, we would like to keep our small code-model when we need it. What other strategies can we pursue?

More to come in subsequent writings.