---
layout: post
title: Making RUNPATH redundant for Nix
date: 2022-09-12 16:22 +0000
excerpt_separator: <!--more-->
---

> This post is a direct translation of Harmen Stoppel's [blog](https://stoppels.ch/2022/08/04/stop-searching-for-shared-libraries.html) on the same subject for Nix. He has also contributed a fix to [Spack](http://spack.io/).
>
> Please check out [https://github.com/fzakaria/nix-harden-needed](https://github.com/fzakaria/nix-harden-needed) for my solution for the Nix ecosystem.

Nix and other store-like systems (i.e. Guix or Spack), resolve all their dependencies within their store (_/nix/store_) to enforce hermiticity. They leverage for the most part _RUNPATH_ which is a field on the ELF executable to instruct the
dynamic linker where to discover the libraries -- as opposed to searching default search paths like _/lib_.

```console
❯ which ruby
/nix/store/8k4sgk3bmxnj0jvcgc4wvyd8ilg0ww3y-ruby-2.7.6/bin/ruby

❯ patchelf --print-rpath $(which ruby)
/nix/store/8k4sgk3bmxnj0jvcgc4wvyd8ilg0ww3y-ruby-2.7.6/lib:/nix/store/r90cncsaa519pwqpijg7ii4rkcmwjn6h-zlib-1.2.12/lib:/nix/store/bvy2z17rzlvkx2sj7fy99ajm853yv898-glibc-2.34-210/lib
```

I have a paper about to published for [SuperComputing 2022](https://sc22.supercomputing.org/) (please reach out if you'd like early copy) that demonstrates there is a non-trivial cost to continuously searching needlessly through
the _RUNPATH_. In fact, I have [written previously]({% post_url 2022-03-14-shrinkwrap-taming-dynamic-shared-objects %}) about the specific costs and our tool [Shrinkwrap](https://github.com/fzakaria/shrinkwrap) that can avoid it.

Although Shrinkwrap is one approach for a solution, it is merely a bandaid over the existing problem.


Can systems like Nix do more to solve this problem?
<!--more-->

Nix and similar systems have the benefit of knowing ahead of time the exact path for every dependency. They are also particularly well positioned to make deep impactful changes because they rebuild the world __bottom up__, starting from libc.


Although these systems are radical departures from traditional Linux distributions and try to rebel against the Filesystem Hierachy Standard, they nevertheless rely on fundamental tooling and control knobs such as _RUNPATH_ to bandaid over the solution.

🧐 Let's make the use of _RUNPATH_ in Nix obsolete and unnecessary.


We can do this through the observation that GCC will propagate the _soname_ stored in the library into the _DT_NEEDED_ entry of the upstream binary. That means that if our _soname_ happens to be an absolute path, such as a _/nix/store_ entry, it will get set for the _DT_NEEDED_ and searching through _RUNPATH_ will be unnecessary. 🎆

Here is a small example to demonstrate
```
# Let's build our library with an absolute path for soname
# notice I have set the soname to an absoulte path
❯ gcc -shared -o libf.so -Wl,-soname,/nix/store/znxycsxlnx2s9zn6g0s0fl4z57ar7aps-libf-0.1/lib/libf.so -x c - <<EOF
        #include <stdio.h>
        void f() { puts("hello world"); }
    EOF

❯ patchelf --print-soname libf.so
/nix/store/zir4jfm86i3037lnsaz5br55iwavvhpz-libf-0.1/lib/libf.so

# now build the application that relies on it
❯ gcc -o app -lf -L. -x c - <<EOF
    void f();
    int main() { f(); }
EOF

❯ patchelf --print-needed app
/nix/store/znxycsxlnx2s9zn6g0s0fl4z57ar7aps-libf-0.1/lib/libf.so
libc.so.6
```

Nothing of the above cannot be done during the building of a library __automatically__ within Nix and specifically Nixpkgs. During build time, the store path is known (_$out_) and it can be set for the _soname_.


Ideally, I believe a deep fix for Nixpkgs is possible by altering the [ld-wrapper](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/bintools-wrapper/ld-wrapper.sh) to correctly set the _soname_
which will be picked up for every derivation built with _stdenv_.


Unfortunately since I am not a _bash_ Guru, I opted for a fix similar to _autopatchelf_ -- [nix-harden-needed](https://github.com/fzakaria/nix-harden-needed).

It is a Nix _stdenv_ setuphook that will automatically call _patchelf_ to set the _soname_ to the correct value -- their absolute path. This means that the _DT_NEEDED_
entry for any binary upstream that relies on it will leverage the absolute path and avoid the costly lookup through _RUNPATH_.


It's incredibly easy to use, you simply have to add it as a build input to your derivation. Let's revisit the above example using the setup-hook.
```
let libf = stdenv.mkDerivation rec {
  pname = "libf";
  version = "0.1";

  dontUnpack = true;

  buildInputs = [
    nix-harden-needed-hook
  ];

  buildPhase = ''
    # Enable if you'd like to see wrapper debug information
    # NIX_DEBUG=1 
    $CC -shared -o libf.so -Wl,-soname,libf.so -x c - <<EOF
        #include <stdio.h>
        void f() { puts("hello world"); }
    EOF
  '';

  installPhase = ''
    mkdir -p $out/lib
    mv libf.so $out/lib
  '';
};
in
stdenv.mkDerivation rec {
  pname = "app";

  version = "0.1";

  dontUnpack = true;

  buildInputs = [
    libf
  ];

  buildPhase = ''
    # Enable if you'd like to see wrapper debug information
    # NIX_DEBUG=1 
    $CC -o app -lf -x c - <<EOF
        void f();
        int main() { f(); }
    EOF
  '';

  installPhase = ''
    mkdir -p $out/bin
    mv app $out/bin
  '';

}
```

The built binary will correctly have the _DT_NEEDED_ set to the absolute path of the shared object file.
```console
❯ patchelf --print-needed /nix/store/6pg9d3lwlmgcmmswv937fcy211vkqxch-app-0.1/bin/app
/nix/store/znxycsxlnx2s9zn6g0s0fl4z57ar7aps-libf-0.1/lib/libf.so
libc.so.6
❯ patchelf --print-soname /nix/store/zir4jfm86i3037lnsaz5br55iwavvhpz-libf-0.1/lib/libf.so
/nix/store/zir4jfm86i3037lnsaz5br55iwavvhpz-libf-0.1/lib/libf.so
```

I believe systems such as Nix have ushered a new paradigm shift of thinking about software and there is immense opportunity to go beyond the current limitations and tooling.


🙇 Everything can be re-thought and re-imagined.

> Please reach out if you are a _bash guru_ and we can work together to apply a deeper fix to Nixpkgs of the above ideas.