---
layout: post
title: Linux cgroup from first principles
date: 2025-05-26 14:59 -0700
---

After having spent the better part of 2 weeks learning Linux's cgroup (control group) concept, I thought I better write this down for the next brave soul. 🦸

> Facebook's cgroup2 [microsite](https://facebookmicrosites.github.io/cgroup2/docs/overview.html) is also a fantastic resource. I highly recommend reading it 🤓. 

Let's dive in and learn _cgroup_, specifically _cgroup v2_.

There is a distinction between v2 and v1 implementation of cgroup.  However v2 was introduced in Linux kernel 4.5 in 2016. It included a much simpler design, so we will consider it the only version to simplify this guide [[ref]](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/diff/Documentation/cgroup-v2.txt?id=v4.5&id2=v4.4).

> As a quick aside, what I love about Linux is the Unix design philosophy _"everything is a file"_. This bleeds itself into everything in Linux especially on how to interface with various kernel subsystems.
> 
> While higher-level tools and libraries often abstract these direct file manipulations,
> If you can `read` and `write` to a file, you can communicate with the kernel! 📜

Linux control groups are a sort of container you can place processes within and apply a variety of limits on resources allocations such as: memory, cpu and network bandwidth.

We will be using the following NixOS VM to build and run this guide if you want to follow along.

<details markdown="1">
<summary markdown="span">vm.nix</summary>
    
```nix
let
  # release-24.11
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/archive/5ef6c425980847c78a80d759abc476e941a9bf42.tar.gz";
  nixos = import "${nixpkgs}/nixos" {
    configuration = {
      modulesPath,
      pkgs,
      ...
    }: {
      imports = [
        (modulesPath + "/virtualisation/qemu-vm.nix")
      ];

      virtualisation = {
        graphics = false;
      };

      users.users.alice = {
        isNormalUser = true;
        extraGroups = ["wheel"];
        packages = with pkgs; [
          file
          libcgroup
          vim
          (pkgs.runCommandCC "throttled"{
              src = pkgs.writeText "throttled.c" ''
              #include <stdio.h>
              #include <stdlib.h>
              #include <unistd.h>
              #include <time.h>

              static long long now_ns() {
                  struct timespec ts;
                  clock_gettime(CLOCK_MONOTONIC, &ts);
                  return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
              }

              int main() {
                  long long last = now_ns();
                  int count = 0;

                  while (1) {
                      count++;
                      if (count % 1000000 == 0) {
                          long long current = now_ns();
                          long long delta_ms = (current - last) / 1000000;
                          printf("Delta: %lld ms\n", delta_ms);
                          fflush(stdout);
                          last = current;
                      }
                  }
                  return 0;
              }
              '';
            } ''
              mkdir -p $out/bin
              $CC -o $out/bin/throttled $src
            '')
          (pkgs.runCommandCC "hog" {
              src = pkgs.writeText "hog.c" ''
                #include <stdlib.h>
                #include <stdio.h>
                #include <unistd.h>
                #include <string.h>

                int main() {
                    while (1) {
                        char *mem = malloc(1024 * 1024);
                        if (!mem) {
                            perror("malloc");
                            break;
                        }
                        memset(mem, 1, 1024 * 1024);
                        printf("1 MB allocated\n");
                        fflush(stdout);
                        sleep(1);
                    }
                    return 0;
                }
              '';
            } ''
              mkdir -p $out/bin
              $CC -o $out/bin/hog $src
            '')
        ];
        initialPassword = "";
      };
      security.sudo.wheelNeedsPassword = false;
      services.getty.autologinUser = "alice";

      system.stateVersion = "24.11";
    };
  };
in
  nixos.vm
```
</details>

Although a single `cgroup` can enforce multiple resource allocations, we will do so one at a time to simplify.

All `cgroup` live beneath the special directory `/sys/fs/cgroup` directory, which is referred to as the _root cgroup_.

You can inspect your login shells current cgroup by inspecting `/proc/self/cgroup`

The returned value is what should be appended to the root.

