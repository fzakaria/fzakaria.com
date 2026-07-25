---
layout: post
title: Quick insights using sqlelf
date: 2023-09-11 21:12 +0000
excerpt_separator: <!--more-->
---

> Please checkout the [sqlelf](https://github.com/fzakaria/sqlelf) repository and give me your feedback.

I wrote in my earlier [post]({% post_url 2023-03-19-sqlelf-and-20-years-of-nix %}) about releasing [sqlelf](https://github.com/fzakaria/sqlelf).
I had the hunch that the existing tooling we have to interface with our object formats, such as ELF, are antiquated and ill specified.

Declarative languages, such as SQL, are such a wonderful abstraction to articulate over data layouts and let you reason about _what you want_ rather than _how to get it_.

Since continuing to noodle 👨‍💻 on the project, I've been pleasantly surprised at some of the introspection, specifically with respect to symbols, I've been able
to accomplish with SQL that would have been a pain using traditional tools.

<!--more-->

Come on a stroll with me on a few case studies I've gone through on how SQL guided analysis wins out.

## Symbol Resolution

One of the primary data structures within the ELF file is the symbol table, especially the _dynamic symbol table_ that allows the use of shared objects (libraries).

A typical question someone may ask themselves though is:

__Which library that I load is providing _function foo_?__

This is a worthwhile question because you would like to know which shared object is not only providing the symbol definition but also which the linker (`ld.so`) chooses
to link against at runtime.

The _state of the art_ (prior to sqlelf) of how to retrieve this diagnostic information is using `LD_DEBUG` environment variable and trolling through the large dump of logs it emits. 🤦

```console
$ LD_DEBUG=symbols,bindings /usr/bin/ruby |& head
   1228310:	symbol=__vdso_clock_gettime;  lookup in file=linux-vdso.so.1 [0]
   1228310:	binding file linux-vdso.so.1 [0] to linux-vdso.so.1 [0]: normal symbol `__vdso_clock_gettime' [LINUX_2.6]
   1228310:	symbol=__vdso_gettimeofday;  lookup in file=linux-vdso.so.1 [0]
   1228310:	binding file linux-vdso.so.1 [0] to linux-vdso.so.1 [0]: normal symbol `__vdso_gettimeofday' [LINUX_2.6]
   1228310:	symbol=__vdso_time;  lookup in file=linux-vdso.so.1 [0]
   1228310:	binding file linux-vdso.so.1 [0] to linux-vdso.so.1 [0]: normal symbol `__vdso_time' [LINUX_2.6]
   1228310:	symbol=__vdso_getcpu;  lookup in file=linux-vdso.so.1 [0]
   1228310:	binding file linux-vdso.so.1 [0] to linux-vdso.so.1 [0]: normal symbol `__vdso_getcpu' [LINUX_2.6]
   1228310:	symbol=__vdso_clock_getres;  lookup in file=linux-vdso.so.1 [0]
   1228310:	binding file linux-vdso.so.1 [0] to linux-vdso.so.1 [0]: normal symbol `__vdso_clock_getres' [LINUX_2.6]
```

Let's see how we can re-think of this question as a declarative SQL statement:

```SQL
SELECT caller.path as 'caller.path',
       callee.path as 'calee.path',
       caller.name,
       caller.demangled_name
FROM ELF_SYMBOLS caller
INNER JOIN ELF_SYMBOLS callee
ON
caller.name = callee.name AND
caller.path != callee.path AND
caller.imported = TRUE AND
callee.exported = TRUE
```

We can think of the above ask asking: 

_Please provide all pairings of symbols where the name is the same between any two different ELF files.
One of the files must export the symbol and the other must be importing it._

```console
$ sqlelf /usr/bin/ruby --sql "SELECT caller.path as 'caller.path',
       callee.path as 'calee.path',
       caller.name
FROM ELF_SYMBOLS caller
INNER JOIN ELF_SYMBOLS callee
ON
caller.name = callee.name AND
caller.path != callee.path AND
caller.imported = TRUE AND
callee.exported = TRUE
LIMIT 10"
┌───────────────┬────────────────────────────────────────────────┬───────────────────┐
│  caller.path  │                   calee.path                   │       name        │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libruby-3.1.so.3.1.2 │ ruby_run_node     │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libruby-3.1.so.3.1.2 │ ruby_init         │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libruby-3.1.so.3.1.2 │ ruby_options      │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libruby-3.1.so.3.1.2 │ ruby_sysinit      │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libc.so.6            │ __stack_chk_fail  │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libruby-3.1.so.3.1.2 │ ruby_init_stack   │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libc.so.6            │ setlocale         │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libc.so.6            │ __libc_start_main │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libc.so.6            │ __libc_start_main │
│ /usr/bin/ruby │ /usr/lib/x86_64-linux-gnu/libc.so.6            │ __cxa_finalize    │
└───────────────┴────────────────────────────────────────────────┴───────────────────┘
```

🥳 That sure beats dealing with unstructured text. sqlelf can also emit a myriad of output formats such as csv or json. 

## Symbol Shadowing

The reality of `LD_DEBUG` however is that it usefulness came in knowing the _final resolution_ of a given symbol.

ELF files are free to have and export any symbols and often times, whether by accident (benign) or maliciously, the same symbol may be exported by
multiple libraries.

> This is what empowers tools such as `LD_PRELOAD` so that users can take over symbols such as `malloc` and replace them with alternative strategies.

The linker, according to the [SystemV ABI](https://refspecs.linuxbase.org/elf/gabi4+/ch5.dynamic.html), examines the symbol tables with a breadth-first search across the dependency graph of the shared object libraries.

A typical question someone may ask themselves though is:

__What symbols are currently shadowed in my dependency graph?__

Let's see how we can re-think of this question as a declarative SQL statement:

```SQL
SELECT name, version, count(*) as symbol_count,
       GROUP_CONCAT(path, ':') as libraries
FROM elf_symbols
WHERE exported = TRUE
GROUP BY name, version
HAVING count(*) >= 2
```

We can think of the above ask asking: 

_Please provide me all symbols (and the library that defines them) that are exported by more than 2 libraries_.

Any symbol here is technically being shadowed, whether on purpose or benign.

Revisiting the same _ruby_ example above we can see the results.
```console
$ sqlelf /usr/bin/ruby --recursive --sql "
SELECT name, version, count(*) as symbol_count,
       GROUP_CONCAT(path, ':') as libraries
FROM elf_symbols
WHERE exported = TRUE
GROUP BY name, version
HAVING count(*) >= 2"
┌────────────┬─────────────┬──────────────┬─────────────────────────────────────────────────────────────────────────┐
│    name    │   version   │ symbol_count │                                libraries                                │
│ __finite   │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ __finitef  │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ __finitel  │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ __signbit  │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ __signbitf │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ __signbitl │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ copysign   │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ copysignf  │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ copysignl  │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ finite     │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ finitef    │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ finitel    │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ frexp      │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ frexpf     │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ frexpl     │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ ldexp      │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ ldexpf     │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ ldexpl     │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ modf       │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ modff      │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ modfl      │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ scalbn     │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ scalbnf    │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
│ scalbnl    │ GLIBC_2.2.5 │ 2            │ /usr/lib/x86_64-linux-gnu/libm.so.6:/usr/lib/x86_64-linux-gnu/libc.so.6 │
└────────────┴─────────────┴──────────────┴─────────────────────────────────────────────────────────────────────────┘
```

In this particular case, there is no malicious symbol shadowing and the symbols shadowed by `libm` and `libc` are well
known. In fact, on many systems, `libm` is a symlink to `libc`.

I have [previously written](https://arxiv.org/abs/2211.05118) about through the development of [shrinkwrap](https://github.com/fzakaria/shrinkwrap) that a more
annoying shadowing can happen with OpenMPI. It's pretty easy to accidentally get the _no-op_ library implementation earlier in
breadth-first search and find yourself with a sequential application.

I've included a neat [example](https://github.com/fzakaria/sqlelf/blob/main/examples/shadowed-symbols/Makefile) in the sqlelf repository that you can play with
to test shadowing symbols and see the results of sqlelf. 🕵️

If you find any of this fascinating, contribute and let's work to make accessing ELF via SQL simple and productive.
