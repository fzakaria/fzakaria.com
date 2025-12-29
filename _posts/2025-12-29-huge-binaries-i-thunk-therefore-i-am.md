---
layout: post
title: 'Huge binaries: I thunk therefore I am'
date: 2025-12-29 08:15 -0800
---

In my [previous post]({% post_url 2025-12-28-huge-binaries %}), we looked at the "sound barrier" of x86_64 linking: the 32-bit relative `CALL` instruction and how it can result in relocation overflows. Changing the code-model to `-mcmodel=large` fixes the issue but at the cost of "instruction bloat" and likely a performance penalty although I had failed to demonstrate it via a benchmark 🥲.

Surely there are other interesting solutions? 🤓

First off, probably the simplest solution is to not statically build your code and rely on dynamic libraries 🙃. This is what most "normal" software-shops and the world does; as a result this hasn't been such an issue otherwise.

This of course has its own downsides and performance implications which I've written about and produced solutions for (i.e., [Shrinkwrap]({% post_url 2022-03-14-shrinkwrap-taming-dynamic-shared-objects %}) & [MATR]({% post_url 2024-05-03-speeding-up-elf-relocations-for-store-based-systems %})) via my doctorate research. Beyond the performance penalty induced by having thousands of shared-libraries, you lose the simplicity of single-file deployments.

A more advanced set of optimizations are under the umbrella of "LTO"; Link Time Optimizations. The linker at the final stage has all the information necessary to perform a variety of optimizations such as code inlining and tree-shaking. That would seem like a good fit except these huge binaries would need an enormous amount of RAM to perform LTO and cause build speeds to go to a crawl.

