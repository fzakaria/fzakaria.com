---
layout: post
title: 'Crazy shit linkers do: Relaxation'
date: 2026-01-30 20:55 -0800
---

I have been looking into linkers recently and I've been amazed at all the crazy options and optimizations that a linker may perform. Compilers are a well understood domain, taught in schools with a plethora of books but few resources exist for linkers aside from what you may find on some excellent technical blogs such as Lance Taylor's series on [writing the gold linker](https://www.airs.com/blog/archives/38) and Fangrui Song's, also known as MaskRay, [very in-depth blog](https://maskray.me/).

I wanted to write down in my own style, concepts I'm learning from _first principles_.

Recently, I came across a term "relaxation" as I was fuddling around LLVM's `lld`.

What is it? 🤔

> **Note**
> Relaxation looks to be _relatively new_, and the original RFC to the [x86-64-abi google group](https://groups.google.com/g/x86-64-abi/c/n9AWHogmVY0) was proposed in 2015.
{: .alert .alert-note }

Well, let's look at a super simple example to understand what it is and why we want it.

If you want to follow along take a look at this [godbolt](https://godbolt.org/z/oePn7c86n) example.

```c
// Declare it, but don't define it.
// The compiler assumes it might be in a shared library.
extern void external_function();

void example() {
external_function();
}
```

If we compile this with `-O0 -fno-plt -fpic -mcmodel=medium -Wa,-mrelax-relocations=no` we see the following disassembly in the object file using `objdump`.

```c
example():
 push   rbp
 mov    rbp,rsp
 call   QWORD PTR [rip+0x0]        # a <example()+0xa>
    R_X86_64_GOTPCREL external_function()-0x4
 pop    rbp
 ret
```

Specifically, the compile has left a "note" for the linker in the form of a _relocation_, specifically `R_X86_64_GOTPCREL`.

You can see that the address in the emitted code is `0x0` after compilation. The linker needs to replace that value with the address of the function from the GOT relative to the `rip` register (instruction pointer).

This works great and is necessary for shared libraries but what if we are building a final static binary? 🤓

Turns out that in some cases, this instruction can be further simplified by the linker since when producing the final executable binary it has _all_ the information.

We will have to see the actual instruction-code to understand this further.

If we look at the hexcode for that assembly we see the following:

```
ff 15 00 00 00 00 call *0x0(%rip)
```

This indirect call `call` (`ff`) via the GOT address is **6 bytes long** with 2 bytes for the opcode & 4 bytes belonging to the offset to the GOT entry.

> **Note**
> Understanding x86-64 is its own whole can of worms. The ISA is incredibly dense and complex, but if you want you can reference [it here](https://www.felixcloutier.com/x86/call).
{: .alert .alert-note }

x86-64 though has other `call` types (`e8`), that operate in a direct mode where it calls the address relative to the bytes presented.

This direct-mode `call` type is only **5 bytes** long with 1 byte for the opcode and 4 bytes for the offset to the function.

If we knew the location of the function ahead of time, it would be nice if we could skip checking the GOT completely and just go to where we want to be.

Why would we want to do this?

Well it's more efficient to directly jump to the address we want to end up directly. The CPU doesn't have to load the memory stored at the GOT before jumping to it.

When building a static binary the linker should know all the final relative addresses of all the functions, so going through the GOT is no longer necessary.

Since the number of bytes is nearly equal, the linker can effectively patch the binary without disrupting other relative calculations, provided it can fill the small gap.

We only need to find a _single byte_ to pad our more-efficient `call`! 🕵️

Turns out, the `nop` operation is only _a single byte_. 👌

We then get the equality:

```
call *foo@GOTPCREL(%rip) => [nop call foo] or [call foo nop]
```

This is what the `R_X86_64_GOTPCRELX` relocation indicates. It tells the linker it is safe to "relax" and modify the instructions to the more performant variation.



When we enable relaxation, we now generate the same code as above but with this new relocation type instructing the linker to perform the optimization if possible.

```c
 call   QWORD PTR [rip+0x0]        # a <example()+0xa>
    R_X86_64_GOTPCRELX external_function()-0x4
``` 
> **Note**
> Why not just always optimize `R_X86_64_GOTPCREL` when possible and forgo introducing a new relocation? My own guess is that it's important to be backwards compatible and you wouldn't want the emitted code to vary depending on the linker version but I would be interested to hear something more concrete if you know!
{: .alert .alert-note }

Interestingly that many linkers, optimize this even further!

Rather than generating a `nop` instruction, the linker instead prefixes the `call` with `0x67` (`addr32`).

On x86-64, `0x67` (`addr32`) usually implies 32-bit addressing for the operand. However, for a relative `call` instruction, it acts as a benign prefix that effectively ignores the override but also consumes exactly 1 byte.

If we go back to our example and enable relaxation, and produce a final binary, we can disassemble it to see whether it was relaxed.

```bash
> objdump -SD main

0000000000401133 <example>:
  401133:	55                   	push   %rbp
  401134:	48 89 e5             	mov    %rsp,%rbp
  401137:	48 8d 05 9a 2e 00 00 	lea    0x2e9a(%rip),%rax        # 403fd8 <_GLOBAL_OFFSET_TABLE_>
  40113e:	b8 00 00 00 00       	mov    $0x0,%eax
  401143:	67 e8 bd ff ff ff    	addr32 call 401106 <external_function>
  401149:	90                   	nop
  40114a:	5d                   	pop    %rbp
  40114b:	31 c0                	xor    %eax,%eax
  40114d:	c3                   	ret
```

Here we can see that in fact our `call` was relaxed since we can see `addr32 call 401106` 🥳.

As it happens, you can do this same "relaxation" optimization for a few other instructions such as `test`, `jmp` and `mov` but the basic premise is the same.