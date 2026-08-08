---
layout: post
title: 'Always, sometimes, never'
date: 2026-10-14 11:00 -0700
excerpt_separator: <!--more-->
---

_Exit 0 means your program exited 0. That's it. That's all it means._ 🍞


I have been working on a deterministic VM called [Rewind VM](https://rewindvm.dev), where "a run" (i.e. test, command etc.) is a function of its inputs including the thread schedule. The determinism comes from the tool recording every step which lets you replay it exactly. This alone is a pretty good way to find flaky tests: run the test under Rewind, then `rewind check` runs it under many different thread schedules, with some slight latency added, and failures often crop up. 🐛

<!--more-->

Feedback however was that it was not enough: the tool could find a failing schedule, but it could not tell you if that schedule was _actually_ a bug. It only knew that the run ended differently than the original schedule, which could be a crash, a timeout, or just a different exit code. That is not enough to say "this is a bug".

Someone pointed out that I had built most of a **property-based
testing** tool, but I only had one property: matching exit codes.

What is _property-based testing_?

If you have used [QuickCheck](https://hackage.haskell.org/package/QuickCheck) or
[Hypothesis](https://hypothesis.readthedocs.io), you have already used the idea. You write a property, or constraint, that must hold for every input. The tool generates lots of inputs, and when one breaks the property, it _shrinks_ it down to the smallest input that still fails.

`rewind check` already did the generating and the shrinking. The inputs are thread
schedules, and narrowing shrinks a failing schedule down to the one step that causes the failure. The only property though was "the run ends the same way schedule 0 did": the same exit code and the same outputs.

That's a pretty low bar, but easy to improve. 🙃

Rewind now lets specify properties that must be true for every run, or must be true for at least one run, or must never be true in any run.

[![A photo of a bag of Wonder bread with the logo changed to REWIND and the tagline to 11 Built-in Properties, SDK, JUnit, Seeds. The meme caption reads: now with property-based testing, the best thing since sliced bread.](/assets/images/rewind_sliced_bread_meme.png)](/assets/images/rewind_sliced_bread_meme.png)

## Two tellers: Java Edition ☕

Let's keep the bank from [last time]({%post_url 2026-10-07-nix-wrote-half-of-my-debugger %}): two tellers deposit into one account from two threads, **without a lock**.

This time the example is in Java as a JUnit 5 suite to appeal to my Enterprise brethren.[^example]

[^example]: It is [`bank-java`](https://github.com/fzakaria/rewindvm/tree/main/examples/bank-java) in the Rewind repository, next to the C version.

```java
void deposit(int teller, long amount) {
    long seen = balance;
    System.out.println("teller " + teller + ": " +
                        seen + " + " + amount);
    balance = seen + amount;
}
```

A teller that runs between the other's read and store writes a stale balance over the other's
deposit. 💥

We include a "typical" test suite: one teller, two tellers concurrently, and a new account being empty. We run it and see all tests pass and head home for the day. 🍺

Is the code correct? Let's use Rewind to dig further.

## Properties that come in the box

Before even looking at the balance, Rewind knows a lot about what a run _did_. Every open,
write, rename, close, fork and exit is in the trace, with the step it happened at. Rewind ships
properties computed from the trace alone:

| Property                     | A run violates it when                                                 |
| ---------------------------- | ---------------------------------------------------------------------- |
| `no-crash`                   | a process dies of a signal such as SIGSEGV, even if a retry hid it     |
| `no-orphans`                 | a process the job started is still running when the job exits          |
| `single-writer=GLOB`         | two processes have a matching file open for writing at once            |
| `atomic-replace=GLOB`        | a matching file is truncated in place instead of renamed over          |
| `no-read-while-written=GLOB` | a matching file is opened for reading while another process writes it |
| `writes-within=DIR:DIR`      | the job writes outside these directories                               |
| `junit=GLOB`                 | a test that passed on schedule 0 fails, by the JUnit XML reports       |
| `script=PATH`                | a program of yours exits 1                                             |

Let's throw a few at the bank and only run schedule 0:

```console
$ rewind check --schedules 0 --property no-crash --property no-orphans \
    --property 'writes-within=/build' github:fzakaria/rewindvm#bank-java
schedule   0: exited:0     148479 steps  ba3f68ae3869  run bd3b527f0a837af8  violates writes-within
  writes-within: step 2710: process 111 (javac) opened /tmp/hsperfdata_nixbld/111 for writing, outside /build
never true in any run: sometimes "deposits-concurrent"
every schedule violated a property, as schedule 0 did
```


Interesting! `javac` writes its performance counters to `/tmp/hsperfdata_<user>/<pid>`[^perfdata]. It has nothing to do with our bug, but I included it because I learned something new and it could have been a bug if it did not include the process ID.

[^perfdata]: `-XX:-UsePerfData` turns it off.

The file properties shine for bugs between processes. The
[properties tutorial](https://rewindvm.dev/tutorials/properties.html) has a program that
rewrites its config in place while another process rereads it. Its own test fails only
when a read lands between the truncate and the last write, but `atomic-replace` flags it on
the very first run. 😲

## Asserting from the inside

The bank's real invariant is not in any syscall though. It lives in memory in our example: _the balance variable must add up_.

For that there is the [Rewind SDK](https://github.com/fzakaria/rewindvm/tree/main/sdk), a tiny library you call from your program. Each call
writes one line to `/dev/rewind`, a device in Rewind's VM, and the trace keeps it with the
step, process and thread that wrote it.[^outside]

[^outside]: Outside Rewind the device does not exist and every call does nothing, so the calls can stay in your code.

```java
// Account.deposit: another teller is mid-deposit.
int others = depositing.getAndIncrement();
Rewind.sometimes(others > 0, "deposits-concurrent");

// BankTest.twoTellersDeposit
Rewind.always(balance == expected, "balance-adds-up",
        () -> "balance " + balance + ", expected " + expected);
```

`always` must be true every time the program reaches it. `unreachable` is its opposite: a run that reaches it at all fails. These are your typical `assertions`, except we get the whole replay if it fails.

`sometimes` is the one I find the most interesting and tough to think through at times. 🤓 It tests the search: its condition must be true in at least one of the runs check tries, and it never fails a run. In model-checking terms, `always` is a _safety property_ (nothing bad happens in any run) and `sometimes` is a _reachability property_ (some run gets there). Here it asks whether any run had both tellers inside `deposit` at the same time.

Look at the output above again:

```console
never true in any run: sometimes "deposits-concurrent"
```

The suite passed under schedule 0, but one teller always finished its deposit before the
other started. That pass told us nothing about the race. 🤷

[![Anakin and Padme meme. Anakin: my tests passed. Padme, smiling: so the deposits overlapped, right? Anakin says nothing. Padme: they overlapped, right?](/assets/images/rewind_anakin_padme_meme.png)](/assets/images/rewind_anakin_padme_meme.png)
{: style="--image-width: 24rem"}

Let `check` try its default 64 schedules:

```console?comments=true
$ rewind check github:fzakaria/rewindvm#bank-java
...
true in 11 of 17 runs that checked it: sometimes "deposits-concurrent"
...
step 145417 decides it: a reschedule and a 10 µs stall there makes the run violate same-outcome, sdk

passing: run 61643f768ec51337, schedule 2 over steps 144694..145417
failing: run 643a298ef0ec3f7b, schedule 2 over steps 144694..145418
the two are the same run until step 145417
failing run violates same-outcome: step 149407: ended exited:2, where bd3b527f0a837af8 ended exited:0
failing run violates sdk: step 145713: always "balance-adds-up" failed: balance 380, expected 400
```

That took 40 seconds on my laptop[^jvm] and we found that two deposits went missing.

The first line is the `sometimes` again: of the 17 runs check tried before it found the
failure, 11 had both tellers inside `deposit` at once.

[^jvm]: The JVM is chatty: 148,479 steps for three tests, where the C equivalent takes about 4,500.

## Did I truly fix it?

The fix is the obvious one: hold a lock from the read to the store.

```java
int others = depositing.getAndIncrement();
Rewind.sometimes(others > 0, "deposits-concurrent");
synchronized (lock) {
    long seen = balance;
    System.out.println("teller " + teller + ": " +
                        seen + " + " + amount);
    balance = seen + amount;
}
depositing.decrementAndGet();
```

```console
$ rewind check .#bank-java
...
true in 42 of 65 runs that checked it: sometimes "deposits-concurrent"
every property held under all 65 schedules
```

Every schedule passes, but is that enough to make us feel warm and fuzzy?

The `sometimes` line is what gives me the warm embrace: in 42 of the 65 runs the tellers ran concurrently, but the lock prevented the bug. ✅[^sync]

A condition that is only true when the bug happens can never be true once the bug is fixed. 💡

[^sync]: This counter must sit outside the lock. With `synchronized void deposit`, the second teller would wait before it reaches the counter.

## JUnit

Java developers though love writing JUnit tests. Fear not my [FizzBuzzEnterprise](https://github.com/enterprisequalitycoding/fizzbuzzenterpriseedition) colleagues, Rewind has you covered: the SDK has a JUnit 5 extension. 

Put `@ExtendWith(RewindExtension.class)` on the test class and it marks each test's start and result.

```java
@ExtendWith(RewindExtension.class)
class BankTest { ... }
```

If you can't touch the code, `junit=GLOB` reads the XML reports the runner wrote instead:
Maven's surefire, Gradle, pytest's `--junitxml`, whatever writes the format.

```console
$ rewind check --property 'junit=TEST-*.xml' github:fzakaria/rewindvm#bank-java
...
step 145417 decides it: a reschedule and a 10 µs stall there makes the run violate junit, sdk
failing run violates junit: step 149407: test BankTest.twoTellersDeposit() passed in the unperturbed run and failed here
failing run violates sdk: step 145713: always "balance-adds-up" failed: balance 380, expected 400
```

## Visualizing properties

The Rewind app shows the timeline of a run, with the tests and the build log. The failing test is red, and the event card names the assertion that failed.

```console
$ rewind open 643a298e 145713 --compare 61643f76
```

[![The Rewind app at step 145,713 of the failing bank-java run, compared with the passing run: the timeline zoomed to the tests, the build log ending in always "balance-adds-up" failed: balance 380, expected 400 in red, and the event card naming the failed assertion](/assets/images/rewind-junit-assertion.png)](/assets/images/rewind-junit-assertion.png)

The strip under the timeline has a span per test: green passed, red failed. Each include a helpeful tooltip with the test name and the steps it ran.

[![The timeline's test strip: a green span for the first test, a red one for the second, and a pointer on the red span showing Test BankTest.twoTellersDeposit failed, steps 145,291 to 145,986](/assets/images/rewind-junit-test-strip.png)](/assets/images/rewind-junit-test-strip.png)


All the other Rewind features can then be used to help isolate the cause: the source
panel, gdb on a fork at any step, the thread lanes and Check from here.


## Easy Peasy ?

There is a SDK for many languages already included in the Rewind repository. They are tiny, and the only dependency is the Rewind VM itself. The SDK is a single file or two per language, and you can copy it into your project.[^languages]

[^languages]: The [SDK's README](https://github.com/fzakaria/rewindvm/tree/main/sdk) has the format instrunctions if you want to write one for another language.

- **C and C++**: `rewind.h`, `REWIND_ALWAYS(cond, "id", "fmt", ...)`
- **Rust**: `rewind_sdk::always!(cond, "id", "fmt", ...)`
- **Go**: `rewind.Always(cond, "id", "fmt", ...)` and `rewind.Track(t)` for `go test`
- **Python**: `rewind_sdk.always(cond, "id")`, and a pytest plugin that loads itself
- **Java**: `Rewind.always(cond, "id")` and the JUnit 5 extension
- **Shell**: `rewind_always id "message" test "$x" -eq 3`

```console
$ curl -fsSL https://rewindvm.dev/install | sh
$ rewind check github:fzakaria/rewindvm#bank-java
```

The [properties tutorial](https://rewindvm.dev/tutorials/properties.html) goes through each
piece step by step, and the [advanced tutorial](https://rewindvm.dev/tutorials/advanced.html)
has script properties and a file of properties to keep beside your tests for the more adventurous.

If you happen to find any interesting bugs with Rewind let me know. I am keeping track of a small [leaderboard](https://rewindvm.dev/bugs.html) of the best ones. 🏆