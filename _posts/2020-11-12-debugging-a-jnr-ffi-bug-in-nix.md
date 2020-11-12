---
layout: post
title: Debugging a JNR-FFI bug in Nix
date: 2020-11-12 09:46 -0800
excerpt_separator: <!--more-->
---

> This is a write-up of an issue I discovered when using more advanced features of Java within a Nix environment. Please refer to the GitHub issue [#103493](https://github.com/NixOS/nixpkgs/issues/103493) to see any ongoing process

I have been onboarding several engineers to doing their development workflow using Nix; promising all the benefits of hermeticity & reproducibility. The biggest challenge is making sure that onboarding continues to be _seemless_.

Therefore it's 🚨 *all hands on deck* when someone has encountered a SIGSEGV; especially since the environment is within the JVM.
```bash
#
# A fatal error has been detected by the Java Runtime Environment:
#
#  SIGSEGV (0xb) at pc=0x0000000000000680, pid=3229039, tid=0x00007ff8c5834640
#
# JRE version: OpenJDK Runtime Environment (8.0_265) (build 1.8.0_265-ga)
# Java VM: OpenJDK 64-Bit Server VM (25.265-bga mixed mode linux-amd64 compressed oops)
# Problematic frame:
# C  0x0000000000000680
```

<!--more-->

## Debugging

Typically Java & Nix work well together since there's not much reliance on system libraries beyond than what the JVM pulls in, unless you use JNI or JNR.

> [jnr-ffi](https://github.com/jnr/jnr-ffi) is a Java library for loading native libraries without writing JNI code by hand, or using tools such as SWIG.

The fist challenge in any SIGSEGV or bug for that matter is getting the **smallest reproducible failure**.

Our team is using [JRuby](https://github.com/jruby/jruby), so coming up with a small one-liner to reproduce the issue was useful.

Analyzing the stack trace in the coredump logs in JRuby is not very helpful, so stepping through the code to find the failing line was the method of choice here.

```
Java frames: (J=compiled Java code, j=interpreted, Vv=VM code)
j  com.kenai.jffi.Foreign.invokeN5O1(JJJJJJJLjava/lang/Object;III)J+0
j  com.kenai.jffi.Invoker.invokeN5(Lcom/kenai/jffi/CallContext;JJJJJJILjava/lang/Object;Lcom/kenai/jffi/ObjectParameterStrategy;Lcom/kenai/jffi/ObjectParameterInfo;Ljava/lang/Object;Lcom/kenai/jffi/ObjectParameterStrategy;Lcom/kenai/jffi/ObjectParameterInfo;Ljava/lang/Object;Lcom/kenai/jffi/ObjectParameterStrategy;Lcom/kenai/jffi/ObjectParameterInfo;Ljava/lang/Object;Lcom/kenai/jffi/ObjectParameterStrategy;Lcom/kenai/jffi/ObjectParameterInfo;)J+198
j  jnr.netdb.NativeProtocolsDB$LinuxLibProto$jnr$ffi$3.getprotobyname_r(Ljava/lang/String;Ljnr/netdb/NativeProtocolsDB$UnixProtoent;Ljnr/ffi/Pointer;Ljnr/ffi/NativeLong;Ljnr/ffi/Pointer;)I+223
j  jnr.netdb.NativeProtocolsDB$LinuxNativeProtocolsDB.getProtocolByName(Ljava/lang/String;)Ljnr/netdb/Protocol;+48
j  jnr.netdb.NativeProtocolsDB.load()Ljnr/netdb/NativeProtocolsDB;+244
j  jnr.netdb.NativeProtocolsDB.access$000()Ljnr/netdb/NativeProtocolsDB;+0
j  jnr.netdb.NativeProtocolsDB$SingletonHolder.<clinit>()V+0
v  ~StubRoutines::call_stub
j  jnr.netdb.NativeProtocolsDB.getInstance()Ljnr/netdb/NativeProtocolsDB;+0
j  jnr.netdb.Protocol$ProtocolDBSingletonHolder.load()Ljnr/netdb/ProtocolsDB;+0
j  jnr.netdb.Protocol$ProtocolDBSingletonHolder.<clinit>()V+0
v  ~StubRoutines::call_stub
j  jnr.netdb.Protocol.getProtocolDB()Ljnr/netdb/ProtocolsDB;+0
j  jnr.netdb.Protocol.getProtocolByNumber(I)Ljnr/netdb/Protocol;+0
j  org.jruby.ext.socket.Addrinfo.<init>(Lorg/jruby/Ruby;Lorg/jruby/RubyClass;Ljava/net/NetworkInterface;Z)V+38
j  org.jruby.ext.socket.Ifaddr.setAddr(Lorg/jruby/Ruby;)V+61
j  org.jruby.ext.socket.Ifaddr.<init>(Lorg/jruby/Ruby;Lorg/jruby/RubyClass;Ljava/net/NetworkInterface;)V+58
```

Turned out that the failing line was the following which looks seemingly innocuous 🤔
```ruby
UUID.generate.tr
```

Digging into the gems, we trace [see](https://github.com/assaf/uuid/blob/master/lib/uuid.rb#L240) the code through.
```ruby
##
# Uses system calls to get a mac address
#
def iee_mac_address
  begin
    Mac.addr.gsub(/:|-/, '').hex & 0x7FFFFFFFFFFF
  rescue
    0
  end
end
```

Which ends up [calling](https://github.com/ahoward/macaddr/blob/master/lib/macaddr.rb#L82) the following code
```ruby
def from_getifaddrs
  return unless Socket.respond_to? :getifaddrs

  interfaces = Socket.getifaddrs.select do |addr|
    if addr.addr  # Some VPN ifcs don't have an addr - ignore them
      addr.addr.pfamily == INTERFACE_PACKET_FAMILY
    end
  end
```

💡 Aha! This now correlates to portions of the stacktrace that at first were not fully clear.

```bash
j  jnr.netdb.Protocol.getProtocolDB()Ljnr/netdb/ProtocolsDB;+0
j  jnr.netdb.Protocol.getProtocolByNumber(I)Ljnr/netdb/Protocol;+0
j  org.jruby.ext.socket.Addrinfo.<init>(Lorg/jruby/Ruby;Lorg/jruby/RubyClass;Ljava/net/NetworkInterface;Z)V+38
j  org.jruby.ext.socket.Ifaddr.setAddr(Lorg/jruby/Ruby;)V+61
j  org.jruby.ext.socket.Ifaddr.<init>(Lorg/jruby/Ruby;Lorg/jruby/RubyClass;Ljava/net/NetworkInterface;)V+58
j  org.jruby.ext.socket.RubySocket.getifaddrs(Lorg/jruby/runtime/ThreadContext;Lorg/jruby/runtime/builtin/IRubyObject;)Lorg/jruby/runtime/builtin/IRubyObject;+61
```

Putting this all together, we can now write a minimal reproducer.

```bash
❯ which jruby
/nix/store/v0frl1gs13bxs7g3hvlrm3656zq9ra5f-jruby-9.2.13.0/bin/jruby

❯ gem install macaddr
❯ jruby -e "require 'macaddr'; require 'jruby/path_helper'; puts Mac.addr"

#
# A fatal error has been detected by the Java Runtime Environment:
#
#  SIGSEGV (0xb) at pc=0x0000000000000680, pid=3229039, tid=0x00007ff8c5834640
```

Now that we have a small reproducer, we can start to investigate.

## Investigation

Jumping to the [jnr-netdb](https://github.com/jnr/jnr-netdb) library, we [find](https://github.com/jnr/jnr-netdb/blob/cf6b34662cea211e58736d0fec91d25d6a186912/src/main/java/jnr/netdb/NativeProtocolsDB.java#L68) that the only external library opened is *libc*

```java
String[] libnames = os.equals(SOLARIS)
        ? new String[]{"socket", "nsl", "c"}
        : new String[]{"c"};
lib = os.equals(LINUX)
    ? Library.loadLibrary(LinuxLibProto.class, libnames)
    : Library.loadLibrary(LibProto.class, libnames);
```

Okay, so the _hunch_ is that the wrong _libc_ is being brought in, let's check with **LD_DEBUG=libs**.

```bash
❯ LD_DEBUG=libs jruby -e "require 'macaddr'; require 'jruby/path_helper'; puts Mac.addr"
...
   3769338: calling init: /lib/x86_64-linux-gnu/libc.so.6
...
```

💡 Great! We are definitely resolving to a different libc than what is already set in the ELF header of our Java process.

```
❯ ldd $(which java)
    ...
    libc.so.6 =>
    /nix/store/bdf8iipzya03h2amgfncqpclf6bmy3a1-glibc-2.32/lib/libc.so.6 (0x00007f9e58bc6000)
    ...
```

Java uses the system property **java.library.path** or environment variable **LD_LIBRARY_PATH** (on Linux) to check where to load libraries.

I had neither set, so what gives?

The final piece of the puzzle involves looking through the [JDK source code](https://github.com/openjdk/jdk/blob/50357d136a775872999055bef61057b884d80693/src/hotspot/os/linux/os_linux.cpp#L413) itself, to discover that if neither is set, the JVM **automatically includes some as default**.

```cpp
  // See ld(1):
  //      The linker uses the following search paths to locate required
  //      shared libraries:
  //        1: ...
  //        ...
  //        7: The default directories, normally /lib and /usr/lib.
#ifndef OVERRIDE_LIBPATH
  #if defined(AMD64) || (defined(_LP64) && defined(SPARC)) || defined(PPC64) || defined(S390)
    #define DEFAULT_LIBPATH "/usr/lib64:/lib64:/lib:/usr/lib"
  #else
    #define DEFAULT_LIBPATH "/lib:/usr/lib"
  #endif
#else
  #define DEFAULT_LIBPATH OVERRIDE_LIBPATH
#endif
```

## Solution

The _long term / correct_ solution would be to patch the Nix distribution of the JDK to exclude these default library paths. However in the interest of solving it immediately for the engineers, specifying the correct library paths is essential.

I added the following to our _shell.nix_ file
```nix
# This is a way to globally set Java system properties without having to specify
# them on the CLI
# Specifically, here we make sure to set the equivalent of Java's LD_LIBRARY_PATH to find
# the correct glibc library.
# `java.library.path` is used by Java when dynamic linking
# This needs to be set in order to determine where to find libraries
#
# https://docs.oracle.com/en/java/javase/14/docs/api/java.base/java/lang/System.html#java.library.path
# https://docs.oracle.com/javase/8/docs/platform/jvmti/jvmti.html#tooloptions
export JAVA_TOOL_OPTIONS=-Djava.library.path=${stdenv.lib.makeLibraryPath [ stdenv.cc.libc ]}
```

⚠️ You **do not** want to set _LD_LIBRARY_PATH_ because that will affect **every binary** you run in your _nix-shell_.

Another suitable solution would be to use [makeWrapper](https://nixos.org/manual/nixpkgs/stable/#ssec-stdenv-functions) on Java itself to set _LD_LIBRARY_PATH_ only for itself.

Are you looking to help contribute to Nix? Reach out to [me](mailto:farid.m.zakaria@gmail.com) and let's fix the JDK as mentioned above. I'm also looking for other people to help improve the overall language-support of Java in Nix. 🙏