```bash
> cat /proc/self/cgroup
0::/user.slice/user-1000.slice/session-5.scope

> file /sys/fs/cgroup/user.slice/user-1000.slice/session-5.scope
/sys/fs/cgroup/user.slice/user-1000.slice/session-5.scope: directory
```

> If you are confused with the _slice_ and _scope_ stuff in the path just ignore that 🤔. That is a `systemd` concept to help organize cgroups.


Let's create a simple hierarchy we want for the purpose of learning. 

In practice you will probably have these groups created to model the business domain or the various processes you want to group together and not the controllers you want to express.

```
/sys/fs/cgroup
└── demo/
    ├── cpu-limited/
    ├── memory-limited/
    └── network-limited/
```

Since "everything is a file" is the mantra of our Linux API, let's just `mkdir` the groups.

```bash
sudo mkdir /sys/fs/cgroup/demo
sudo chown -R $USER /sys/fs/cgroup/demo
mkdir /sys/fs/cgroup/demo/cpu-limited
mkdir /sys/fs/cgroup/demo/memory-limited
mkdir /sys/fs/cgroup/demo/network-limited
```

If we look inside a single cgroup, we see a bunch of virtual files.

```bash
ls -1 /sys/fs/cgroup/demo | head
cgroup.controllers
cgroup.events
cgroup.freeze
cgroup.kill
cgroup.max.depth
cgroup.max.descendants
cgroup.subtree_control
...
memory.low
memory.max
memory.min
memory.numa_stat
memory.oom.group
memory.peak
...
network-limited
pids.current
pids.events
pids.max
pids.peak
```

Some of these files help set the value on the various controllers such as `memory.max` which sets the absolute aggregate maximum memory all processes either attached to this cgroup or any of its descendants can allocate.

Other files, give you live accounting information or events such as `memory.current` or `memory.events`.

All the files that begin with `cgroup` itself, help set up the cgroup and turn on/off the various controllers.

`cgroup.controllers`
: This file will list all the active controllers enabled on this cgroup.

`cgroup.subtree_control`
: This file lists the controllers that are enabled and available to the descendants.

Initially, our `cgroup.subtree_control` for `/sys/fs/cgroup/demo` is empty. This means if you looked at any of the child cgroup, i.e. `/sys/fs/cgroup/demo/cpu-limited`, it will be missing a bunch of files.

```bash
> cat /sys/fs/cgroup/demo/cgroup.subtree_control 
# empty
> cat /sys/fs/cgroup/demo/cpu-limited/cgroup.controllers 
# empty
```

Let's toggle on various controllers.

```bash
> echo "+memory +io +cpu" > /sys/fs/cgroup/demo/cgroup.subtree_control 

> cat /sys/fs/cgroup/demo/cgroup.subtree_control 
cpu io memory

> cat /sys/fs/cgroup/demo/cpu-limited/cgroup.controllers 
cpu io memory
```

We can change the cgroup for a process by writing its _pid_ to the `cgroup.procs` file.

```bash
> sleep infinity &
1055
> echo 1055 | sudo tee /sys/fs/cgroup/demo/memory-limited/cgroup.procs 
1055
>  ps -o cgroup 1055
CGROUP
0::/demo/memory-limited
```

Why did you have to use `sudo` even though before you did `chown` ? 🤔

When I first started `sleep`, it was in the same cgroup as my login shell. Processes are only allowed to move cgroups for other processes if they have write permission for a common ancestor between them. The only common ancestor between the two is `/sys/fs/cgroup` and our user does not have write permission for it.

Why didn't you write the _pid_ to `/sys/fs/cgroup/demo` instead of a child group?

There is a _"no internal process constraint"_ which states that a cgroup may either have child cgroups or process **but not both** (except for the root).

Let's write a small C program that endlessly eats memory.

<details markdown="1">
<summary markdown="span">hog.c</summary>
```c
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

int main() {
    while (1) {
        char *mem = malloc(1024 * 1024);
        if (!mem) {
            perror("malloc");
            break;
        }
        memset(mem, 1, 1024 * 1024);
        printf("1 MB allocated\n");
        fflush(stdout);
        sleep(1);
    }
    return 0;
}
```
</details>

