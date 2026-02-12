---
layout: post
title: Creating massively huge fake files and binaries
date: 2026-02-11 16:34 -0800
---

I was writing a test case for `lld` to support "thunks" [[llvm#180266](https://github.com/llvm/llvm-project/pull/180266)] which uses a linker script to place two sections very far apart (8GiB) in the virtual address space.

```
SECTIONS {
    .text_low 0x10000: { *(.text_low) }
    .text_high 0x200000000: { *(.text_high) }
}
```

After linking a trivially small assembly file, I ran `ls -l` on the resulting binary was confused

```console
$ ls -lh output
-rwxr-xr-x 1 fzakaria fzakaria 8.0G Feb 11 16:00 output
```

**8 GiB**. For what amounts to a handful of instructions. 😲

What's going on? And where did all that space come from?

### Apparent size vs. on-disk size

Turns out `ls -l` reports the _logical_ (apparent) size of the file, which is simply an integer stored in the inode metadata. It represents the offset of the last byte written. Since `.text_high` lives at `0x200000000` (~8 GiB), the file's logical size extends out that far even though the actual code is tiny.

The _real_ story is told by `du`:

```console
$ du -h output
12K     output
```

12 KiB on disk. The file is **sparse**. 🤓

### What is a sparse file?

A sparse file is one where the filesystem doesn't bother allocating blocks for regions that are all zeros. The filesystem (ext4, btrfs, etc.) stores a mapping of logical file offsets to physical disk blocks in the inode's _extent tree_. For a sparse file, there are simply no extents for the hole regions.

For our 8 GiB binary, the extent tree looks something like:

```
Inode extent tree:
  [offset 0,       12 blocks]  → disk blocks 48392-48403   (.text_low code)
  [offset 0x1FFFF, 4 blocks]   → disk blocks 48404-48407   (.text_high code)

  (nothing for the ~8 GiB in between — no extents exist)
```

We can use `filefrag` to also see the same information, albeit a little more condensed.

```console
$ defrag -v output
Filesystem type is: 9123683e
File size of output is 8589873896 (2097138 blocks of 4096 bytes)
 ext:     logical_offset:        physical_offset: length:   expected: flags:
   0:        0..       1:  461921719.. 461921720:      2:             encoded
   1:  2097137.. 2097137:  461921740.. 461921740:      1:  464018856: last,eof
output: 2 extents found
```

When something reads the file:
1. The virtual filesystem (VFS) receives `read(fd, buf, size)` at some offset
2. The filesystem looks up the extent tree for that offset
3. If **extent found** then read from the physical disk block
4. If **no extent (hole)** then the kernel fills the buffer with zeros, no disk I/O

### Creating sparse files yourself

You don't need a linker to create sparse files. `truncate` will do it:

```console
$ truncate -s 1P bigfile
$ ls -lh bigfile
-rw-r--r-- 1 fzakaria fzakaria 1.0P Feb 11 16:00 bigfile

$ du -h bigfile
0       bigfile
```

A 1 PiB file that takes zero bytes on disk. `dd` with `seek` works too:

```console
$ dd if=/dev/null of=bigfile bs=1 seek=1P
```

Both produce the same result: a file whose logical size is 1 PiB but whose on-disk footprint is effectively nothing.
