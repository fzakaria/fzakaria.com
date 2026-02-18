---
layout: post
title: Linker Pessimization
date: 2026-02-18 07:54 -0800
---

In a [previous post]({% post_url 2026-01-30-crazy-shit-linkers-do-relaxation %}), I wrote about _linker relaxation_: the linker's ability to replace a slower, larger instruction with a faster, smaller one when it has enough information at link time. For instance, an indirect `call` through the GOT can be relaxed into a direct `call` plus a `nop`. This is a well-known technique to optimize the instructions for performance.

Does it ever make sense to go the _other direction_? 🤔

We've been working on linking some massive binaries that include Intel's [Math Kernel Library (MKL)](https://www.intel.com/content/www/us/en/developer/tools/oneapi/onemkl.html), a prebuilt static archive. MKL ships as object files compiled with the _small_ code-model (`mcmodel=small`), meaning its instructions assume everything is reachable within ±2 GiB. The included object files also has some odd relocations where the addend is a very large negative number (>1GiB).

The calculation for the relocation value is **S + A - P**: the symbol address plus the addend minus the instruction address. WIth a sufficiently large negative addend, the relocation value can easily exceed the 2 GiB limit and the linker fails with relocation overflows.

We can't recompile MKL (it's a prebuilt proprietary archive), and we can't simply switch everything to the large code model. What can we do? 🤔

I am calling this technique **linker pessimization**: the reverse of relaxation. Instead of shrinking an instruction, we _expand_ one to tolerate a larger address space. 😈

### The Problematic LEA

The specific instructions that overflow in our case are `LEA` (Load Effective Address) instructions.

In x86_64, `lea r9, [rip + disp32]` performs pure arithmetic: it computes `RIP + disp32` and stores the result in `r9` without accessing memory. The `disp32` is a **32-bit signed integer** embedded directly into the instruction encoding, and the linker fills it in via an `R_X86_64_PC32` relocation.

The relocation formula is **S + A - P**. Let's look at an example with a large addend.

| Term | Meaning | Value (approximate) |
|------|---------|---------------------|
| **S** (Symbol) | Addfress of symbol | ~200 MB into `.rodata` |
| **A** (Addend) | Constant baked into the object file | `0x44000000` (−1,062 MB) |
| **P** (Position) | Address of the instruction being patched | ~1,200 MB into `.text` |

```
S + A - P  =  200 + (−1062) − 1200
           =  −2062 MB
```

A 32-bit signed integer can only represent ±2,048 MB (±2 GiB). Our value of **−2,062 MB** exceeds that range and the linker rightfully complains 💥:

```
ld.lld: error: libfoo.a(...):(function ...: .text+0x...):
  relocation R_X86_64_PC32 out of range:
  -2160984064 is not in [-2147483648, 2147483647]
```

> **Note**
> These `LEA` instructions appear in MKL because the library uses them as a way to compute an address of a data table relative to the instruction pointer. The large negative addend (`-0x44000000`) is _intentional_; it's an offset within a large lookup table.
{: .alert .alert-note }

### The Idea: Replace LEA with MOV

The core idea is delightful because often as an engineer we are trained to optimize systems, but in this case we want the opposite. We swap the `LEA` for a `MOV` that reads through a nearby pointer.

Recall from the [relaxation post]({% post_url 2026-01-30-crazy-shit-linkers-do-relaxation %}): relaxation _shrinks_ instructions (e.g. indirect `call` -> direct `call`). Here we do the opposite: we make the instruction _do more work_ (pure arithmetic -> memory load) in exchange for a reachable displacement. That's why I consider it a _pessimization_ or _reverse-relaxation_.

Both instructions use the same encoding length (7 bytes with a REX prefix), so the patch is a **single byte change** in the opcode. 🤓

```
LEA:  4C 8D 0D xx xx xx xx    lea r9, [rip + disp32]   (opcode 0x8D)
MOV:  4C 8B 0D xx xx xx xx    mov r9, [rip + disp32]   (opcode 0x8B)
         ^^
 only this byte changes!
```