> **Tip**
> This is still an active area of research and Google has authored [ThinLTO](https://research.google/pubs/thinlto-scalable-and-incremental-lto/). Facebook has its own set of profile guided LTO optimizations as well via [Bolt](https://research.facebook.com/publications/bolt-a-practical-binary-optimizer-for-data-centers-and-beyond/).
{: .alert .alert-tip }

What if I told you that you could keep your code in the fast, 5-byte small code-model, even if your binary is 25GiB for most callsites. 🧐

Turns out there is prior art for "Linker Thunks" [[ref](https://github.com/llvm/llvm-project/blob/main/lld/ELF/Thunks.cpp)] within LLVM for various architectures -- notably missing for `x86_64` with a quote:

> "i386 and x86-64 don't need thunks" [[ref](https://github.com/llvm/llvm-project/blob/144dc7464fcfde796401acf7784e084d0e66d15c/lld/ELF/Thunks.cpp#L19C4-L19C38)]

What is a "thunk" ?

You might know it by a different name and we use them all the time for _dynamic-linking_ in fact; a trampoline via the procedure linkage table (PLT).

A thunk (or trampoline) is a linker-inserted shim that lives within the immediate reach of the caller. The caller branches to the thunk using a standard relative jump, and the thunk then performs an absolute indirect jump to the final destination.

<!-- 

\documentclass[tikz, border=10pt]{standalone}
\usetikzlibrary{positioning, arrows.meta, calc, shapes.multipart, bending}

\begin{document}
\begin{tikzpicture}[
    font=\sffamily,
    % Styles for the labels on the left column
    addr/.style={font=\ttfamily\small, text=gray, anchor=east},
    symb/.style={font=\ttfamily\bfseries\small, anchor=east, xshift=-0.0cm, yshift=0.4cm},
    % Styles for the instruction boxes
    % Use 'style 2 args' to avoid parameter errors
    memory block/.style 2 args={
        draw=#1,
        fill=#1!5,
        line width=1pt,
        rectangle split,
        rectangle split parts=#2,
        text width=4.5cm,
        align=left,
        inner sep=6pt,
        font=\ttfamily\small,
        anchor=north west
    },
    jump path/.style={
        -{Stealth[bend]},
        line width=1.2pt,
        rounded corners=8pt
    }
]

    % --- Low Memory (Main) ---
    \node[memory block={blue}{2}] (main) {
        ...
        \nodepart{second} bl \_\_far\_thunk
    };
    
    % Labels for main (Left side)
    \node[symb, blue] at (main.one west) {main:};
    \node[addr] at (main.one west) {0x400000};
    \node[addr] at (main.two west) {0x400008};

    % --- Thunk (Directly below main) ---
    \node[memory block={orange}{4}, below=0mm of main] (thunk) {
        ldr x16, [pc, \#8]
        \nodepart{second} br x16
        \nodepart{third} .word 0x20000000
        \nodepart{fourth} .word 0x00000001
    };
    
    % Labels for thunk (Left side)
    \node[symb, orange!80!black] at (thunk.one west) {\_\_far\_thunk:};
    \node[addr] at (thunk.one west) {0x400018};
    \node[addr] at (thunk.two west) {0x40001c};
    \node[addr] at (thunk.three west) {0x400020};
    \node[addr] at (thunk.four west) {0x400024};

    % --- The Gap (Centered under the 4.5cm width box) ---
    \coordinate (center_column) at ($(thunk.south west)!0.5!(thunk.south east)$);
    \node[below=1mm of center_column, text=gray, font=\itshape\small] (gap) {
        [ ... $\approx$ 5 GiB Address Space Gap ... ]
    };
    
    % --- High Memory (Target) ---
    % Positioned below the gap
    \node[memory block={green!60!black}{3}, below=7mm of center_column] (far) {
        push x29 \par mov x29, sp
        \nodepart{second} ...
        \nodepart{third} ret
    };
    
    % Labels for far function (Left side)
    \node[symb, green!40!black] at (far.one west) {far\_function:};
    \node[addr] at (far.one west) {0x120000000};

    % --- Control Flow Paths ---
    
    % Jump 1: main to thunk (Right side)
    \draw[jump path, blue] (main.second east) -- ++(0.6,0) |- (thunk.one east)
        node[pos=0.25, right, font=\sffamily\scriptsize, align=left] {1. Relative Jump};

    % Jump 2: thunk to far (Left side)
    % This edge takes the "long way" around the labels on the left
    \draw[jump path, green!60!black] (thunk.second east) -- ++(0.5,0) |- (far.one east)
        node[pos=0.25, right, font=\sffamily\scriptsize, align=left] {2. Absolute Jump\\(via x16)};

\end{tikzpicture}
\end{document}

-->
[![thunk image](/assets/images/thunk_50p.png)](/assets/images/thunk.png)

LLVM includes support for inserting thunks for certain architectures such as AArch64 because it is a fixed-size instruction set (32-bit), so the relative branch instruction is restricted to 128MiB. As this limit is so low, `lld` has support for thunks out of the box.

If we cross-compile our "far function" example for AArch64 using the same linker script to synthetically place it far away to trigger the need for a thunk, the linker magic becomes visible immediately.

```bash
> aarch64-linux-gnu-gcc -c main.c -o main.o \
-fno-exceptions -fno-unwind-tables \
-fno-asynchronous-unwind-tables

> aarch64-linux-gnu-gcc -c far.c -o far.o \
-fno-exceptions -fno-unwind-tables \
-fno-asynchronous-unwind-tables

> ld.lld main.o far.o -T overflow.lds -o thunk-aarch64
```

We can now see the generated code with `objdump`.

```bash
> aarch64-unknown-linux-gnu-objdump -dr thunk-example 

Disassembly of section .text:

0000000000400000 <main>:
  400000:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400004:	910003fd 	mov	x29, sp
  400008:	94000004 	bl	400018 <__AArch64AbsLongThunk_far_function>
  40000c:	52800000 	mov	w0, #0x0                   	// #0
  400010:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400014:	d65f03c0 	ret

0000000000400018 <__AArch64AbsLongThunk_far_function>:
  400018:	58000050 	ldr	x16, 400020 <__AArch64AbsLongThunk_far_function+0x8>
  40001c:	d61f0200 	br	x16
  400020:	20000000 	.word	0x20000000
  400024:	00000001 	.word	0x00000001

Disassembly of section .text.far:

0000000120000000 <far_function>:
   120000000:	d503201f 	nop
   120000004:	d65f03c0 	ret
```

Instead of branching to `far_function` at `0x120000000`, it branches to a generated thunk at `0x400018` (only 16 bytes away). The thunk similar to the large code-model, loads `x16` with the absolute address, stored in the `.word`, and then performs an absolute jump (`br`).

What if `x86_64` supported this? Can we now go beyond 2GiB? 🤯

There would be some more similar thunks that would need to be fixed beyond `CALL` instructions. Although we are mostly using static binaries, some libraries such as `glibc` may be dynamically loaded. The access to the methods from these shared libraries are through the GOT, Global Offset Table, which gives the address to the PLT (which is itself a thunk 🤯).

The GOT addresses are also loaded via a relative offset so they will need to changed to be either use thunks or perhaps multiple GOT sections; which also has prior art for other architectures such as MIPS [[ref](https://github.com/llvm/llvm-project/blob/5c19f77a7e0c4b35c0efb511a7d9e2e436335e61/lld/ELF/SyntheticSections.h#L315)].

With this information, the necessity of code-models feels unecessary. Why trigger the cost for every callsite when we can do-so piecemeal as necessary with the opportunity to use profiles to guide us on which methods to migrate to thunks.

Furthermore, if our binaries are already tens of gigabytes, clearly size for us is not an issue. We can duplicate GOT entries, at the cost of even larger binaries, to reduce the need for even more thunks for the PLT `jmp`.

What do you think? Let's collaborate.