---
layout: post
title: Does anyone actually use the large code-model?
date: 2026-03-27 09:37 -0700
---

I have been focused lately on trying to resolve relocation overflows when compiling large binaries in the small & medium code-models.
Often when talking to others about the problem, they are quick to offer the idea of using the large code-model.

**small code-model**
  : Assumes all code and data comfortably fit within a single 2GiB window. The compiler relies on fast, compact 32-bit PC-relative offsets for all function calls and data accesses.

**medium code-model**
  : Assumes code stays under 2GiB, but data might exceed it. It splits data into "small" and "large" sections using 32-bit offsets for code and small data, and generating 64-bit addresses strictly for the large data.

**large code-model**
  : Makes zero assumptions about size or placement, lifting the 2GiB limit entirely. The compiler is forced to use 64-bit absolute addressing for every external reference.

Despite the performance downsides of using the large code-model from the instructions generated, it's true that its intent was to support arbitrarily large binaries.
However does anyone actually use it?

Turns out that large binaries do not only affect the instructions generated in the `.text` section but may also have effects on other sections within the ELF file such as
`.eh_frame` (exception handling information), `.eh_frame_hdr` (optimized binary search table for `.eh_frame`), and even `.gcc_except_table`.

Let's take `.eh_frame` and `.eh_frame_hdr` as an example. They specifically allow various encodings for the data within them (`sdata4` or `sdata8` for 4 bytes and 8 bytes respectively) irrespective of the code-model used. However, it looks like the userland has terrible support for it!

If we look at the `.eh_frame_hdr` format, we can see how these encodings are applied in practice. The `encoded` entries in this column are the ones that actually resolve to specific DWARF exception header encoding formats (like `sdata4`, `sdata8`, `udata4`, etc.) depending on the values provided in the preceding `*_enc` fields.

`.eh_frame_hdr` format [[ref](https://refspecs.linuxfoundation.org/LSB_1.3.0/gLSB/gLSB/ehframehdr.html)]:

| Encoding | Field |
| :--- | :--- |
| unsigned byte | version |
| unsigned byte | eh_frame_ptr_enc |
| unsigned byte | fde_count_enc |
| unsigned byte | table_enc |
| encoded | eh_frame_ptr |
| encoded | fde_count |
| *(encoded based on table_enc)* | binary search table |

*Note: The `encoded` values for `eh_frame_ptr` and `fde_count` dictate their byte size and format. For example, if `fde_count_enc` is set to `DW_EH_PE_sdata4`, the `fde_count` field will be processed as an `sdata4` (signed 4-byte) value.*

Up until very recently ([pull#179089](https://github.com/llvm/llvm-project/pull/179089)), LLVM's linker `lld` would crash if it tried to link exception data (`.eh_frame_hdr`) beyond 2GiB.
This section is always generated to help stack searching algorithms avoid linear search.

Once we fix that though, it looks like `libgcc` ([gcc-patch@](https://gcc.gnu.org/pipermail/gcc-patches/2026-March/711435.html)) and `libunwind` ([pull#964](https://github.com/libunwind/libunwind/pull/964)) explicitly either crash on `sdata8` or avoid the binary search table completely reverting back to linear search.

How devasting is linear search here?

If you have a lot of exceptions, which you theoretically might for the large code-model, I had benchmarks that started at **~13s** improve to **~18ms** for a **~700x speedup**.

Other fun failure modes that exist:

**Thread Local Storage (.tdata and .tbss)**
  : Highly optimized TLS access models often rely on 32-bit offsets from the thread pointer to fetch thread-local variables. Massive binaries can push these variables too far away, breaking the fast-path TLS instructions and forcing you into slower, more general TLS models.


**The String Table (.strtab)**
  : Even in a 64-bit ELF (`Elf64_Sym`), the `st_name` field, which holds the offset to the symbol's name in the string table is only a 32-bit integer. If you have enough heavily mangled C++ templates, your string table can theoretically hit the 4GiB limit, at which point the ELF format itself fundamentally caps out. 🫠

  ```
  typedef struct {
	Elf64_Word	st_name;
	unsigned char	st_info;
	unsigned char	st_other;
	Elf64_Half	st_shndx;
	Elf64_Addr	st_value;
	Elf64_Xword	st_size;
  } Elf64_Sym;
  ```

  _Note: Don't let `Elf64_Word` confuse you, it's actually 32bit: `typedef uint32_t	Elf64_Word;`_


It seems like the large code-model "exists" but no one is using it for it's intended purpose which was to build large binaries.
I am working to make massive binaries possible without the large code-model while retaining much of the performance characteristics of the small code-model.

You can read more about it in [x86-64-abi](https://groups.google.com/g/x86-64-abi/c/hz28LNnlBEc/m/J211uZASAgAJ) google-group where I have also posted an RFC.
