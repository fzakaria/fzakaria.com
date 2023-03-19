---
layout: post
title: sqlelf and 20 years of Nix
date: 2023-03-19 20:48 +0000
excerpt_separator: <!--more-->
---

> If you want to skip ahead, please checkout the [sqlelf](https://github.com/fzakaria/sqlelf) repository and give me your feedback.

🎉 We are celebrating 20 years of [Nix](https://nixos.org) 🎉


Within that 20 years Nix has ushered in a new paradigm of how to build software reliably that is becoming more ubiquitous in the software industry.
It has inspired imitators such as [Spack](https://spack.io/) & [Guix](https://guix.gnu.org/).

Given the concepts introduced by Nix and it's willingnes to eschew some fundamental Linux concepts such as the Filesystem Hierarchy Standard.


I can't help but think _has Nix gone far enough within the 20 years?_

<!--more-->

If you have kept an eye on some of the work I've been doing and thinking of, I have spent some time thinking how Nix can make further progress on goals of reliability and reproducibility.

> If you haven't seen my talk on [Rethinking basic primitives for store based systems](https://www.youtube.com/watch?v=HZKFe4mCkr4), I recommend you watch it.

Nix, and more specifically NixOS, is uniquely poised to do-away with many of the historic cruft that has plaque us in software due to the fact that it's dependency closure goes down to the Linux kernel!

There is no short-list of components we can re-imagine however I have been focused on the dynamic linker / interpreter. Concepts of the *Unixes of the world which are largely historic are up for grabs.


As part of my work on [Shrinkwrap](https://github.com/fzakaria/shrinkwrap), I was getting pretty frustrated working with the ELF file format.

> Checkout my SuperComputing 2022 paper [Mapping Out the HPC Dependency Chaos](https://arxiv.org/abs/2211.05118)

The best tools we have to introspect binaries are `readelf` and `objdump` whom simply dump raw ASCII text to the console.
```console
❯ readelf --demangle --dyn-syms /usr/bin/ruby | head

Symbol table '.dynsym' contains 22 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND 
     1: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND ruby_run_node
```

_Why are we restricted to such a challenging file format to work with?_

I am working on an idea which I am very excited about 🤓 which I will be writing about.
To prove to myself that the idea has merit, I wanted to explore making a tool that allows for easier introspection of ELF files.


Using the power of [SQLite](https://sqlite.org/index.html) and the Virtual Tables concept, I wrote [sqlelf](https://github.com/fzakaria/sqlelf): _Explore ELF objects through the power of SQL._

```console
❯ sqlelf /usr/bin/ruby /bin/ls /usr/bin/pnmarith
sqlite> SELECT elf_headers.path, COUNT(*) as num_sections
    ..> FROM elf_headers
    ..> INNER JOIN elf_sections ON elf_headers.path = elf_sections.path
    ..> WHERE elf_headers.type = 3
    ..> GROUP BY elf_headers.path;
path|num_sections
/bin/ls|31
/usr/bin/pnmarith|27
/usr/bin/ruby|28
```

If I can prove a clean 1:1 mapping between the two formats then there is an amazing room for potential.

I am still working through the domain model mapping to individual tables (_contributions and help appreciated!_) but I am really excited by this idea.
1. Linker specifications can be articulated with SQL to guarantee semantics. 
2. Dynamic loader specifications can also be defined with SQL + potentially use of ACID constraints.
3. Analysis of files can be done at large easily using SQL.
4. We remove a custom file format.


Unix introduced the simple concept of _what if everything was a file?_


🙈 🙉 🙊 __What if everything was a database?__ 🙈 🙉 🙊 