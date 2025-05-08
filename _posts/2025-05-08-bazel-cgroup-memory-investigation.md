---
layout: post
title: Bazel cgroup memory investigation
date: 2025-05-08 14:25 -0700
---

We had the case at _$DAYJOB$_, where our CI system would occassional bork 💀.

With some regression analysis we figured it was likely to a new test being added that likely had a memory leak and caused the overall system to go _out-of-memory_ (OOM).

While we sought to find the culprit, I wanted to explore whether `cgroup`, a Linux kernel feature that limits, accounts for, and isolates the resource usage of a collection of processes could help us cap the total memory Bazel tests accumulate.

> Looks like Bazel 8.0 has some new exciting specific `cgroup` features which I'd like to try!

First, let us start with a small reproducer that we will call `eat_memory`, whose role will simply be to continously allocate more memory.

<details>
    <summary>eat_memory.py</summary>
    
```python
import time
import sys

megabytes_to_allocate = 200  # Default, can be overridden by arg
if len(sys.argv) > 1:
    try:
        megabytes_to_allocate = int(sys.argv[1])
    except ValueError:
        print(f"Usage: python3 {sys.argv[0]} [megabytes_to_allocate]")
        sys.exit(1)

print(f"Attempting to allocate {megabytes_to_allocate} MB of memory gradually.")

data_chunks = []
chunk_size_mb = 1  # Allocate 1MB at a time
bytes_per_mb = 1024 * 1024
chunk_bytes = chunk_size_mb * bytes_per_mb

allocated_mb = 0

try:
    for i in range(megabytes_to_allocate // chunk_size_mb):
        # Allocate 1MB of memory (list of bytes, ensures it's "real" memory)
        data_chunks.append(b' ' * chunk_bytes)
        allocated_mb += chunk_size_mb
        print(f"Allocated: {allocated_mb} MB / {megabytes_to_allocate} MB", flush=True)
        time.sleep(0.1)
    print(f"Successfully allocated all {megabytes_to_allocate} MB.")
except MemoryError:
    print(f"MemoryError: Could not allocate more memory. Allocated approx {allocated_mb} MB.")
    sys.exit(1)
except Exception as e:
    print(f"An unexpected error occurred: {e}")
    sys.exit(1)

# Optional:
# print("Holding memory. Press Ctrl+C to exit or wait for OOM killer.")
# try:
#     while True:
#         time.sleep(1)
# except KeyboardInterrupt:
#     print("Exiting due to Ctrl+C.")
```
    
</details>

Turns out the creation of `cgroup` and the settings of it can be easily accomplished with `systemd-run` that is installed on any distrition (most) with `systemd`.

We take special care to set `MemoryMax` and `MemorySwapMax` as on my machine as I
have swap enabled.

```console
> systemd-run --user --scope -p MemoryMax=10M \
              -p MemorySwapMax=0M -- python eat_memory.py
Running as unit: run-rfac85b068fee45479a4aae220ae02d24.scope; invocation ID: ea099d98584a4e0c979c96e265e3cd06
Attempting to allocate 200 MB of memory gradually.
Allocated: 1 MB / 200 MB
Allocated: 2 MB / 200 MB
Allocated: 3 MB / 200 MB
Allocated: 4 MB / 200 MB
Allocated: 5 MB / 200 MB
Allocated: 6 MB / 200 MB
fish: Job 1, 'systemd-run --user --scope -p M…' terminated by signal SIGKILL (Forced quit)
```

The reproducer dies at 6MB because the Python interpreter itself consumed 4MB.

We now want to apply this to bazel!

Let's create a simple Bazel project.

<details>
    <summary>BUILD.bazel</summary>

```python
py_binary(
    name = "eat_memory",
    srcs = ["eat_memory.py"],
)

sh_test(
    name = "eat_memory_test",
    srcs = ["eat_memory_test.sh"],
    data = [":eat_memory"],
    tags = ["no-cache"]
)
```
</details>

<details>
    <summary>eat_memory_test.sh</summary>

