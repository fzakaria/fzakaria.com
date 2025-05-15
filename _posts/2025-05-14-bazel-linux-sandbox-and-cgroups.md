---
layout: post
title: Bazel linux-sandbox and cgroups
date: 2025-05-14 20:13 -0700
---

This is a follow up from the previous post [bazel cgroup]({% post_url 2025-05-08-bazel-cgroup-memory-investigation %}).

Turns out that at _$DAYJOB$_ we were not even using `linux-sandbox` like we thought we were! 🤦

Our builds were happily printing out `processwrapper-sandbox` even thought the builds were on Linux.

How come? 🤔

Well it's not so obvious on why a particular sandbox strategy is not available. Bazel does not make any logs
easily available for debug.

Turns out though we can easily run the `linux-sandbox` itself and get some more diagnostic information.

We will use the `linux-sandbox` tool to run `/bin/true` which is what Bazel itself does to validate that
the tool is functioning correctly [ref](https://cs.opensource.google/bazel/bazel/+/master:src/main/java/com/google/devtools/build/lib/sandbox/LinuxSandboxedSpawnRunner.java;l=99;drc=edd51a86c111407a6ca8ad079ca7cdb92dbfb0c3).


```console
> $(bazel info install_base)/linux-sandbox /bin/true

src/main/tools/linux-sandbox-pid1.cc:180: "mount": Permission denied
```

Uh no 😫 -- what does that permission denied for "mount" mean ?

Well the `linux-sandbox` is creating various _mounts_ within a user namespace to setup
the sandbox.

Once again, not much logs from the tool itself to use to debug.
Turns out that if you run `dmesg`, we see the culprit.

```
[Tue May 13 21:50:22 2025] audit: type=1400 audit(1747173023.407:128):
  apparmor="DENIED" operation="capable" class="cap" profile="unprivileged_userns"
  pid=3763 comm="unshare" capability=21  capname="sys_admin"
```

Looks like _AppArmor_ is specifically denying the mount within the user namespace.

Why?

Looks like a **breaking change** occurred in Ubuntu 24 where a new AppArmor profile was included that
restricted unprivileged user namespaces [ref](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces).

Well for now, let's just _disable_ all AppArmor checks and make them "complaints" 🤫

```bash
sudo aa-complain /etc/apparmor.d/*
```

Now that we know that `linux-sandbox` will work, let's setup our `cgroups` so that they can be used by Bazel.

We will create a root group `/example` and we will enable the _memory_ controller for it. Additionally, we create a child group
`/example/child` that will own the Bazel process.

The last step is moving our current process into the cgroup so that subsequent `bazel` invocations start
in that cgroup itself.

```bash
sudo mkdir /sys/fs/cgroup/example
sudo chown $USER -R /sys/fs/cgroup/example
cat /sys/fs/cgroup/example/cgroup.controllers
echo "+memory" | sudo tee /sys/fs/cgroup/example/cgroup.subtree_control
sudo mkdir /sys/fs/cgroup/example/child
sudo chown $USER -R /sys/fs/cgroup/example/child
echo $$ | sudo tee /sys/fs/cgroup/example/child/cgroup.procs
```

Now we are ready to try `--experimental_cgroup_parent` flag for `bazel`.

We would however like to validate that this all works, so for that we will write a very simple `genrule`.

The goal of the genrule is to write out the info to a file `bazel-bin/cgroup_output.txt` that we can use
to validate things are as we expect.

```python
genrule(
    name = "check_cgroup",
    outs = ["cgroup_output.txt"],
    cmd = """
        echo "==== /proc/self/cgroup ====" > $@
        cat /proc/self/cgroup >> $@
        echo "" >> $@
        echo "==== Cgroup memory.max for each cgroup in /proc/self/cgroup ====" >> $@
        while IFS= read -r line; do
            IFS=: read -r _ _ cgroup_path <<< "$$line"
            if [ -f "/sys/fs/cgroup$${cgroup_path}/memory.max" ]; then
                echo "$${cgroup_path}: $$(cat /sys/fs/cgroup$${cgroup_path}/memory.max)" >> $@
            else
                echo "$${cgroup_path}: memory.max not available" >> $@
            fi
        done < /proc/self/cgroup
        echo "" >> $@
    """
)
```

Now let's run it!

```bash
$ bazel --experimental_cgroup_parent=/example/test build \
   //:check_cgroup \
   --experimental_sandbox_memory_limit_mb=20

$ cat bazel-bin/cgroup_output.txt
==== /proc/self/cgroup ====
0::/example/blaze_8239_spawns.slice/sandbox_7.scope

==== Cgroup memory.max for each cgroup in /proc/self/cgroup ====
/example/blaze_8239_spawns.slice/sandbox_7.scope: 20971520
```

Great! Everything looks like it works.

Our task was correctly placed within `/example` cgroup and I can even see
that the `memory.max` valuef or the cgrou was set to 20MiB.

We can now go back to our original demonstrate of `eat_memory.py` from earlier and avoid having
to use `systemd-run` itself to limit memory but instead rely on `bazel` cgroup integration. 🔥