The difference in behavior is critical:
- **LEA**: `r9 = RIP + disp32` (arithmetic, no memory access). `disp32` must encode the entire distance to the far-away data. This overflows.
- **MOV**: `r9 = *(RIP + disp32)` (memory load). `disp32` points to a _nearby_ 8-byte pointer slot. The pointer slot holds the full 64-bit address. This never overflows.

### Visualizing the Change

**Original** — the `LEA` must reach across the entire binary:

```
                    disp32 must encode this entire distance
                 ╭──────────────────────────────────────────╮
                 │           ~2+ GiB  (OVERFLOW!)           │
                 │                                          │
  .text          ▼                                          │
  ┌──────────────────────────┐                              │
  │ lea r9, [rip + disp32]   │─────────── X ────────────────┤
  │        (0x8D)            │  can't fit in 32 bits!       │
  └──────────────────────────┘                              │
                                                            │
  .rodata (far away)                                        │
  ┌──────────────────────────┐                              │
  │ symbol + offset          │◄─────────────────────────────╯
  └──────────────────────────┘
```

**Pessimized** — the `MOV` reads a nearby pointer that holds the full address:

```
  .text                          .data.fixup (nearby)
  ┌────────────────────────┐    ┌──────────────────────────┐
  │ mov r9, [rip + disp32] │──▶ │ .quad <64-bit address>   │
  │        (0x8B)          │    │  (R_X86_64_64 reloc)     │
  └────────────────────────┘    └──────────┬───────────────┘
         small offset ✓                    │
         always fits in 32 bits            │  full 64-bit pointer
                                           │  NEVER overflows
  .rodata (far away)                       │
  ┌──────────────────────────┐             │
  │ symbol + offset          │◄────────────╯
  └──────────────────────────┘
```

We've traded one direct `LEA` computation for an indirect `MOV` through a pointer, and we make sure the displacement is now tiny. The 64-bit pointer slot can reach _any_ address in the virtual address space. 👌

### Implementation Details

For each problematic relocation, three changes are needed in the object file:

**1. Opcode Patch**: In `.text`, change byte `0x8D` to `0x8B` (1 byte).

This converts the `LEA` (compute address) into a `MOV` (load from address). The rest of the instruction encoding (ModR/M byte, REX prefix) stays identical because both instructions use the same operand format.

```
 Before:  4C 8D 0D xx xx xx xx    lea  r9, [rip + disp32]
 After:   4C 8B 0D xx xx xx xx    mov  r9, QWORD PTR [rip + disp32]
             ^^
```

**2. New Pointer Slot** — Create a new section (`.data.fixup`) containing 8 zero bytes per patch site, plus a new `R_X86_64_64` relocation pointing to the original symbol with the original addend.

```
 .data.fixup:
   .quad 0x0000000000000000      # linker fills via R_X86_64_64
         ▲
         └── relocation: R_X86_64_64  sym=symbol  addend=-0x44000000
```

`R_X86_64_64` is a **64-bit absolute** relocation. Its formula is simply `S + A`, no subtraction of `P`. There is no 32-bit range limitation; it can address the entire 64-bit address space. This is the key insight that makes the fix work.

**3. Retarget the Original Relocation** — In the `.rela.text` entry for the patched instruction, change the symbol to point at the new pointer slot in `.data.fixup` and update the type to `R_X86_64_PC32`. The addend becomes a small offset (the distance from the instruction to the fixup slot), which is guaranteed to fit.

> **Note**
> Because both `LEA` and `MOV` with a `[rip + disp32]` operand are exactly the same length (7 bytes with a REX prefix), we don't shift any code, don't invalidate any other relocations, and don't need to rewrite any other parts of the object file. It's truly a surgical patch.
{: .alert .alert-note }

The pessimized `MOV` now performs a **memory load** where the original `LEA` did pure register arithmetic. That's an extra cache line fetch and a data dependency. If this instruction is in a tight loop, it could be a performance hit.

Optimization is the root of all evil, what does that make pessimization? 🧌