```bash
#!/bin/bash

echo "Running eat_memory test..."

# Locate the eat_memory binary provided as a data file
EAT_MEMORY_BINARY=$(dirname "$0")/eat_memory

# Check if the binary exists
if [[ ! -x "$EAT_MEMORY_BINARY" ]]; then
    echo "Error: eat_memory binary not found or not executable"
    exit 1
fi

$EAT_MEMORY_BINARY
EXIT_CODE=$?

# Validate the output and exit code
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "Test failed: eat_memory exited with code $EXIT_CODE"
    echo "Output: $OUTPUT"
    exit 1
fi

echo "Test passed: eat_memory ran successfully"
exit 0
```
</details>

If we `bazel run` the command with `systemd-run` things work as expected.

```console
> systemd-run --user --scope -p MemoryMax=10M \
            -p MemorySwapMax=0M -- bazel run //:eat_memory
Running as unit: run-r351ccd338626452181cbe63b78287bbe.scope; invocation ID: 16c6551b89924a7c8182bf2d217253c0
INFO: Analyzed target //:eat_memory (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
Target //:eat_memory up-to-date:
  bazel-bin/eat_memory
INFO: Elapsed time: 0.058s, Critical Path: 0.00s
INFO: 1 process: 1 internal.
INFO: Build completed successfully, 1 total action
INFO: Running command line: bazel-bin/eat_memory
Attempting to allocate 1024 MB of memory gradually.
Allocated: 1 MB / 1024 MB
Allocated: 2 MB / 1024 MB
Allocated: 3 MB / 1024 MB
Allocated: 4 MB / 1024 MB
Allocated: 5 MB / 1024 MB
fish: Job 1, 'systemd-run --user --scope -p M…' terminated by signal SIGKILL (Forced quit)
```

If I do `bazel test` however things don't seem to work.

```console
systemd-run --user --scope -p MemoryMax=10M \
            -p MemorySwapMax=0M -- \
            bazel test //... \
            --cache_test_results=no \
            --test_output=streamed
Running as unit: run-r5b91c5d734b3415faa754ae982e3f621.scope; invocation ID: 051f6836ee1a4e038ce997249050711c
WARNING: Streamed test output requested. All tests will be run locally, without sharding, one at a time
INFO: Analyzed 2 targets (0 packages loaded, 4 targets configured).
Running eat_memory test...
Attempting to allocate 1024 MB of memory gradually.
Allocated: 1 MB / 1024 MB
Allocated: 2 MB / 1024 MB
Allocated: 3 MB / 1024 MB
Allocated: 4 MB / 1024 MB
Allocated: 5 MB / 1024 MB
Allocated: 6 MB / 1024 MB
Allocated: 7 MB / 1024 MB
Allocated: 8 MB / 1024 MB
Allocated: 9 MB / 1024 MB
Allocated: 10 MB / 1024 MB
Allocated: 11 MB / 1024 MB
Allocated: 12 MB / 1024 MB
Allocated: 13 MB / 1024 MB
Allocated: 14 MB / 1024 MB
...
```

Of course, there is a `bazel` server that is started previously that is not bound to the `cgroup` limit 🤦.

We will have to invoke `bazel shutdown` and be sure to provide a `MemoryMax` that is large enough to include the server which for my machine is roughly 500MiB.

```console
> bazel shutdown

> systemd-run --user --scope \
    -p MemoryMax=510M -p MemorySwapMax=0M -- \
    bazel test //... \
    --cache_test_results=no \
    --test_output=streamed
Running as unit: run-r1c56d335301e45049e32c7c44f571a1c.scope; invocation ID: 2a6806e72e7d4aa9b246976d3a808915
Starting local Bazel server and connecting to it...
WARNING: Streamed test output requested. All tests will be run locally, without sharding, one at a time
INFO: Analyzed 2 targets (90 packages loaded, 905 targets configured).
Running eat_memory test...
Attempting to allocate 1024 MB of memory gradually.
Allocated: 10 MB / 1024 MB
Allocated: 20 MB / 1024 MB
[10 / 11] Testing //:eat_memory_test; 0s linux-sandbox

Bazel caught terminate signal; cancelling pending invocation.

Could not interrupt server: (14) Connection reset by peer

Server terminated abruptly (error code: 14, error message: 'Connection reset by peer', log file: '...')
```

Great! This now properly kills everything including the server. ✊

That may seem pretty draconian but we've found that relying on Linux's OOM killer to be not effective and having the CI machines get to an inoperable state leads them to suddenly cycle.