> 😲 Our program has to be sure to `memset` to 1 rather than 0. I found that either the compiler or the kernel has optimizations for pages that are all 0 and that no new memory was ever actually allocated.

We will restrict processes within our `demo/memory-limited` group to 5MiB.

```bash
> echo "5242880" > /sys/fs/cgroup/demo/memory-limited/memory.max  

> cat /sys/fs/cgroup/demo/memory-limited/memory.max  
5242880
```

Now let's start `hog` in the cgroup. We will use the tool `cgexec` which takes care of spawning the process in the desired cgroup -- this avoids us having to write ourselves to the `cgroup.procs` file.

```bash
> sudo cgexec -g memory:demo/memory-limited hog
1 MB allocated
1 MB allocated
1 MB allocated
1 MB allocated
[  128.648590] Memory cgroup out of memory: Killed process 895 (hog)
total-vm:7716kB, anon-rss:4992kB, file-rss:1024kB,
shmem-rss:0kB, UID:0 pgtables:48kB oom_score_adj:0
Killed
```

We just applied our first resource constraint 😊.

Let's do one more interesting example. Let's restrict a program from running only 10% of the time on the CPU.

This can be really useful if you want to reproduce what the effects of an over-subscribed machine may be like.

Let's write a simple program that does some _busy work_ and prints out time deltas every 1000000 iterations.

<details markdown="1">
<summary markdown="span">throttled.c</summary>
```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>

static long long now_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

int main() {
    long long last = now_ns();
    int count = 0;

    while (1) {
        count++;
        if (count % 1000000 == 0) {
            long long current = now_ns();
            long long delta_ms = (current - last) / 1000000;
            printf("Delta: %lld ms\n", delta_ms);
            fflush(stdout);
            last = current;
        }
    }
    return 0;
}
```
</details>

If we were to run this program normally, we may see the following:

```bash
> throttled  | head
Delta: 0 ms
Delta: 1 ms
Delta: 0 ms
Delta: 0 ms
Delta: 0 ms
Delta: 1 ms
Delta: 0 ms
Delta: 1 ms
Delta: 0 ms
Delta: 0 ms
```

Now let's apply a CPU constraint saying that within 100ms (100000µs), processes within the cgroup may only use 1ms (1000µs) -- 1% CPU allocation.

```
> echo "1000 100000" > /sys/fs/cgroup/demo/cpu-limited/cpu.max

> cat /sys/fs/cgroup/demo/cpu-limited/cpu.max
1000 100000
```

Let's use `cgexec` again on our `throttled` program and observe the difference.

```bash
> sudo cgexec -g cpu:demo/cpu-limited throttled
Delta: 0 ms
Delta: 5 ms
Delta: 99 ms
Delta: 0 ms
Delta: 99 ms
Delta: 99 ms
Delta: 99 ms
Delta: 100 ms
Delta: 99 ms
Delta: 199 ms
Delta: 0 ms
```

Nice -- we now have a way to easily throttle tasks that may be unreasonably CPU hungry 😈.

Although we applied these constraints to single-processes, the same concept applies to multiple processes as well. The values set are for all descendants of the tree in a particular cgroup.

Control groups are an excellent way to provide an additional layer of isolation for a workload from the rest of the system and also serve as a great knob for performance benchmarking under pathological conditions.

While they seemed daunting at first, the elegance of the _"everything is a file"_ philosophy makes them surprisingly approachable once you start experimenting.

We also benefited from ignoring the complexity that systemd often adds on top — sometimes it's nice to just work with raw files and understand the fundamentals 🙃.

One improvement I'd love to see: when you hit an invalid condition — like violating the _"no internal process"_ constraint — you're left with a vague file I/O error (e.g. _Device or resource busy_). It would be amazing if the kernel could offer more actionable error messages or hints in `dmesg` 💡.