---
layout: post
title: 'Your executable is a SQLite database'
date: 2026-08-23 07:30 -0700
---

I have been probably obsessed with two things in the last few years: Nix as a tool to explore
innovative ideas that require the capability to rebuild the world and replacing ELF with SQLite as an executable format. You might have noticed that these two ideas are well suited to each other.

I explored the idea during my PhD thesis but found feedback from others unmotivating. 
Radical ideas are hard to sell, as you are working against the inertia of the established
solution.

![Four-panel comic. A crow at a microphone says "Nix is great"; the audience
boos and shouts "get better material"; the crow looks stricken; the last panel
shows its remaining cue cards, which read "SQLite can be an object file format".](/assets/images/get-better-material-sqlite.png){: style="--image-width: 26rem"}

One of the end results of that exploration was [sqlelf]({% post_url 2023-03-19-sqlelf-and-20-years-of-nix %}),
a tool that lets you explore an ELF file declaratively using SQL.[^sqlelf]
`SELECT name FROM elf_symbols` instead of fiddling with `readelf` and `grep`.
It was remarkably simple by leveraging _virtual tables_ over the ELF: however I found it
to be a refreshing improvement to explore the ELF file format. I knew however that
there is still something much bigger to be done.

[^sqlelf]: I wrote a paper, [arXiv:2405.03883](https://arxiv.org/abs/2405.03883),
    that I failed to get published and a follow-up post on [querying with it]({% post_url 2023-09-11-quick-insights-using-sqlelf %}).

I never let the idea go and with the recent improvements with LLMs, I find it compelling to revisit these ideas to explore further. Specifically, can we replace ELF with SQLite as an executable format? 🤔

Not "a database that describes an executable", but the actual file you `chmod +x`
and run.

```console
$ file hello
hello: SQLite 3.x database, application id 0x53454c46, user version 1

$ ./hello
Hello, world!

$ sqlite3 hello 'SELECT soname FROM ldd'
libc.so.6
```

I developed a pretty fleshed out prototype. It is called **SELF**, the _Structured Executable & Linkable Format_, because I am unoriginal. It is on [GitHub](https://github.com/fzakaria/selfdb) if you are interested. I'm surprised about all the interesting things that fall out of this idea.

# ELF is a database that refuses to admit it

Working through my PhD, I realized something that bugged me. ELF is _already_ a database. It just implements many database primitives by hand, along with a surprising number of
data structures for performance, like a bloom filter for symbol lookup.

| ELF mechanism                     | The database primitive it reinvents |
| --------------------------------- | ----------------------------------- |
| `.strtab` / `.dynstr`             | string interning                    |
| `.hash` / `.gnu.hash`             | an index (`CREATE INDEX`)           |
| section header table              | `sqlite_schema`, a table of tables  |
| `st_name` → offset into `.strtab` | a foreign key, done by hand         |
| `sh_offset` / `sh_size`           | the record layout of a b-tree page  |
| `.gnu.version_r`                  | a column                            |
| `objcopy --strip-debug`           | `DELETE` + `VACUUM`                 |
| `ldconfig` cache, `debuginfod`    | out-of-band indexes over the above  |

If you ever have to analyze or parse ELF, the kernel, `ld.so`, binutils, LIEF, goblin, `readelf`, you are re-implementing the same parser over and over again. Every producer re-implements the same serializer.

The format itself is incredibly terse, designed for a world where disk space and network
bandwidth was at an extreme premium. Modifying the format is hard, you often have to zero out
sections and add new ones since it is packed so tightly. There is also no self-describing schema. ELF itself is a very generic format that supports sections of data that by convention
are interpreted in specific ways but the format does not enforce it.

SQLite is the counter-example. They are a self-describing
format that is extremely stable. It is designed to be extended to support new features without breaking existing consumers and supporting a wide range of queries performantly.

If we were to replace ELF with SQLite, what would fall out and can all of the necessary information be represented in a SQLite database? The answer is yes, and it is surprisingly simple.

# What falls away

A SELF file needs two tables to run: `self_meta` is the ELF header as key/value
pairs and `segments` is the load image, one row per program header with the bytes
in a `BLOB`:

```sql
CREATE TABLE segments (
  -- original phdr index
  id      INTEGER PRIMARY KEY,
  -- 'load' | 'tls' | 'stack' | 'relro'
  type    TEXT NOT NULL,
  -- original file offset
  offset  INTEGER NOT NULL,
  vaddr   INTEGER NOT NULL,
  filesz  INTEGER NOT NULL,
  memsz   INTEGER NOT NULL,
  r INTEGER, w INTEGER, x INTEGER,
  align   INTEGER NOT NULL DEFAULT 4096,
  -- the segment bytes; NULL for pure BSS
  content BLOB
);
```

A single table for the symbol table replaces many of the ELF sections and the `.gnu.hash` index. It is a single table with a single index:

```sql
CREATE TABLE symbols (
  id      INTEGER PRIMARY KEY,
  name    TEXT NOT NULL,
  -- 'GLIBC_2.2.5'
  version TEXT,
  value   INTEGER,
  size    INTEGER,
  -- 'func' | 'object' | 'tls' | ...
  type    TEXT,
  -- 'global' | 'weak' | 'local'
  bind    TEXT,
  defined  INTEGER NOT NULL,
  exported INTEGER NOT NULL
);
CREATE INDEX idx_symbols_name ON symbols(name, version);
```

Our capability to include an index is equivalent to `.gnu.hash` and `.hash` in ELF, but it is a proper b-tree index maintained by SQLite instead of a hand-rolled bloom filter.[^gnuhash]

[^gnuhash]: `.gnu.hash` is a bloom filter plus bucket chains, laid out so
    `ld.so` can reject a miss without touching the chain during symbol discovery.

Surprisingly a lot more falls out as well: `.dynstr` is gone, because `name` is `TEXT` and SQLite already interns strings, symbol versioning is a column, not the `.gnu.version_r` / `.gnu.version_d` contraption and there is no need for a `strings` table.

Other tables exist as well for metadata which exist for tooling: `sections`,
`notes`, `dynamic_entries`. Delete them and the program still
runs, which means `strip(1)` is a transaction:

```console?comments=true
# ldd(1)
$ sqlite3 hello 'SELECT soname FROM ldd' 
libc.so.6

# nm -D --undefined
$ sqlite3 hello 'SELECT name,version FROM imports LIMIT 3'
__libc_start_main|GLIBC_2.34
_ITM_deregisterTMCloneTable|
puts|GLIBC_2.2.5

# readelf -l
$ sqlite3 hello \
    "SELECT type,vaddr,memsz,r,w,x FROM segments WHERE type='load'"
load|0|1744|1|0|0
load|4096|361|1|0|1
load|8192|312|1|0|0
load|15768|640|1|1|0

# strip(1)
$ sqlite3 hello 'DELETE FROM sections; DELETE FROM notes; VACUUM;'
# 57344 -> 49152 bytes

# still runs,  the optional tables were optional
$ ./hello
Hello, world!
```

All the tools that operate on ELF files for reading, reduce to queries over the database.
Any tool that modifies an ELF file, like `strip`, can operate on the database within a transaction rather than performing fragile offset surgery: `strip` is a `DELETE` and `VACUUM`. `patchelf` is an `UPDATE`.

Any information missing from the schema can be easily exposed via a view. For example, `ldd` is a query over the `needed` table, which is a join of the `symbols` table with the `segments` table to find the sonames of the libraries needed by the program.

```sql
CREATE VIEW exports AS SELECT name, version, type, size FROM symbols WHERE exported = 1;
CREATE VIEW imports AS SELECT name, version FROM symbols WHERE defined = 0;
CREATE VIEW ldd     AS SELECT ord, soname FROM needed ORDER BY ord;
```

# How does it work?

SQLite reserves a 4-byte
[`application_id`](https://sqlite.org/pragma.html#pragma_application_id) at byte
offset 68 of its header, for exactly this purpose. We stamp it `SELF`, so an
ordinary SQLite database never matches:

```console
$ xxd -s 64 -l 8 hello
00000040: 0000 0001 5345 4c46                      ....SELF
```

We can now leverage [binfmt_misc](https://docs.kernel.org/admin-guide/binfmt-misc.html), the subsystem that allows you to invoke any binary as if it were native. We need only to register
the magic to trigger on and an interpreter that will invoke our new file format.


On NixOS the registration is a few lines matching the SQLite magic at offset 0
_and_ `SELF` at 68:

```nix
boot.binfmt.registrations.self = {
  recognitionType = "magic";
  offset = 0;
  # bytes 0-15, 68-71
  magicOrExtension = "SQLite format 3\\x00" + ... + "SELF";
  # ignore the middle
  mask = "\\xff..\\x00..\\xff";
  interpreter = "${self-exec}/bin/self-exec";
};
```

For now, I have a small tool `elf2self` that converts an ELF file into a SELF file. It is a simple `postFixup` hook you can opt into per package on NixOS. The tool reads the ELF, extracts the program headers and symbol table, and writes them into the SQLite database. We could look at extending `gcc` or `ld` to emit SELF directly, but for now this is a simple way to explore the idea.

```graphviz
digraph {
  rankdir=LR
  node [shape=box style=rounded fontname="sans-serif" fontsize=14 margin="0.16,0.10"]
  edge [arrowsize=0.8 fontname="sans-serif" fontsize=12]

  elf   [label="hello\n(ELF)"]
  conv  [label="elf2self", shape=note]
  self  [label="hello\n(SQLite db)"]
  krn   [label="execve()\nbinfmt_misc"]
  interp[label="self-exec\n(interpreter)"]
  run   [label="running\nprocess"]

  elf -> conv -> self
  self -> krn [label="magic SELF@68"]
  krn -> interp -> run
}
```

`self-exec` is the interpreter. It is a small C program linked against `libsqlite3`.
Its implementation is remarkably similar to that of `ld.so` but it fetches the program headers and symbol table from the database instead of reading them from the ELF file.
It maps the loadable segments into memory, relocates them, and jumps to the entry point.

> **Note**
> `self-exec` has to stay an ELF file. An interpreter that also matches the
> registration recurses straight into `-ELOOP`.
{: .alert .alert-note }


# Dynamic linking

Running a static program was quick and easy but _boring_ and unimaginative. The interesting part is dynamic linking, which is where the database shines.

I explored two different ways to do dynamic linking. The first is to keep `ld.so` and just replace the lookup with a SQL query via `glibc` [rtld-audit](https://man7.org/linux/man-pages/man7/rtld-audit.7.html) interface, to quickly iterate on the design. The second is to replace `ld.so` entirely with a new dynamic linker that does the entire lookup and binding in SQL.
 
glibc's rtld-audit interface lets an audit library intercept every shared object lookup (`la_objsearch`) before any filesystem search happens, `dlopen` included. The audit library can then answer the question "which library satisfies this symbol?" with a SQL query instead of walking the `RUNPATH` and `LD_LIBRARY_PATH`. Stock `ld.so` maps and relocates it, so the full gamut of glibc features work: lazy PLT, IFUNCs, TLS and symbol versioning, while library storage are rows and library lookups are queries.


```console?comments=true
# no ELF library anywhere on disk
$ rm libgreet.so.1
$ ./app
./app: error while loading shared libraries: 
       libgreet.so.1: cannot open ...

$ self scan --db system.db .
$ SELF_SYSTEM_DB=system.db LD_AUDIT=libself-audit.so ./app
Hello, world, from a SQLite library!
```

I was curious what a fully SQL dynamic linker would look like, so I prototyped one. It is called `self-ld` and it is a small C program that implements the dynamic linker entirely in SQL. It is a proof-of-concept, but it works. It maps every object's segments, publishes their exports, and for each relocation patches the GOT and jumps to the start.

```sql
SELECT s.value + o.load_bias
FROM   relocations r
JOIN   symbols s ON r.symbol = s.id
JOIN   objects o ON s.object = o.id
WHERE  r.id = ?
ORDER BY o.load_order
LIMIT  1;
```

# Cost & Benchmark

The two things that often matter when replacing a well-established format are size and latency. How much bigger is a SELF file than an ELF file, and how much slower is it to run?

**Size.** A SELF file carries SQLite's b-tree overhead and lands at roughly
double the ELF.

```plotnine
import pandas as pd
from plotnine import *

elf  = [15.5, 273.9, 4642.4, 41061.0]
slf  = [56.0, 684.0, 10028.0, 95940.0]     # SELF, unstripped
order = ["hello", "curl", "git", "gdb"]

# A dumbbell, not bars: on a log axis a bar's baseline is arbitrary and a 2x
# gap looks like nothing. The segment IS the overhead.
gap = pd.DataFrame({"subject": order, "lo": elf, "hi": slf,
                    "ratio": [f"{s / e:.1f}x" for e, s in zip(elf, slf)]})
pts = pd.DataFrame({"subject": order * 2, "kib": elf + slf,
                    "kind": (["ELF"] * 4) + (["SELF"] * 4)})
for frame in (gap, pts):
    frame["subject"] = pd.Categorical(frame["subject"],
                                      categories=order[::-1], ordered=True)

plot = (
    ggplot()
    + geom_segment(gap, aes(y="subject", yend="subject", x="lo", xend="hi"),
                   size=1.1, color=INK, alpha=0.35)
    + geom_point(pts, aes("kib", "subject", color="kind"), size=3.4)
    + geom_text(gap, aes(x="hi", y="subject", label="ratio"), size=9,
                color=INK, ha="left", nudge_x=0.06)
    + scale_x_log10(breaks=[10, 100, 1000, 10000, 100000],
                    labels=lambda bs: [f"{b:g}" if b < 1000 else f"{b / 1000:g}K"
                                       for b in bs])
    + scale_color_manual(values={"ELF": "#4c72b0", "SELF": "#b1201d"})
    + expand_limits(x=300000)
    + labs(x="on-disk size (KiB, log scale)", y="", color="")
    + theme(legend_position="top")
)
plot.width, plot.height = 7.0, 3.2
```

Similar to ELF binaries, most of that is recoverable, because the overhead is mostly the optional tables for debugging and tooling. Stripping them and deleting them is a transaction. A stripped `coreutils` SELF is 1,794,048 B against the ELF's 1,768,632 B, that is **within 1%**.

We will see though that there are interesting ways to amortise the overhead even more which I found very unique and interesting.

**Latency.** I benchmarked various binaries from a 15 KiB `hello` to a 42 MiB `gdb`
linking 47 libraries:

```plotnine
import pandas as pd
from plotnine import *

# bench/big.md -- hyperfine -N, warmup 10, min-runs 60. mean +/- sd, ms.
df = pd.DataFrame({
    "subject": ["hello", "curl", "git", "gdb"] * 2,
    "kind": (["ELF"] * 4) + (["SELF"] * 4),
    "mean": [1.401, 11.069, 3.000, 86.109,
             6.915, 15.170, 20.821, 156.414],
    "sd":   [0.303, 2.669, 0.311, 3.248,
             0.678, 1.014, 3.040, 4.492],
})
df["lo"] = df["mean"] - df["sd"]
df["hi"] = df["mean"] + df["sd"]
df["subject"] = pd.Categorical(df["subject"],
                               categories=["hello", "curl", "git", "gdb"],
                               ordered=True)
df["kind"] = pd.Categorical(df["kind"], categories=["ELF", "SELF"],
                            ordered=True)

# Bars from an arbitrary baseline lie on a log axis, so these are points.
plot = (
    ggplot(df, aes("subject", "mean", color="kind"))
    + geom_errorbar(aes(ymin="lo", ymax="hi"),
                    position=position_dodge(0.45), width=0.25, size=0.7)
    + geom_point(position=position_dodge(0.45), size=3.4)
    + scale_y_log10(breaks=[1, 3, 10, 30, 100, 300],
                    labels=lambda bs: [f"{b:g}" for b in bs])
    + scale_color_manual(values={"ELF": "#4c72b0", "SELF": "#b1201d"})
    + labs(x="", y="exec latency (ms, log scale)", color="")
    + theme(legend_position="top")
)
plot.width, plot.height = 7.0, 3.6
```

There is a fixed ~5 ms to open SQLite and start the interpreter, plus a copy proportional
to the image. That copy is worse than it looks, because the b-tree pages are not mapped into memory. Two processes running the same SELF binary do not share text pages the way a normally-`mmap`'d ELF does, because the bytes are copied out of the b-tree rather than mapped.[^curl]

[^curl]: You might notice that `curl` (274 KiB, 27 libraries) starts slower than ELF `git`
    (4.6 MiB, 5 libraries). That is `ld.so` doing work proportional to the
    number of objects rather than the number of bytes, which I have
    [complained about before]({% post_url 2024-05-03-speeding-up-elf-relocations-for-store-based-systems %}).


# The system is a closure

A SQLite database though need not merely be a single executable. It can be a _closure_, a single file that contains a program and all of its transitive dependencies. The `ldd` output of a program is ambiguous: it only lists the sonames of the libraries it needs, not the specific files that satisfy those needs. Nix improves upon this by explicitly resolving every edge to a specific store path via the use of `RUNPATH`.[^runpath]

[^runpath]: I have written about `RUNPATH` on Nix before such as
    [making it redundant]({% post_url 2022-09-12-making-runpath-redundant-for-nix %}) or
    [speeding it up]({% post_url 2022-03-14-shrinkwrap-taming-dynamic-shared-objects %}).

We can do the same in SELF by storing the resolved path of each edge in the database:

```sql
CREATE TABLE objects (id INTEGER PRIMARY KEY, path TEXT UNIQUE,
                      soname TEXT, kind TEXT, is_root INTEGER);
CREATE TABLE needs (
  object_id     INTEGER REFERENCES objects(id),
  ord           INTEGER NOT NULL,
  soname        TEXT NOT NULL,
  -- the FK that kills ambiguity
  resolved_path TEXT REFERENCES objects(path)
);
```

`self closure` packs a binary and its transitive dependencies into **one database**
with those edges filled in. Shared library resolution stops being a guess and
becomes a foreign key and `ldd` becomes a `JOIN` 🤯:

```console
$ self closure "$(readlink -f $(command -v ls))" coreutils.db
ls + closure -> coreutils.db

$ sqlite3 -column coreutils.db \
    "SELECT n.soname, substr(n.resolved_path, 12, 20)
     FROM needs n JOIN objects o ON o.id = n.object_id
     WHERE o.is_root = 1"
libgmp.so.10          rfabfsmwq02sn94mb3qg
libacl.so.1           x0zgiss9hdzcsll3cswg
libattr.so.1          08nfpyc4qhzdkc37nznv
libc.so.6             8kvxvr3pmsypxiypq4g8
```

This single database is a closure of the `ls` executable and its five libraries:
six objects, segment bytes and all, in one 4.8 MiB file. There is no soname ambiguity inside a closure, because a closure by
construction contains exactly one provider per edge.

```graphviz
digraph {
  rankdir=LR
  node [shape=box style=rounded fontname="sans-serif" fontsize=10 margin="0.16,0.09"]
  edge [arrowsize=0.7]

  ls   [label="ls\n(is_root)", style="rounded,filled", fillcolor="#f4f4f4"]
  libc [label="libc.so.6"]
  gmp  [label="libgmp.so.10"]
  acl  [label="libacl.so.1"]
  attr [label="libattr.so.1"]

  ls -> gmp
  ls -> acl
  ls -> attr
  ls -> libc
  acl -> attr
  acl -> libc
  attr -> libc
  gmp -> libc
}
```

# How far does this go? One file, one userland

I hope you've been with me so far, because this is where it gets really interesting.
We can go even further and pack **multiple closures** into a single database.

![Five-panel Inception meme. Cobb: "your executable is a SQLite database."
Fischer: "and the libraries it links?" Cobb: "also SQLite, so is the whole
userland, one file." Fischer: "how far down does this go?" Cobb, winking:
"you are in one right now."](/assets/images/inception-one-file-one-userland.png){: style="--image-width: 20rem"}

I pointed `self closure` at every ELF binary on this system's `PATH`: 723 executables,
which pull in 400 distinct shared libraries. 1,123 objects, 346,386 symbols,
3,808 dependency edges, all as **one SQLite file**.

Turns out when you do that, the database is much smaller than you would expect.

```plotnine
import pandas as pd
from plotnine import *

# 723 root executables from /run/current-system/sw/bin + their ldd closures:
# 1,123 objects total. The straw-man "every root ships its own closure"
# number (5.53 GiB) is left out on purpose -- it would flatten these three.
df = pd.DataFrame({
    "what": ["the member ELF\nfiles on disk",
             "one SQLite\ndatabase",
             "segment payload\n(program bytes)"],
    "mib": [644.4, 611.9, 576.9],
    "kind": ["ELF", "SELF", "payload"],
})
df["what"] = pd.Categorical(df["what"], categories=df["what"][::-1],
                            ordered=True)
df["label"] = [f"{v:.1f} MiB" for v in df["mib"]]

plot = (
    ggplot(df, aes("what", "mib", fill="kind"))
    + geom_col(width=0.62, show_legend=False)
    + geom_text(aes(label="label"), nudge_y=14, size=9, color=INK)
    + scale_fill_manual(values={"ELF": "#4c72b0", "SELF": "#b1201d",
                                "payload": "#8a8580"})
    + coord_flip()
    + expand_limits(y=720)
    + labs(x="", y="total size (MiB)")
)
plot.width, plot.height = 7.0, 2.6
```

**611.9 MiB of database against 644.4 MiB of ELF files.** The whole userland,
as one queryable file, is _smaller_ than the files it came from. The b-tree cost that doubled a single `hello` amortises to nearly nothing across 1,123 objects and is roughly 6% over
the actual program bytes.

The libraries and closure are shared across the executables very similar to how Nix might share them across multiple closures, if the store-path was the same. If every root shipped its own private closure (i.e. the AppImage model), the same 723 programs would come to
5.53 GiB but the deduplication of libraries and symbols falls out naturally from the database schema.

```console
$ sqlite3 userland.db \
    'SELECT count(DISTINCT soname), count(*)
     FROM objects WHERE soname IS NOT NULL'
345|399

$ sqlite3 -column userland.db \
    'SELECT soname, count(*) FROM objects
     WHERE soname IS NOT NULL
     GROUP BY soname HAVING count(*) > 1
     ORDER BY 2 DESC LIMIT 4'
libsystemd.so.0   3
libpthread.so.0   3
libgcc_s.so.1     3
libc.so.6         3

$ sqlite3 userland.db \
    "SELECT count(*)
    FROM needs
    WHERE resolved_path IS NULL AND soname NOT LIKE 'ld-%'"
4
```

Many common idioms we use in ELF immediately fall out of the database. For example, `LD_PRELOAD` is a row in a table rather than an environment variable. The `preload` table is a list of objects to map last, so their exports win. This means that turning `LD_PRELOAD` on and off is a transaction.

```console?comments=true
$ ./app.self; echo $?
13

$ sqlite3 system.db "BEGIN;
    CREATE TABLE preload(ord INTEGER PRIMARY KEY, path TEXT);
    INSERT INTO preload VALUES (0, 'libmul.so.1.self');
  COMMIT;"

# same binary, no env var, no relink
$ ./app.self; echo $?
42

$ sqlite3 system.db 'DELETE FROM preload;'
$ ./app.self; echo $?
13
```

We were able to accomplish an atomic `LD_PRELOAD` across a whole userland
in one file, "interpose a tracing `malloc` everywhere, then `ROLLBACK`" is a
single transaction. 😈

# Where it stands

The format is done and round-trips between ELF and SELF losslessly. The tooling is done and can query, modify, and pack closures.  Lookup through SQL works on unmodified glibc programs perfectly and the native-SQL loader works enough to explore it as a possibility for ideas. 

The whole thing is at [fzakaria/selfdb](https://github.com/fzakaria/selfdb).
`nix run .#self-vm` boots a NixOS VM where `hello` is a SQLite database. 🙌

Nix lets us explore radical ideas like this. We can rebuild the world down to the Linux kernel if needed. We need not be constrained by the existing decisions and constraints of the past. We can explore new ideas and see what falls out. I hope you find this idea as interesting as I do.