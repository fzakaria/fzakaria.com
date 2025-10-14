---
layout: post
title: Fuzzing for fun and profit
date: 2025-10-07 12:05 -0700
---

I watched recently a keynote by [Will Wilson](https://antithesis.com/company/leadership/) on fuzzing -- [Fuzzing'25 Keynote](https://www.youtube.com/watch?v=qQGuQ_4V6WI). The talk is excellent, and one main highlight is the fact we have at our disposal is the capability to _"fuzz"_ our software toaday and yet we do not.

While I've seen the power of [QuickCheck-like tools](https://github.com/pholser/junit-quickcheck) to create property based testing, I never had never used fuzzing over an application as a whole, specifically [American Fuzzy Lop](https://github.com/google/AFL). I was intrigued to add this skill to my toolbelt and maybe apply it to [CppNix](https://github.com/NixOS/nix).

As with everything else, I need to learn things from _first principles_. I would like to create a scenario with a known-failure and see how AFL discovers it.

To get started let's first make sure we have access to AFL via [Nix](http://nixos.org/).

> We will be using [AFL++](https://aflplus.plus/), the daughter of AFL that incorporates newer updates and features.

```bash
> nix-shell -p aflplusplus
```

How does AFL work? 🤔

AFL will feed your program various inputs to try and cause a crash! 💥

In order to generate better inputs, you compile your code with a variant of `gcc` or `clang` distributed by AFL which will insert special instructions to keep track of coverage of branches as it creates various test cases.

Let's create a `demo` program that crashes when given the input `Farid`.

> We leverage a `volatile int` so that the compiler does not optimize the multiple `if` instructions together.

```c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>

#define INPUT_SIZE 10

void crash() {
  raise(SIGSEGV);
}

int main(int argc, char *argv[]) {
  char buffer[INPUT_SIZE] = {0};

  if (fgets(buffer, INPUT_SIZE, stdin) == NULL) {
    fprintf(stderr, "Error reading input.\n");
    return 1;
  }

  // So the if statements are not optimized together
  volatile int progress_tracker = 0;

  if (strlen(buffer) < 5) {
    return 0;
  }

  if (buffer[0] == 'F') {
    progress_tracker ++;
    if (buffer[1] == 'a') {
      progress_tracker ++;
      if (buffer[2] == 'r') {
        progress_tracker ++;
        if (buffer[3] == 'i') {
          progress_tracker ++;
          if (buffer[4] == 'd') {
            crash();
          }
        }
      }
    }
  }
  return 0;
}
```

We now can compile our code with `afl-cc` to get the _instrumented binary_.

```bash
> afl-cc demo.c -o demo
```

AFL needs to be given some sample inputs 
Let's feed it the simplest starter seed possible -- an empty file!

```bash
> mkdir -p seed_dir
> echo "" > seed_dir/empty_input.txt
```

Now we simply run `afl-fuzz`, and the _magic happens_. ✨

```bash
> afl-fuzz -i seed_dir -o out_dir -- ./demo
```

A really nice TUI appears that informs you of various statistics of the running fuzzer, and importantly _if any crashes had been found_ -- `saved crashes : 1 ` !

```
          american fuzzy lop ++4.32c {default} (./demo) [explore]          
┌─ process timing ────────────────────────────────────┬─ overall results ────┐
│        run time : 0 days, 0 hrs, 33 min, 4 sec      │  cycles done : 3191  │
│   last new find : 0 days, 0 hrs, 33 min, 2 sec      │ corpus count : 6     │
│last saved crash : 0 days, 0 hrs, 33 min, 1 sec      │saved crashes : 1     │
│ last saved hang : none seen yet                     │  saved hangs : 0     │
├─ cycle progress ─────────────────────┬─ map coverage┴──────────────────────┤
│  now processing : 4.7238 (66.7%)     │    map density : 16.67% / 44.44%    │
│  runs timed out : 0 (0.00%)          │ count coverage : 45.00 bits/tuple   │
├─ stage progress ─────────────────────┼─ findings in depth ─────────────────┤
│  now trying : havoc                  │ favored items : 5 (83.33%)          │
│ stage execs : 496/800 (62.00%)       │  new edges on : 6 (100.00%)         │
│ total execs : 13.5M                  │ total crashes : 1014 (1 saved)      │
│  exec speed : 6566/sec               │  total tmouts : 0 (0 saved)         │
├─ fuzzing strategy yields ────────────┴─────────────┬─ item geometry ───────┤
│   bit flips : 0/0, 0/0, 0/0                        │    levels : 5         │
│  byte flips : 0/0, 0/0, 0/0                        │   pending : 0         │
│ arithmetics : 0/0, 0/0, 0/0                        │  pend fav : 0         │
│  known ints : 0/0, 0/0, 0/0                        │ own finds : 5         │
│  dictionary : 0/0, 0/0, 0/0, 0/0                   │  imported : 0         │
│havoc/splice : 6/13.5M, 0/0                         │ stability : 100.00%   │
│py/custom/rq : unused, unused, unused, unused       ├───────────────────────┘
│    trim/eff : 64.13%/20, n/a                       │          [cpu000: 18%]
└─ strategy: exploit ────────── state: running...  ──┘
```

The output directory contains all the saved information including the input that caused the crashes.

Let's inspect it!

```bash
> cat "out_dir/default/crashes/id:000000,sig:11,src:000005,time:2119,execs:14486,op:havoc,rep:1" 
Farid
```

Huzzah! 🥳

AFL was successfully able to find our code-word, `Farid`, that caused the crash.

It is important to note however that for my simple program it found the failure-case rather quickly, however for large programs it can take a long time to explore the complete state space. Companies such as Google, continously run fuzzers such as AFL on well-known open source projects to help detect failures.