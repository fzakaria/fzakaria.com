---
layout: post
title: Leaving performance on the table
date: 2026-05-23 08:06 -0700
---

I have been working with LLVM at `$DAYJOB$`, and I have gotten to become familiar with the benefits of optimizing your workloads.

I tend to think of optimizing my binaries as thinking about whether I have attached `-O3` to my compiler flags; maybe if I'm particularly advanced that day I'll sprinkle in some `-flto` (link time optimziation) and call it a day.

Turns out though that's leaving lots of performance on the table.

Compilers work under the assumption that every branch is equally taken, unless you are hints like `[[likely]]` ([ref](https://en.cppreference.com/cpp/language/attributes/likely)). If we can feed the compilers more information about the likely path that our workloads often take, then they can produce much more performant code.

There are two primary ways to optimize a binary: instrumented or statistical. When we instrument our binary, we run our workload with an instrumented binary and capture _the exact paths_ that are executed. We will then optimize the binary perfectly tuned to that workload.

If our workloads however are varied, we can collect profiles via `perf` over a length of time and create an optimized binary based on the statistical occurence of call graphs.

Both approaches have their benefits however let's start with the instrumented variant first, as it's a little easier to follow and understand.

Let's look at a very simple benchmark. We will calculate **fibonocci** using SQL in [sqlite3](https://sqlite.org). This is an ideal workload because it's purely CPU-bound and ripe for optimizing.

```sql
-- fibonacci.sql (100 Million Iterations)
WITH RECURSIVE fibonacci(n, a, b) AS (
    -- Seed values
    SELECT 0, 0, 1
    
    UNION ALL
    
    -- Loop 100,000,000 times. 
    -- The modulo keeps the integers safely within 64-bit bounds.
    SELECT n + 1, b, (a + b) % 1000000007 
    FROM fibonacci 
    WHERE n < 100000000
)
-- Only output the final computed value to avoid terminal I/O bottlenecks
SELECT a FROM fibonacci WHERE n = 100000000;
```

We will compile `sqlite3` from source by downloading it.

```bash
> wget https://sqlite.org/2026/sqlite-amalgamation-3530100.zip
> unzip sqlite-amalgamation-3530100.zip
```

We can compile a "traditional" optimized binary that merely has `-O3` and also a version that has LTO enabled since I was also keen to see how much LTO itself adds.

```bash
> clang -O3 shell.c sqlite3.c -o sqlite3_base

> clang -O3 -flto shell.c sqlite3.c -o sqlite3_lto

# let's run it just to see some rough times
> time ./sqlite3_base :memory: < ./fibbonoci.sql
╭───────────╮
│     a     │
╞═══════════╡
│ 908460138 │
╰───────────╯

________________________________________________________
Executed in   14.22 secs    fish           external
   usr time   14.16 secs    0.00 micros   14.16 secs
   sys time    0.00 secs  802.00 micros    0.00 secs
```

Ok, so it looks like our program takes roughly 14-15 seconds to run.
Sounds ok? How much better can we do.... 🤔


Next, we compile our program again but we _instrument the binary_, which effectively injects counters into the program to count invocations of functions. We get very accurate counts of our calls but the binary itself now runs much slower, which can be a problem if your workload was already very slow. Luckily for us, we are in a time domain (~15 seconds), where that is ok.

After we have our instrumented binary, we run our workload again to generate the profile data and rebuild the binary with that data.


```bash
# 1. Build the instrumented version for Clang
> clang -O3 -flto -fprofile-generate=. shell.c sqlite3.c -o sqlite3_instr

# 2. Run the 100M Fibonacci loop to generate Clang profile data
> ./sqlite3_instr :memory: < ../fibonacci.sql

# 3. Merge the raw profile
> ./llvm-profdata merge -output=sqlite3.profdata *.profraw

# 4. Build the PGO-optimized binary, BUT preserve relocations for BOLT (-Wl,-q)
./ clang -O3 -flto -fprofile-use=sqlite3.profdata -Wl,-q shell.c sqlite3.c -o sqlite3_pgo
```

The last step will be to optimize with BOLT, which is a post-link optimizer, which requires us to keep relocations so I've also added `-Wl,-q`.

When we run our workload with the final optimized binary, we see massive improvement already! 🤯

```bash
> time ./sqlite3_pgo :memory: < ./fibbonoci.sql
╭───────────╮
│     a     │
╞═══════════╡
│ 908460138 │
╰───────────╯

________________________________________________________
Executed in   10.86 secs    fish           external
   usr time   10.83 secs    0.00 micros   10.83 secs
   sys time    0.00 secs  770.00 micros    0.00 secs
```

We've cut our workload time down to ~10 seconds which is a nearly a **1.5x** improvement.

Now let's optimize the final binary with LLVM's [BOLT](https://github.com/llvm/llvm-project/blob/main/bolt/README.md). BOLT is a post-link optimizer designed for "large applications". What this means, is that it largely works by shuffling code around the binary to keep code-paths that have high temporal locality near each other (spatial locality). This can have positive impact on performance due to the instruction cache for instance.

```bash
# 1. Instrument the PGO binary with BOLT
> llvm-bolt sqlite3_pgo -o sqlite3_bolt_instr --instrument --instrumentation-file=bolt.fdata

# 2. Run the workload AGAIN to trace the physical execution path
> ./sqlite3_bolt_instr :memory: < ../fibonacci.sql

# 3. Apply the final BOLT optimizations on top of the PGO binary
> llvm-bolt sqlite3_pgo -o sqlite3_ultimate \
    -data=bolt.fdata \
    -reorder-blocks=ext-tsp \
    -reorder-functions=hfsort+ \
    -split-functions \
    -dyno-stats

> time ./sqlite3_ultimate :memory: < ./fibbonoci.sql
╭───────────╮
│     a     │
╞═══════════╡
│ 908460138 │
╰───────────╯

________________________________________________________
Executed in   10.52 secs    fish           external
   usr time   10.46 secs  591.00 micros   10.46 secs
   sys time    0.01 secs  244.00 micros    0.01 secs
```

Looks like it was a little faster but not much. That makes sense since `sqlite3` itself is a pretty small binary (~6MB), but nontheless was good to run through.

Running a more _thorough_ benchmark with `hyperfine` we can get a final tally of our results.

| Build Configuration | Mean Time ± σ | Min … Max| Relative Speed (vs Fastest) |
| ------------------|-------------|---------|--------------------------:|
| PGO+BOLT|10.536 s ± 0.051 s|10.491 s … 10.631 s|1.00|
| PGO | 10.805 s ± 0.055 s | 10.733 s … 10.889 s | 1.03 ± 0.01 |
| LTO | 14.252 s ± 0.026 s | 14.225 s … 14.315 s | 1.35 ± 0.01 |
| Basic (no LTO) | 14.292 s ± 0.071 s | 14.224 s … 14.435 s | 1.36 ± 0.01 |
| Fedora package | 14.496 s ± 0.074 s | 14.402 s … 14.662 s | 1.38 ± 0.01 |

Looks like the `sqlite3` I got from the Fedora ecosystem was the _slowest_. When all the optimizations were applied I was able to get a maximum of **1.38x** faster than what was available.

These optimizations would be even more dramatic for code-bases that are a sprawl and can heavily vary.

Don't worry also about getting the profile perfectly tuned to your workloads.
I have a coworker who often cites that even poor profiles are still much better than no profile at all.