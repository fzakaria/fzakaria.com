---
layout: post
title: 'Bazel Knowledge: Diagnostic messages only on failure'
date: 2025-06-10 15:42 -0700
---

I have been writing quite a few Bazel rules recently, and I've been frustrated with the fact that `STDOUT` and `STDERR`
are emitted always for rules that are run even when the actions are successful. 😩

I like to audit our build logs for warnings and spurious noise. A happy build should ideally be a quiet build. 🤫

The inability of [ctx.actions.run](https://bazel.build/rules/lib/builtins/actions#run) or [ctx.actions.run_shell](https://bazel.build/rules/lib/builtins/actions#run_shell) to suppress output on successful builds is a longstanding gap that seems to have been re-implemented by _many_ independent codebases and rules such as in [rules_js#js_binary](https://github.com/aspect-build/rules_js/blob/157f7553543036a72a318ec6147b11f8f09abd88/js/private/js_binary.sh.tpl#L22).

> There has been a longstanding feature request to also support automatically capturing output for `ctx.actions.run` without having
> to resort to `ctx.actions.run_shell` needlessly [#5511](https://github.com/bazelbuild/bazel/issues/5511).

Do want to join the cabal of _quiet builds_? 🧘‍♂️ 

Here is the simplest way to achieve that!

Let's write our simple _wrapper_ that will invoke any program but capture the output.

```bash
#!/usr/bin/env bash
set -o pipefail -o nounset

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <stdout-file> <stderr-file> <command> [args...]" >&2
  exit 1
fi

STDOUT_FILE="$1"
STDERR_FILE="$2"
shift 2

"$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
STATUS=$?
 
if [ "$STATUS" -ne 0 ]; then
  echo "--- Command Failed ---" >&2
  echo "Status: $STATUS" >&2
  echo "Command: $*" >&2
  echo "--- STDOUT ---" >&2
  cat "$STDOUT_FILE" >&2
  echo "--- STDERR ---" >&2
  cat "$STDERR_FILE" >&2
  echo "--- End of Output ---" >&2
  exit "$STATUS"
fi
```

We will create a simple `sh_binary` to wrap this script. _Nothing fancy_.

```python
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

sh_binary(
    name = "quiet_runner",
    srcs = ["quiet_runner.sh"],
    visibility = ["//visibility:public"],
)
```

Now, when it's time to leverage this rule, we make sure to provide it as the
`executable` for `ctx.actions.run`.

I also like to provide the `STDOUT` & `STDERR` as an _output group_ so they can easily
be queried and investigated even on successful builds.

Let's write a simple rule to demonstrate.

Let's start off with our _tool_ we want to leverage in our rule.
This tool simply emits _"hello world"_ to `STDOUT`, `STDERR` and a provided file.

```java
import java.io.FileWriter;
import java.io.IOException;

public class HelloWorld {
  public static void main(String[] args) {
    if (args.length < 1) {
      System.err.println("Please provide a filename as the first argument.");
      return;
    }
    String filename = args[0];
    String message = "hello world";
    System.out.println(message);
    System.err.println(message);
    try (FileWriter writer = new FileWriter(filename, true)) {
      writer.write(message + System.lineSeparator());
    } catch (IOException e) {
      System.err.println("Failed to write to file: " + e.getMessage());
    }
  }
}
```

We now write our rule to leverage the tool.

The _important_ parts to notice are:

* We must provide the actual tool we want to run (i.e. `HelloWorld`) as a tool in `tools` so it is present as a runfile.
* We include the `stdout` and `stderr` as an `OutputGroupInfo`.
* Our `executable` is our _quiet runner_ that we created earlier.

```python
def _hello_world_impl(ctx):
    output = ctx.actions.declare_file("{}.txt".format(ctx.label.name))
    stdout = ctx.actions.declare_file("{}.out.log".format(ctx.label.name))
    stderr = ctx.actions.declare_file("{}.err.log".format(ctx.label.name))

    ctx.actions.run(
        outputs = [output, stdout, stderr],
        executable = ctx.executable._runner,
        arguments = [
            stdout.path,
            stderr.path,
            ctx.executable._binary.path,
            output.path,
        ],
        tools = [
            ctx.executable._binary,
        ],
    )

    return [
        DefaultInfo(files = depset(direct = [output])),
        OutputGroupInfo(
            output = depset([stderr, stdout]),
        ),
    ]

hello_world = rule(
    implementation = _hello_world_impl,
    attrs = {
        "_binary": attr.label(
            default = Label("//:HelloWorld"),
            executable = True,
            cfg = "exec",
        ),
        "_runner": attr.label(
            default = Label("//:quiet_runner"),
            executable = True,
            cfg = "exec",
        ),
    },
)
```

When we have a **successful** build, it is quiet. 😌

```bash
> bazel build //:hello_world
INFO: Invocation ID: 114e65ff-a263-4dcd-9b4f-de6cef10d36a
INFO: Analyzed target //:hello_world (1 packages loaded, 5 targets configured).
INFO: Found 1 target...
Target //:hello_world up-to-date:
  bazel-bin/hello_world.txt
```

If I were to induce a failure in our tool, by having it return `System.exit(-1)` we can see the logs now include
the relevant information.

```bash
> bazel build //:hello_world
INFO: Invocation ID: fb1170c9-7f38-4269-9d60-7d03155837c2
INFO: Analyzed target //:hello_world (0 packages loaded, 0 targets configured).
ERROR: BUILD.bazel:15:12: Action hello_world.txt failed: (Exit 255): quiet_runner failed: error executing Action command (from target //:hello_world) bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/quiet_runner bazel-out/darwin_arm64-fastbuild/bin/hello_world.out.log ... (remaining 3 arguments skipped)

Use --sandbox_debug to see verbose messages from the sandbox and retain the sandbox build root for debugging
--- Command Failed ---
Status: 255
Command: bazel-out/darwin_arm64-opt-exec-ST-d57f47055a04/bin/HelloWorld bazel-out/darwin_arm64-fastbuild/bin/hello_world.txt
--- STDOUT ---
hello world
--- STDERR ---
hello world
--- End of Output ---
Target //:hello_world failed to build
Use --verbose_failures to see the command lines of failed build steps.
INFO: Elapsed time: 0.459s, Critical Path: 0.15s
INFO: 2 processes: 2 action cache hit, 2 internal.
ERROR: Build did NOT complete successfully
```

Finally, we can use `--output_groups` to get access to the output on successful builds.

```bash
> bazel build //:hello_world --output_groups=output
INFO: Invocation ID: f2341485-42f3-4117-aced-bfdd87ef60ca
INFO: Analyzed target //:hello_world (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //:hello_world up-to-date:
  bazel-bin/hello_world.err.log
  bazel-bin/hello_world.out.log
INFO: Elapsed time: 0.369s, Critical Path: 0.08s
INFO: 3 processes: 1 disk cache hit, 1 internal, 1 darwin-sandbox.
INFO: Build completed successfully, 3 total actions
```

This allows us to access `bazel-bin/hello_world.out.log`, for instance, so we can see the output quite nicely! 💪

It's a bit annoying we have to all keep rebuilding this infrastructure ourselves but hopefully this _demystifies_ it for you and you can enter _build nirvana_ with me.