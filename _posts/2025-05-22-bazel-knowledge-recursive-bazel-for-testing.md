---
layout: post
title: 'Bazel Knowledge: Recursive Bazel for testing'
date: 2025-05-22 14:32 -0700
---

Bazel’s sandboxing is a powerful way to isolate builds and enforce resource usage via the use of cgroups. One key feature is limiting memory per action via `--experimental_sandbox_memory_limit_mb`. However, configuring this correctly across machines and CI environments is tricky, and even worse, if Bazel silently fails to enable it, your limits simply don’t apply.

> I consider this silent failure to be a bug, especially if any limits have been explicitly expressed, and have opened [issue#26062](https://github.com/bazelbuild/bazel/issues/26062).

I have a few previous posts where I explored how to [enable groups for Bazel]({% post_url 2025-05-08-bazel-cgroup-memory-investigation %}) for the purpose of enforcing memory limits at my _$DAYJOB$_. After I got to the point of having my own manual validation of the flag working, I wanted to prove that
it continues to work and we don't introduce a regression. 🤔

Normally, we catch regressions with tests. But things get a little more hazy when you're trying to test the foundational layer that runs all your code.

Nevertheless, turns out we can employ a test! We will run `bazel` inside of `bazel` 🤯.

Turns out that the [Bazel codebase](https://github.com/bazelbuild/bazel) already runs `bazel` recursively in test targets and there is even a ruleset, [rules_bazel_integration_test](https://github.com/bazel-contrib/rules_bazel_integration_test), that offers a lot of scaffolding to test multiple Bazel versions.

I always opt for the _simplest_ solution first and decided to write a minimal `sh_test` that provided our memory limits without relying on `@rules_bazel_integration_test` which adds scaffolding for multi-version testing, but felt heavyweight for this focused validation 🤓.

Let's first build our failing binary! We will build a Java program that will endlessly consume memory.

```java
public class EatMemory {
  private static final int ONE_MIB = 1024 * 1024;
  private static final int MAX_MIB = 100;

  public static void main(String[] args) {
    byte[][] blocks = new byte[MAX_MIB][];
    int i;

    for (i = 0; i < MAX_MIB; ++i) {
      blocks[i] = new byte[ONE_MIB];
      // Touch the memory to ensure it's actually allocated
      for (int j = 0; j < ONE_MIB; ++j) {
        blocks[i][j] = (byte) 0xAA;
      }
      System.out.printf("Allocated and touched %d MiB%n", i + 1);
      System.out.flush();
    }

    System.out.printf("Successfully allocated and touched %d MiB. Exiting.%n", MAX_MIB);
  }
}
```

We will now create a simple `sh_test` that will run `bazel`. We will give it the `EatMemory.java` file and it will setup a _very minimal_ Bazel workspace.

The test will create a simple `MODULE.bazel` file in a temporary directory and copy over our Java file.

```bash
#!/usr/bin/env bash

# Remove the default runfile
# setup stuff for brevity...

mkdir -p "${TEST_TMPDIR}/workspace/java/"

cp "$(rlocation __main__/java/EatMemory.java)" \
   "${TEST_TMPDIR}/workspace/java/EatMemory.java"

cd "${TEST_TMPDIR}/workspace"

cat > java/BUILD.bazel <<'EOF'
# This target is only run within the memory_limit_test.sh script
java_test(
  name = "EatMemory",
  srcs = ["EatMemory.java"],
  tags = [
    "manual",
    "no-cache",
    "no-remote",
  ],
  use_testrunner = False,
)
EOF

cat > MODULE.bazel <<'EOF'
bazel_dep(name = "rules_java", version = "8.11.0")
EOF

# we want to make sure we don't immediately fail if the test fails
# since this is a negative test.
set +e

# this should fail
if bazel --output_user_root="${TEST_TMPDIR}/root" \
      test //java:EatMemory \
      --announce_rc \
      --experimental_sandbox_memory_limit_mb=20 \
      --sandbox_tmpfs_path=/tmp \
      --sandbox_add_mount_pair="${TEST_TMPDIR}/root" \
      --flaky_test_attempts=1 \
      --test_output=streamed
then
  echo "Test unexpectedly succeeded. Are the cgroup limits set correctly?"
  exit 1
fi
```

The important flag I'm seeking to test is `--experimental_sandbox_memory_limit_mb=20` where I set the maximum memory that can be used by actions as 20MiB.

Since I'm running a target that will consume up to 100MiB, this test **expects bazel to fail** and if it succeeds, the test will fail.

We now do the last finishing touch of writing our `BUILD.bazel` file with our `sh_test`. In order to help the test find `bazel` we add our `$PATH` to the `env_inherit` flag. Normally this is not considered best practice as it ruins the hermiticity of the test, but in this case we don't mind if the test re-runs. 😎

```python
java_binary(
    name = "EatMemory",
    srcs = ["EatMemory.java"],
)

sh_test(
    name = "memory_limit_test",
    srcs = ["memory_limit_test.sh"],
    data = [
        ":EatMemory.java",
        "@bazel_tools//tools/bash/runfiles",
    ],
    env_inherit = ["PATH"],
    tags = [
        "external",
        "no-cache",
        "no-remote",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
    ],
)
```

We make sure to restrict the test to only the Linux platform, since Windows and MacOS do not have cgroup support.

One final gotcha, is to _remember to disable any form of caching_ 👌 !

We are trying to validate assumptions about the state of a system unbenownst to Bazel and therefore as it is not modeled in Bazel's action graph, we cannot safely cache the test. Make sure no-cache and no-remote are applied.

We can now rest assured that when we apply `experimental_sandbox_memory_limit_mb` to our comprehensive test suite, Bazel will continue to respect them.