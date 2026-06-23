---
layout: post
title: Hijacking ELF entry points for NixOS compatibility or WTF is wrap-buddy?
date: 2026-06-22 17:55 -0700
---

We are part-way through [TacoSprint 2026](https://tacosprint.org/) and a project that has inspired me has been the long-standing pursuit of producing [relocatable binaries]({% post_url 2026-06-21-nix-needs-relocatable-binaries %}) in Nix. This is something I've been [discussing since as early as 2022](https://discourse.nixos.org/t/making-runpath-redundant-for-nix/21631/12?u=fzakaria).

[![photo us hacking at tacosprint](/assets/images/tacosprint_photo_50p.webp)](/assets/images/tacosprint_photo.webp)

We've made pretty great headway! 🥳

I posted a [proposal to the Linux kernel](https://lore.kernel.org/linux-mm/20260622043934.179879-1-farid.m.zakaria@gmail.com/T/#t) mailing list to add support for `$ORIGIN` to `DT_INTERP`, which will allow for resolving the interpreter relatively.

I also submitted [PR#534339](https://github.com/NixOS/nixpkgs/pull/534339) to [nixpkgs](https://github.com/NixOS/nixpkgs) which improves the `RUNPATH` generation and shrinking by modifying them to leverage `$ORIGIN` as well. This needs no new Linux kernel support and will make Nix derivations _a teeny_ bit more relocatable.

Throughout this investigation, I was informed about similar efforts via [wrap-buddy](https://github.com/Mic92/wrap-buddy) by the venerable [Mic92](https://github.com/Mic92).

I opened the GitHub project and I have to admit, I did not quite understand it. Jörg is an amazingly prolific and technical developer, and despite my knowledge of the space, it took me a while to understand the ~~craziness~~ beauty of what was being done.

So, _wtf is wrap-buddy_?

Nix is all about explicit dependencies and it leverages this with techniques like `RUNPATH` on the ELF binary. This all works for newly minted code, but if you try to download any precompiled binary on your NixOS machine, you'll hit an error for a myriad of reasons. One of the biggest being that the dynamic linker/interpreter, `/lib64/ld-linux-x86-64.so.2`, does not exist on NixOS.

We would love to compile everything from source, but the reality is that plenty of software people want to use is _closed_. In order to allow that to work on NixOS machines, derivations may _patch_ the ELF files with [patchelf](https://github.com/nixos/patchelf) setting things like `RUNPATH` and `DT_INTERP` to Nix-friendly paths.

In some rare cases, however, that **doesn't** work. The documentation in `wrap-buddy` claims:

> [autoPatchelfHook](https://nixos.org/manual/nixpkgs/stable/#setup-hook-autopatchelfhook) can be error-prone and may break binaries that, have unusual ELF layouts.

In these pathological cases, `wrap-buddy` is an alternative that takes over the startup of the binary to modify it at runtime. 🤯 

Let's take a look with a small example.
We can build a small C program linked against two shared libraries, `libfoo` and `libbar`, forcing a non-NixOS interpreter path:

```makefile
main: main.c libfoo.so libbar.so
	gcc -I. -L. -Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2 -o main main.c -lfoo -lbar
```

If we run this binary, it fails immediately because `/lib64/ld-linux-x86-64.so.2` doesn't exist or it can't resolve `libfoo.so`.

```bash
> ./main
./main: error while loading shared libraries: libfoo.so: cannot open shared object file...
```

Now we patch it using `wrap-buddy` pointing to our library paths:

```bash
> wrap-buddy --paths ./main --libs ./libfoo ./libbar
Using interpreter: /nix/store/57iz36553175g3178pvxjij8z5rcsd4n-glibc-2.42-61/lib/ld-linux-x86-64.so.2
64-bit stub: 407 bytes
32-bit stub: 441 bytes
Patching: ./main
  ELF class: 64-bit
  Original entry: 0x11a0 (file offset: 0x11a0)
  Available space at entry: 569 bytes
  Stub size: 407 bytes (padded to 416)
  Wrote config to ./.main.wrapbuddy
  Overwrote 416 bytes at entry point
  Converted PT_INTERP to PT_NULL
Patched: ./main
```

Now if we run our binary, `main`, we see that it works:

```bash
> ./main
Starting C application...
Hello from libfoo!
Hello from libbar!
```

What did it do? 🤔

First off, it copies the first 416 bytes of our program code into a hidden file named `.main.wrapbuddy`.

Let's peek at the original binary and the instructions for `_start`:

```bash
> radare2 -q -c "e asm.functions=false; e asm.var=false; e asm.lines=false; e asm.xrefs=false; aa; pd 40 @ entry0" main.orig
  ;-- _start:
0x000011a0      f30f1efa       endbr64
0x000011a4      31ed           xor ebp, ebp
0x000011a6      4989d1         mov r9, rdx                             ; arg3
0x000011a9      5e             pop rsi
0x000011aa      4889e2         mov rdx, rsp
0x000011ad      4883e4f0       and rsp, 0xfffffffffffffff0
0x000011b1      50             push rax
0x000011b2      54             push rsp
0x000011b3      4531c0         xor r8d, r8d
```

`wrap-buddy` saves those starting 416 bytes to the hidden file `.main.wrapbuddy`. The configuration file format starts with a 22-byte header, followed by the interpreter string (83 bytes) and RPATH string (442 bytes), placing our saved original instructions at offset 547 (`0x223`):

```bash
> radare2 -q -a x86 -b 64 -c "pd 10 @ 547" .main.wrapbuddy
0x00000223      f30f1efa       endbr64
0x00000227      31ed           xor ebp, ebp
0x00000229      4989d1         mov r9, rdx
0x0000022c      5e             pop rsi
0x0000022d      4889e2         mov rdx, rsp
0x00000230      4883e4f0       and rsp, 0xfffffffffffffff0
0x00000234      50             push rax
0x00000235      54             push rsp
0x00000236      4531c0         xor r8d, r8d
0x00000239      31c9           xor ecx, ecx
```

Next, it clears our `PT_INTERP` to `PT_NULL` so the Linux kernel thinks it's a statically linked binary and boots it directly:

```
> readelf -a main.orig | grep INTERP
  INTERP         0x0000000000000318 0x0000000000000318 0x0000000000000318

> readelf -a main | grep NULL
  NULL           0x0000000000000318 0x0000000000000318 0x0000000000000318
```

Lastly, it overwrites our entrypoint with that _small stub_ (416 bytes). We can see in the disassembly that `entry0` immediately redirects and calls `stub_main` now:

```bash
> radare2 -q -c "e asm.functions=false; e asm.var=false; e asm.lines=false; e asm.xrefs=false; aa; af- 0x1203; f- sym.register_tm_clones; f stub_main @ 0x120f; pd 4 @ entry0; s entry0; so 3; s \$ij; pd 40" main
  ;-- _start:
0x000011a0      4831ed         xor rbp, rbp
0x000011a3      4889e7         mov rdi, rsp
0x000011a6      4883e4f0       and rsp, 0xfffffffffffffff0
0x000011aa      e860000000     call stub_main
;-- stub_main:
0x0000120f      55             push rbp
0x00001210      b802000000     mov eax, 2
0x00001215      31f6           xor esi, esi
0x00001217      4889e5         mov rbp, rsp
0x0000121a      53             push rbx
0x0000121b      4889fb         mov rbx, rdi
0x0000121e      4881ec9800..   sub rsp, 0x98
```

Why all this complexity?
What is `stub_main` doing?

The goal of `stub_main` is to find a known custom loader, `loader.bin`, which will help us finish all the dynamic linking.

The custom loader gets even more nuanced and low-level. It would be a disservice to try and completely go over everything it does, and at this point the [README](https://github.com/Mic92/wrap-buddy/blob/ab9f7fdf2012007d550293af688a67e11048528c/README.md) does a fairly good job.

At a high level:

1. It reads the saved original bytes from the `.main.wrapbuddy` file and copies the original bytes back over our stub in memory. To any observer, the binary is now completely clean and resembles the original.
2. It injects the custom `RUNPATH` by creating a brand new dynamic section in memory and populates it with the `DT_RUNPATH` containing our library search paths that we stored in `.main.wrapbuddy`.
3. It loads the real NixOS interpreter into memory.
4. It rewrites the kernel's stack metadata (auxiliary vector pointers like `AT_BASE`, `AT_PHDR`, and `AT_ENTRY`) to trick the native loader (`ld.so`) into believing it was loaded natively by the kernel.
5. Finally, it jumps to the entry point of the NixOS interpreter.

The NixOS dynamic linker takes over, uses the `RUNPATH` to resolve `libfoo.so` and `libbar.so`. We can now run the application using the restored original entry point with everything resolved.

Magic. Wizard. [Mic92](https://github.com/Mic92). 🧙