---
layout: post
title: bpf_helpers and you...
date: 2020-04-12 12:55 -0700
excerpt_separator: <!--more-->
---
> This is a republishing of a e-mail I sent out to *xdp-newbies* mailing list which you can find [here](https://www.spinics.net/lists/xdp-newbies/msg01422.html) originally published on Wed, 30 Oct 2019
 
This is my attempt of a continuation of David Miller's prior e-mail
[bpf.h and you...](https://www.spinics.net/lists/xdp-newbies/msg00179.html).

I was curious about how ebpf filters are wired and work. The heavy use of C
macros makes the source code difficult for me to comprehend.

> Maybe there's an online pre-processed version of the Linux kernel?

I'm hoping others may find this exploratory-dive insightful -- hopefully,
it's accurate enough.

<!--more-->

Let's write a very trivial ebpf filter `hello_world_kern.c` and have
it print "hello world"

```c
#include <linux/bpf.h>

#define __section(NAME) __attribute__((section(NAME), used))

static char _license[] __section("license") = "GPL";

/* helper functions called from eBPF programs written in C */
static int (*bpf_trace_printk)(const char *fmt, int fmt_size,
                            ...) = (void *)BPF_FUNC_trace_printk;

__section("hello_world") int hello_world_filter(struct __sk_buff *skb) {
    char msg[] = "hello world";
    bpf_debug_printk(msg, sizeof(msg));
    return 0;
}
```

If we compile the above using the below, we can inspect the LLVM IR.

```bash    
clang -c -o hello_world_kern.ll -x c -S -emit-llvm hello_world_kern.c
```

The few lines that stand out are:

```llvm
@bpf_trace_printk = internal global i32 (i8*, i32, ...)* inttoptr (i64 6 to i32 (i8*, i32, ...)*), align 8
....
%6 = load i32 (i8*, i32, ...)*, i32 (i8*, i32, ...)** @bpf_trace_printk, align 8
%7 = getelementptr inbounds [13 x i8], [13 x i8]* %3, i32 0, i32 0
%8 = call i32 (i8*, i32, ...) %6(i8* %7, i32 13)
```

The above demonstrates that the value of `BPF_FUNC_trace_printk` is
simply the integer `i64 6` and it is being cast to the function pointer (`i32 (i8*, i32, ...)*)`)

Sure enough, we can confirm that `bpf_trace_printk` is the 6th value
in the enumeration of known bpf bpf_helpers in [bpf.h](https://elixir.bootlin.com/linux/v5.3.7/source/include/uapi/linux/bpf.h#L2724)

```c
#define __BPF_FUNC_MAPPER(FN)       \
    FN(unspec),                     \
    FN(map_lookup_elem),            \
    FN(map_update_elem),            \
    FN(map_delete_elem),            \
    FN(probe_read),                 \
    FN(ktime_get_ns),               \
    FN(trace_printk),               \
```

We can go even further and take this LLVM IR and generate human-readable eBPF assembly using `llc`

    llc hello_world_kern.ll -march=bpf

Depending on the optimization level of the earlier `clang` call you
may see different results however using `-O3` we can see

    call 6

Great! So we know that the call to `bpf_trace_printk` gets translated
into a call instruction with an immediate value of 6.

How does it end up calling code within the kernel, though?
Once the Verifier verifies the bytecode it calls [fixup_bpf_calls](https://elixir.bootlin.com/linux/v5.3.8/source/kernel/bpf/verifier.c#L8869)
which goes through all the instructions and makes the necessary
adjustment to the immediate value

```c
fixup_bpf_calls(...) {
    ...
    patch_call_imm:
        fn = env->ops->get_func_proto(insn->imm, env->prog);
        /* all functions that have prototype and verifier allowed
        * programs to call them, must be real in-kernel functions
        */
        if (!fn->func) {
            verbose(env,
                "kernel subsystem misconfigured func %s#%d\n",
                func_id_name(insn->imm), insn->imm);
            return -EFAULT;
        }
        insn->imm = fn->func - __bpf_call_base;
```
N.B. I haven't deciphered how *__bpf_call_base* is used / works

The `get_func_proto` will return the function prototypes registered by
every subsystem, such as in [net/core/filter.c](https://elixir.bootlin.com/linux/v5.3.8/source/net/core/filter.c#L5991).
At this point in the method, it's a simple switch statement to get the
matching function prototype given the numeric value.

I'd love to see more on the code path of how the non-JIT vs JIT
instructions get handled.

For instance, for the net subsystem, I can see where the ebpf prog is [invoked](https://elixir.bootlin.com/linux/v5.3.8/source/net/core/filter.c#L119).
Still, it's challenging to work out how the choice of executing the
function directly (in the case of JIT) vs. running it through the
interpreter is handled.

eBPF is impressive, but the toolchain requires some technical depth of the Linux kernel. If you have similar posts of explaining eBPF from the ground up, [share it with me](mailto:farid.m.zakaria@gmail.com).