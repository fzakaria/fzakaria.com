---
layout: post
title: "Stamping build info in constant memory"
date: 2026-08-25 18:00 -0700
---


This is a fun little trick I came across at `$DAYJOB`. I did not invent it, but I thought
it was interesting enough to understand better and share.

At `$WORK` we build with [buck2](https://buck2.build/) and we stamp our executables
with build information: build-id, timestamp, author, the usual suspects using `llvm-objcopy` as a step **after** the link.

```console?comments=true
$ cat buildinfo.json
{"revision":"9f3c1ad","built_at":"2026-08-25T12:00:00Z",
 "builder":"buck2","host":"nyx"}

# attach it as a section
$ llvm-objcopy --add-section .buildinfo=buildinfo.json app app.stamped

# read it back out
$ llvm-objcopy --dump-section .buildinfo=- app.stamped /dev/null
{"revision":"9f3c1ad","built_at":"2026-08-25T12:00:00Z",
 "builder":"buck2","host":"nyx"}
```

The reason it is a separate step is caching. If the build info was generated at link time then everytime we link the binary it would produce different bytes causing it to not be
bit-reproducible. When something is bit-reproducible, it is safe to cache it, and the build system can apply early cut-off optimizations.

That works, until the binaries get big. We noticed that `llvm-objcopy`'s memory use
scales with the size of the file it is stamping. Stamping is exactly the kind of
step that runs massively parallel at the end of a build so this can cause a lot of memory pressure.

Why is the stamping step reading the binary at all? 🤔

# The memory problem

Let's measure the claim that the memory use of `llvm-objcopy` scales with the size of the file. We will attach a JSON build info blob to an increasingly large synthetic executable and measure the peak RSS of the stamping step.

```plotnine
import pandas as pd
from plotnine import *

# ru_maxrss of a single --add-section, via os.wait4. NixOS,
# llvm-objcopy 20.1.8, 88-byte JSON payload.
sizes = [4, 16, 64, 256, 512, 1024]
df = pd.DataFrame({
    "mib": sizes,
    "rss": [52.7, 76.9, 172.9, 556.8, 1068.6, 2092.6],
})

# Linear axes on purpose. The claim being made is about the slope, and a log
# plot flatters a straight line into looking like a law rather than a cost.
plot = (
    ggplot(df, aes("mib", "rss"))
    + geom_line(size=1.0, color="#b1201d")
    + geom_point(size=2.6, color="#b1201d")
    + scale_x_continuous(breaks=[0, 256, 512, 768, 1024])
    + scale_y_continuous(breaks=[0, 500, 1000, 1500, 2000])
    + labs(x="executable size (MiB)", y="peak RSS (MiB)")
)
plot.width, plot.height = 7.0, 3.2
```

The graph confirms the claim. The memory use of `llvm-objcopy` scales linearly with the size of the file being stamped. Surprisingly, the slope is **two**. The peak RSS is roughly twice the size of the file being stamped irrespective of the size of the build info being attached.[^gnu]

[^gnu]: For those thinking this is an LLVM specific issue, GNU `objcopy` exhibits
        the same behavior.


I am helping to shepherd a [PR open against LLVM](https://github.com/llvm/llvm-project/pull/217706) to stream the ELF output rather than materialize it, which roughly halves the peak. That is a definite improvement but the problem remains that in order to add
a tiny section to a large binary, the whole binary has to be read into memory. The memory use is still linear in the size of the file.

# A section is three things

The problem is not poor implementation on the part of `llvm-objcopy`. Adding a section to
an ELF touches three separate things:

1. the section's **bytes**, somewhere in the file
2. a 64-byte **entry** in the section header table describing where those bytes are
3. the section's **name**, which is not in the entry itself but rather the entry holds a  `sh_name` offset into `.shstrtab`, so the name has to be appended to that string table

<svg viewBox="0 0 760 268" role="img"
     style="display:block;margin-inline:auto;max-width:100%;height:auto;font-family:var(--mono)"
     aria-label="A single Elf64_Shdr entry drawn as a list of fields, with two arrows leaving it. The sh_name field, highlighted in red, holds 0x78 and is an offset into the .shstrtab byte table drawn at the top right, where the .buildinfo cell sits at that offset. The sh_offset and sh_size fields, highlighted in blue, point together at the section contents drawn at the bottom right. The entry itself holds no name and no bytes; it only refers to them.">

  <text x="20" y="30" fill="currentColor" font-size="13" font-weight="600">Elf64_Shdr — one 64-byte entry</text>

  <rect x="20" y="42" width="250" height="182" rx="4"
        fill="#8a8580" fill-opacity="0.10" stroke="#8a8580" stroke-width="1"/>
  <rect x="20" y="42" width="250" height="26" rx="4" fill="#b1201d" fill-opacity="0.18"/>
  <rect x="20" y="146" width="250" height="52" fill="#4c72b0" fill-opacity="0.15"/>

  <g font-size="11.5">
    <g fill="currentColor">
      <text x="34" y="59">sh_name</text>
      <text x="34" y="85">sh_type</text>
      <text x="34" y="111">sh_flags</text>
      <text x="34" y="137">sh_addr</text>
      <text x="34" y="163">sh_offset</text>
      <text x="34" y="189">sh_size</text>
      <text x="34" y="215">sh_link …</text>
    </g>
    <g text-anchor="end">
      <text x="256" y="59"  fill="#b1201d" font-weight="600">0x78</text>
      <text x="256" y="85"  fill="currentColor" opacity="0.7">PROGBITS</text>
      <text x="256" y="111" fill="currentColor" opacity="0.7">0</text>
      <text x="256" y="137" fill="currentColor" opacity="0.7">0x0</text>
      <text x="256" y="163" fill="#4c72b0" font-weight="600">0x401021</text>
      <text x="256" y="189" fill="#4c72b0" font-weight="600">0x58</text>
      <text x="256" y="215" fill="currentColor" opacity="0.7">0</text>
    </g>
  </g>

  <!-- sh_name is an index into the string table, not a name -->
  <text x="370" y="30" fill="currentColor" font-size="13" font-weight="600">.shstrtab</text>
  <g stroke="#b1201d" stroke-width="1.5" fill="none">
    <path d="M274 55 L458 55"/>
    <path d="M466 55 l-9 -4 l0 8 z" fill="#b1201d" stroke="none"/>
  </g>
  <text x="366" y="46" fill="#b1201d" font-size="10" text-anchor="middle">0x78 bytes in</text>

  <g stroke="#8a8580" stroke-width="1" fill="#8a8580" fill-opacity="0.10">
    <rect x="470" y="42" width="90"  height="34"/>
    <rect x="680" y="42" width="60"  height="34"/>
  </g>
  <rect x="560" y="42" width="120" height="34" fill="#b1201d" fill-opacity="0.22"
        stroke="#b1201d" stroke-width="1"/>
  <g fill="currentColor" font-size="10.5" text-anchor="middle">
    <text x="515" y="63">.interp\0</text>
    <text x="620" y="63">.buildinfo\0</text>
    <text x="710" y="63">.rela…</text>
  </g>
  <g stroke="#8a8580" stroke-width="1">
    <line x1="470" y1="80" x2="470" y2="86"/>
    <line x1="560" y1="80" x2="560" y2="86"/>
    <line x1="680" y1="80" x2="680" y2="86"/>
  </g>
  <g fill="currentColor" font-size="9.5" text-anchor="middle" opacity="0.75">
    <text x="470" y="98">0x70</text>
    <text x="560" y="98">0x78</text>
    <text x="680" y="98">0x83</text>
  </g>

  <!-- sh_offset and sh_size locate the bytes, wherever they are -->
  <text x="470" y="146" fill="currentColor" font-size="13" font-weight="600">the section&#39;s bytes</text>
  <path d="M270 146 l8 0 l0 52 l-8 0" stroke="#4c72b0" stroke-width="1.5" fill="none"/>
  <g stroke="#4c72b0" stroke-width="1.5" fill="none">
    <path d="M278 172 L458 172"/>
    <path d="M466 172 l-9 -4 l0 8 z" fill="#4c72b0" stroke="none"/>
  </g>
  <rect x="470" y="156" width="270" height="34" rx="3" fill="#4c72b0" fill-opacity="0.18"
        stroke="#4c72b0" stroke-width="1"/>
  <text x="605" y="177" fill="currentColor" font-size="10.5" text-anchor="middle">88 bytes of JSON, at 0x401021</text>

  <text x="20" y="252" fill="currentColor" font-size="10.5" opacity="0.8">The entry holds neither the name nor the bytes. It only refers to them — and only one of those two references can be repointed in place.</text>
</svg>

In order to account for the new section, the section header table has to grow by one entry, and `.shstrtab` has to grow by the length of the new name.

The current model for `llvm-objcopy` is to read the whole file into memory, add the new section, and write the whole file back out. That is why the memory use scales with the size of the file.

# Pay the byte at link time

How can we avoid having to rebuild the whole file just to add a tiny section? The trick is to pay the cost at link time rather than at stamp time.

We can have the linker emit a placeholder section with the right name and a single byte of content. The section header table entry is already there, and the name is already in `.shstrtab`. The post-link stamping step can then append the payload to the end of the file and update the section header entry to point to it. 💡

We make linker emit the section during the normal build. It does not need to hold
anything; it just needs to exist so that it owns a name and a header.

```c
/* A placeholder the linker will emit a section header for.
   It holds one byte and is deliberately not SHF_ALLOC,
   so it is metadata rather than image. */
__asm__(".section .buildinfo,\"\",@progbits\n"
        ".byte 0\n"
        ".previous");
```

Our "stamp" step is now incredibly simple. It does not need to read the file at all, it just needs to write the new payload and update the section header entry.

1. append the payload to the end of the file
2. write the new `sh_offset` and `sh_size` into the placeholder's section header entry

Nothing that already exists moves. `e_shoff` does not move, the section header table
does not move, no other `sh_offset` changes. The edit is **sixteen bytes**, at a file offset you can compute from the ELF header, plus a `cat`.

<svg viewBox="0 0 760 316" role="img"
     style="display:block;margin-inline:auto;max-width:100%;height:auto;font-family:var(--mono)"
     aria-label="Two file layouts compared. In the objcopy layout the whole file is drawn in red, because every byte is read into memory and written back out even though almost none of it changes. In the reserve-and-append layout the same file is drawn untouched in grey, with a one-byte placeholder section already present, a single highlighted entry inside the section header table, and a new payload block appended past the end of the file; an arrow runs from that entry to the payload.">

  <!-- panel one: objcopy has to rebuild the file -->
  <text x="20" y="20" fill="currentColor" font-size="14" font-weight="600">objcopy --add-section</text>
  <text x="740" y="20" fill="#b1201d" font-size="14" font-weight="600" text-anchor="end">every byte copied</text>

  <g stroke="#b1201d" stroke-width="1" fill="#b1201d" fill-opacity="0.16">
    <rect x="20"  y="58" width="48"  height="34" rx="3"/>
    <rect x="72"  y="58" width="54"  height="34" rx="3"/>
    <rect x="130" y="58" width="310" height="34" rx="3"/>
    <rect x="458" y="58" width="80"  height="34" rx="3"/>
    <rect x="542" y="58" width="150" height="34" rx="3"/>
  </g>
  <g fill="currentColor" font-size="11" text-anchor="middle">
    <text x="44"  y="80">ehdr</text>
    <text x="99"  y="80">phdrs</text>
    <text x="285" y="80">.text .rodata …</text>
    <text x="498" y="80">.shstrtab</text>
    <text x="617" y="80">section headers</text>
  </g>
  <path d="M20 104 l0 8 l672 0 l0 -8" stroke="#b1201d" stroke-width="1.5" fill="none"/>
  <text x="356" y="128" fill="#b1201d" font-size="11" text-anchor="middle">read into a model, serialized again — 1,238 bytes of it actually differ</text>

  <!-- panel two: the section already exists, so only its entry changes -->
  <text x="20" y="188" fill="currentColor" font-size="14" font-weight="600">reserve one byte, then append</text>
  <text x="740" y="188" fill="#b1201d" font-size="14" font-weight="600" text-anchor="end">16 bytes + a tail</text>

  <g stroke="#8a8580" stroke-width="1" fill="#8a8580" fill-opacity="0.12">
    <rect x="20"  y="222" width="48"  height="34" rx="3"/>
    <rect x="72"  y="222" width="54"  height="34" rx="3"/>
    <rect x="130" y="222" width="310" height="34" rx="3"/>
    <rect x="458" y="222" width="80"  height="34" rx="3"/>
    <rect x="542" y="222" width="150" height="34" rx="3"/>
  </g>
  <rect x="444" y="222" width="10" height="34" rx="2" fill="#8a8580" fill-opacity="0.35"/>
  <rect x="650" y="224" width="14" height="30" rx="2" fill="#b1201d"/>
  <rect x="700" y="222" width="40" height="34" rx="3" fill="#b1201d" fill-opacity="0.2"
        stroke="#b1201d" stroke-width="1"/>
  <g fill="currentColor" font-size="11" text-anchor="middle">
    <text x="44"  y="244">ehdr</text>
    <text x="99"  y="244">phdrs</text>
    <text x="285" y="244">.text .rodata …</text>
    <text x="498" y="244">.shstrtab</text>
    <text x="596" y="244">section headers</text>
    <text x="720" y="244">payload</text>
  </g>

  <line x1="449" y1="256" x2="449" y2="272" stroke="#8a8580" stroke-width="1.5"/>
  <text x="449" y="288" fill="currentColor" font-size="11" text-anchor="middle" opacity="0.75">the reserved byte</text>

  <path d="M657 258 l0 20 l63 0 l0 -18" stroke="#b1201d" stroke-width="1.5" fill="none"/>
  <path d="M720 256 l-5 9 l10 0 z" fill="#b1201d"/>
  <text x="700" y="300" fill="#b1201d" font-size="11" text-anchor="middle">sh_offset, sh_size</text>
</svg>

> **Note**
> Why 1 byte?
> Turns out that `llvm-objcopy` and GNU `objcopy` disagree on whether an empty section is a valid ELF. The one byte is a cheap way to make both linkers happy.
{: .alert .alert-note }


The payload lands *after* the section header table, which looks alarming the first time
you see it but is completely legal. Nothing in ELF says section contents must precede the
section header table. The kernel also never looks at section headers also, it loads
`PT_LOAD` segments out of the program headers, which we do not touch.

# Benchmark

I wrote a small C version to benchmark it in contrast, please be mindful that this
graph is log-log.

<details markdown="1">
<summary markdown="span">elfstamp.c</summary>

```c
/* elfstamp -- point a pre-reserved ELF section at data appended to the file.
 *
 * usage: elfstamp <elf> <section-name> <payload-file>
 *
 * The section must already have a header in the file; this never adds one.
 * Nothing that already exists is moved, so the only things ever held in
 * memory are one section header, the section-name string table and a fixed
 * copy buffer -- regardless of how large the ELF is. */
#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Fixed staging buffer for the append; the whole point is that this number
   does not depend on the size of the executable being stamped. */
#define COPY_CHUNK (64 * 1024)

/* Offsets of the two fields inside an Elf64_Shdr that this tool rewrites. */
#define SHDR_OFF_SH_OFFSET offsetof(Elf64_Shdr, sh_offset)
#define SHDR_OFF_SH_SIZE offsetof(Elf64_Shdr, sh_size)

/* Payload placement alignment. Nothing requires more than this for a
   non-allocated note, and it keeps the arithmetic obvious. */
#define PAYLOAD_ALIGN 8

static void die(const char *what) {
  fprintf(stderr, "elfstamp: %s: %s\n", what, strerror(errno));
  exit(1);
}

static void read_exact(int fd, void *buf, size_t n, off_t off) {
  if (pread(fd, buf, n, off) != (ssize_t)n) {
    die("short read");
  }
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s <elf> <section> <payload>\n", argv[0]);
    return 2;
  }
  const char *elf_path = argv[1], *want = argv[2], *payload_path = argv[3];

  int fd = open(elf_path, O_RDWR);
  if (fd < 0) {
    die(elf_path);
  }

  /* The header tells us where the section header table is; that table is the
     only index we need, and we walk it one entry at a time. */
  Elf64_Ehdr eh;
  read_exact(fd, &eh, sizeof eh, 0);
  if (memcmp(eh.e_ident, ELFMAG, SELFMAG) != 0 ||
      eh.e_ident[EI_CLASS] != ELFCLASS64) {
    fprintf(stderr, "elfstamp: not a 64-bit ELF\n");
    return 1;
  }

  /* Section names live in their own string table; read just that section. */
  Elf64_Shdr sh;
  read_exact(fd, &sh, sizeof sh, eh.e_shoff + (off_t)eh.e_shstrndx * eh.e_shentsize);
  char *shstr = malloc(sh.sh_size);
  if (!shstr) {
    die("malloc");
  }
  read_exact(fd, shstr, sh.sh_size, sh.sh_offset);

  /* Find the placeholder section header the linker already emitted. */
  off_t target = -1;
  for (unsigned i = 0; i < eh.e_shnum; i++) {
    off_t at = eh.e_shoff + (off_t)i * eh.e_shentsize;
    read_exact(fd, &sh, sizeof sh, at);
    if (strcmp(shstr + sh.sh_name, want) == 0) {
      target = at;
      break;
    }
  }
  free(shstr);
  if (target < 0) {
    fprintf(stderr, "elfstamp: no section named '%s'\n", want);
    return 1;
  }
  if (sh.sh_flags & SHF_ALLOC) {
    fprintf(stderr, "elfstamp: '%s' is SHF_ALLOC; it is mapped and cannot move\n", want);
    return 1;
  }

  /* Append the payload past everything, aligned. Nothing already in the file
     is read or rewritten, so this is a pure O(payload) copy. */
  off_t end = lseek(fd, 0, SEEK_END);
  if (end < 0) {
    die("lseek");
  }
  off_t where = (end + PAYLOAD_ALIGN - 1) & ~(off_t)(PAYLOAD_ALIGN - 1);
  if (ftruncate(fd, where) != 0) {
    die("ftruncate");
  }

  int pfd = open(payload_path, O_RDONLY);
  if (pfd < 0) {
    die(payload_path);
  }
  char buf[COPY_CHUNK];
  uint64_t written = 0;
  for (;;) {
    ssize_t n = read(pfd, buf, sizeof buf);
    if (n < 0) {
      die("read payload");
    }
    if (n == 0) {
      break;
    }
    if (pwrite(fd, buf, n, where + written) != n) {
      die("write payload");
    }
    written += n;
  }
  close(pfd);

  /* Repoint the section header: sixteen bytes, in place. */
  uint64_t off64 = (uint64_t)where;
  if (pwrite(fd, &off64, sizeof off64, target + SHDR_OFF_SH_OFFSET) != sizeof off64 ||
      pwrite(fd, &written, sizeof written, target + SHDR_OFF_SH_SIZE) != sizeof written) {
    die("patch section header");
  }
  close(fd);

  printf("%s: .%s -> %llu bytes at 0x%llx\n", elf_path, want,
         (unsigned long long)written, (unsigned long long)where);
  return 0;
}
```

</details>

```plotnine
import pandas as pd
from plotnine import *

# ru_maxrss of a single stamping command, via os.wait4. NixOS,
# llvm-objcopy 20.1.8, 88-byte JSON payload.
sizes = [4, 16, 64, 256, 512, 1024]
df = pd.DataFrame({
    "mib": sizes * 2,
    "tool": ["llvm-objcopy"] * 6 + ["append + 16 bytes"] * 6,
    "rss": [52.7, 76.9, 172.9, 556.8, 1068.6, 2092.6,
            9.5, 9.5, 9.5, 9.5, 9.5, 9.5],
})
df["tool"] = pd.Categorical(
    df["tool"], categories=["llvm-objcopy", "append + 16 bytes"], ordered=True)

# Log-log, because the interesting thing is the slope: two lines at 45 degrees
# and one that is flat.
plot = (
    ggplot(df, aes("mib", "rss", color="tool"))
    + geom_line(size=1.0)
    + geom_point(size=2.6)
    + scale_x_log10(breaks=sizes, labels=[str(s) for s in sizes])
    + scale_y_log10(breaks=[10, 30, 100, 300, 1000, 3000],
                    labels=lambda bs: [f"{b:g}" for b in bs])
    + scale_color_manual(values={"llvm-objcopy": "#b1201d",
                                 "append + 16 bytes": "#4c72b0"})
    + labs(x="executable size (MiB)", y="peak RSS (MiB)", color="")
    + theme(legend_position="top")
)
plot.width, plot.height = 7.0, 3.4
```

Our trick works! The "append + 16 bytes" approach is constant memory.
Not only is the peak RSS constant, but the wall time is also constant and much faster
by avoiding the read and write of the whole file.


# One trick pony 

It is often easy to reach for general-purpose tools like `objcopy` as they are a swiss-army knife for manipulating object files. What I like about this trick though is that there are meaningful improvements to be made by writing special purpose tools and that does not mean we have to accrue large maintenance costs. In this case it was a tiny 200-line C program.

The economics of these tools is also changing with the rise of LLMs in our workflow. While many are concerned about the influx of generated code, I remain optimistic that we
we can use them to find such opportunities.

Don't be afraid to write a small tool to solve a specific problem.