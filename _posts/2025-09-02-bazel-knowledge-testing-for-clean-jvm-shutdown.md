---
layout: post
title: 'Bazel Knowledge: Testing for clean JVM shutdown'
date: 2025-09-02 13:57 -0700
---

Ever run into the issue where you exit your `main` method in Java but the application is still running?

That can happen if you have _non-daemon_ threads still running. 🤔

The JVM specification specifically states the condition under which the JVM may exit [[ref](https://docs.oracle.com/javase/specs/jls/se8/html/jls-12.html#jls-12.8)]:

> A program terminates all its activity and exits when one of two things happens:
> * All the threads that are **not daemon threads** terminate.
> * Some thread invokes the `exit()` method of `class Runtime` or `class System`, and the exit operation is not forbidden by the security manager.

What are daemon-threads?

They are effectively _low-priority_ threads that you might spin up for tasks such as garbage collection, where you explicitly don't want them to inhibit the JVM from shutting down.

A common problem however is that if you have code-paths on exit that fail to stop all _non-daemon_ threads, the JVM process will fail to exit which can cause problems if you are relying on this functionality for graceful restarts or shutdown.

Let's observe a simple example.

```java
public class Main {
  public static void main(String[] args) {
    Thread thread = new Thread(() -> {
      try {
        while (true) {
          // Simulate some work with sleep
          System.out.println("Thread is running...");
          Thread.sleep(1000);
        }
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    });
    // Set the thread as non-daemon
    // although this is also set as it's inherited by main thread
    thread.setDaemon(false);
    thread.start();
    System.out.println("Leaving main thread");
  }
}
```

If we run this, although we exit the _main_ thread, we observe that the JVM does not exit and the thread continues to do it's "work".

```bash
> java Main
Leaving main thread
Thread is running...
Thread is running...
Thread is running...
```

Often you will see classes implement `Closeable` or `AutoCloseable` so that an orderly shutdown of these sort of resources can occur.
It would be great however to **test** that such graceful cleanup is done appropraitely for our codebases.

Is this possible in Bazel?

```java
@Test
public void testNonDaemonThread() {
    Thread thread = new Thread(() -> {
      try {
        while (true) {
          // Simulate some work with sleep
          System.out.println("Thread is running...");
          Thread.sleep(1000);
        }
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    });
    thread.setDaemon(false);
    thread.start();
}
```

If we run this test however we notice our tests **PASSES** 😱

```bash
> bazel test //:NonDaemonThreadTest -t-
INFO: Invocation ID: f0b0c42f-2113-4050-ab7e-53c67dfa7904
INFO: Analyzed target //:NonDaemonThreadTest (0 packages loaded, 4 targets configured).
INFO: Found 1 test target...
Target //:NonDaemonThreadTest up-to-date:
  bazel-bin/NonDaemonThreadTest
  bazel-bin/NonDaemonThreadTest.jar
INFO: Elapsed time: 0.915s, Critical Path: 0.40s
INFO: 2 processes: 6 action cache hit, 1 internal, 1 darwin-sandbox.
INFO: Build completed successfully, 2 total actions
//:NonDaemonThreadTest PASSED in 0.4s
```

Why?

Turns out that Bazel's JUnit test runner uses `System.exit` after running the tests, which according to the JVM specification allows the runtime to shutdown irrespective of active non-daemon threads. [[ref](https://github.com/bazelbuild/bazel/blob/82625ab63120ec6ceeabe3485db1d426f83c396d/src/java_tools/junitrunner/java/com/google/testing/junit/runner/BazelTestRunner.java#L104C4-L104C27)]

> * Some thread invokes the `exit()` method of `class Runtime` or `class System`, and the exit operation is not forbidden by the security manager.

From discussion with others in the community, this explicit shutdown was added specifically because many tests would hang due to improper non-daemon thread cleanup. 🤦

How can we validate graceful shutdown then?

Well, we can leverage `sh_test` and startup our `java_binary` and validate that the application exists within a specific timeout.

Additionally, I've put forward a pull-request [PR#26879](https://github.com/bazelbuild/bazel/pull/26879) which adds a new system property `bazel.test_runner.await_non_daemon_threads` that can be added to a `java_test` such that the test runner validates that there are no daemon-threads running before exiting.

> It would have been great to remove the `System.exit` call completely when the presence of the property is true; however I could not find a way to then set the exit value of the test.

Turns out that even simple things can be a little complicated and it was a bit of a headscratcher to see why our tests were passing to catch our failure to properly teardown.