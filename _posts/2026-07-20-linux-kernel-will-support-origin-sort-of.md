---
layout: post
title: Linux kernel will support $ORIGIN, sort of
date: 2026-07-20 19:00 -0700
---

For some reason, during [TacoSprint 2026](https://tacosprint.org) I decided to see if we could tackle [relocatable binaries]({% post_url 2026-06-21-nix-needs-relocatable-binaries %}) in Nix.

I enjoy these lofty goals to push Nix and the surrounding ecosystem forward. I am _bold if not stupid_.

I left the last earlier post with one potential idea of how to get there:

> We could patch the Linux kernel so that $ORIGIN is supported in PT_INTERP and the shebang.

I waded through the complexity of sending patches over email (turns out I actually enjoy this workflow!), and sent a proposal to the Linux kernel mailing list.

My first attempt [here](https://lore.kernel.org/all/20260622043934.179879-1-farid.m.zakaria@gmail.com/) proposed simply adding direct support for `$ORIGIN` in the Virtual File System (VFS) subsystem.

I waited nervously. I was expecting the result from what I had come to read about online; someone non-politely telling me to _F$#CK OFF_ because there is something I missed, misunderstood or did not consider. 🤬

The result was completely different. 😲

[Christian Brauner](https://brauner.io/), the maintainer for VFS responded to me in good faith, asking for the rationale for the change and eventually proposing some ways in which such a support could make it into the subsystem.

> **Note**
> It definitely helped having someone like [John Ericson](https://github.com/ericson2314) [chime in](https://lore.kernel.org/all/24420045-a6eb-4999-ab19-1e344eaba8a4@app.fastmail.com/) and advocate why having a non-fixed interpreter (`PT_INTERP`) is useful to Nix and other use-cases (i.e. Buck & Bazel).
{: .alert .alert-note }

He offered that potentially we could leverage [eBPF](https://ebpf.io/) as a programmable way to select an interpreter through [binfmt_misc](https://docs.kernel.org/admin-guide/binfmt-misc.html).

Whoa! 🤯

I wanted to merely allow `$ORIGIN` but a programmable selection could let us do anything!

The idea must have really intrigued him because soon-after, _on his vacation_, Christian offered the first draft of such a solution. We went back and forth a little over the mailing list and the end result is a [patch series](https://lore.kernel.org/linux-fsdevel/20260716-wacholderbeere-zahlt-beraten-e872c3a4f59b@brauner/T/#ma8bbf0640f3154d76e1fd4607c61507b72609c6a) that will make its way into `-next` branch in the near future.

If you don't know what eBPF is or `binfmt_misc`, WTF did we just collaborate on?

Let's take a look!

I won't do eBPF justice, and there are plenty of articles online about it as it's quite _in-vogue_ at the moment.

**tl;dr;** You can write programs in a C subset that gets compiled to an instruction set whose virtual machine is running **within the kernel**. Shouldn't the kernel be super fast? Yes, the programs are jitted to their native CPU architecture and the programs have a fixed-time slice. Isn't this some crazy vulnerability for the kernel? Before any code is loaded it is "verified" to be safe. Checkout [this guide](https://ebpf.io/what-is-ebpf/) for more info.

We can now support `$ORIGIN` with a relatively simple eBPF program:

```c
SEC("struct_ops.s/match")
bool BPF_PROG(nix_match, struct linux_binprm *bprm)
{
  return !bpf_strncmp(bprm->buf, 4, "\x7f" "ELF");
}

SEC("struct_ops.s/load")
int BPF_PROG(nix_load, struct linux_binprm *bprm)
{
  char path[256];
  long n;

  n = bpf_path_d_path(&bprm->file->f_path, path, sizeof(path));
  if (n < 0)
    return n;

  /* derive the loader location from the binary's path */

  return bpf_binprm_set_interp(bprm, path, sizeof(path));
}

SEC(".struct_ops.link")
struct binfmt_misc_ops nix = {
  .match = (void *)nix_match,
  .load = (void *)nix_load,
  .name = "nix",
};
```

Once the above program is loaded and registered into the kernel, we then ask the `binfmt_misc` subsystem to trigger it. Checkout [this thread](https://lore.kernel.org/linux-fsdevel/20260711-binfmt-misc-bpf-v2-v2-5-d6591ceaf207@gmail.com/) if you want to see the complete example.

```bash
> bpftool struct_ops register nix_origin.bpf.o /sys/fs/bpf
> echo ':origin:B::::nix:' > /proc/sys/fs/binfmt_misc/register
```

What does that mean?

It means that every binary now triggers the `nix_match` function above, in this case any `ELF` file, but it could be executables with a new segment like `PT_INTERP_NIX`, and the kernel will ask `nix_load` to determine the interpreter to use dynamically.

Our special BPF program has support for `$ORIGIN` 💥

What else could you do?

Well we can now even completely replace the traditional QEMU `binfmt_misc` [registration script](https://github.com/qemu/qemu/blob/master/scripts/qemu-binfmt-conf.sh) with a BPF program now like [this one](https://gist.github.com/fzakaria/bef27d2e21b0e36ffccda1cbf417b636).

What else can we do?

Since we can now programmatically select our interpreter **based on anything** in the file, we can do quite a lot. I'm keen to hear your suggestions and ideas 💡.

Some of the smaller items are that we can even support `$ORIGIN` in the shebangs (`#!$ORIGIN/bin/ld.so`) very easily as [seen here](https://gist.github.com/fzakaria/2e1e1c44fa488a951674f8761c672366): we simply look at the first 256 bytes of the file and look for `$ORIGIN` to trigger.

One downside or _side-effect_ of the traditional `binfmt_misc` hand-off was that the way in which the desired final binary was invoked was _non-transparent_.

The registered interpreter **becomes** the process. It owns the entire process identity, and the binary you actually asked to run gets demoted to an argument. For `wine` or `qemu` that's acceptable as they are emulators  but for a per-binary BPF loader that might pick a traditional `ld.so` it does not make much sense. 

This leaks in a few painful ways but the simplest are :

- `argv[0]` and `/proc/<pid>/cmdline` show the _interpreter_ invocation, not what you executed.
- `/proc/self/exe` names the interpreter. Relocatable programs commonly locate _themselves_ through `/proc/self/exe`, and instead they find the dynamic linker. 😩

Christian sent a large patch series for this as well. His latest [patch series](https://lore.kernel.org/linux-fsdevel/20260720-work-bpf-binfmt_misc-ptinterp-v1-0-ddb76c9a508e@kernel.org/T/#m5c7c7cbf4e19d2f045a69f5a1284220d6c35d88c) adds **two** new dispatch modes that close the gap from opposite ends and covers a few other _gotchas_ that these modes can fix.

The **loader substitition** `L` is the one I'm most excited about for Nix.

With the `L` flag, the kernel executes the matched binary **natively** as the main image, and merely substitutes the registered interpreter for the loader named in the binary's `PT_INTERP`. `binfmt_misc` stops being a hand-off and becomes a plain `PT_INTERP` override. There's no contract and no identity to reconstruct, so a **stock dynamic loader works unchanged**.

Where does this leaves us?


I'll be tracking the Linux kernel releases and, once this lands in `-next` and ships in a tagged release, I plan to upstream a **NixOS module** that registers the `$ORIGIN` support at boot. 🎉

The plan is to gate it on a new `PT_INTERP_NIX` segment rather than matching every `ELF` file. That keeps things **backwards compatible**: the BPF handler only kicks in for binaries that explicitly opt-in by carrying the new segment. This means Nix produced binaries continue to work without the BFP handler but those that have it may elevate themselves to _relocatable status_.

> A ship in harbor is safe, but that is not what ships are built for.
>  — John A. Shedd
