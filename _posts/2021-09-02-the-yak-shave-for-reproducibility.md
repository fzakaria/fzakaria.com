---
layout: post
title: The yak shave for reproducibility
date: 2021-09-02 18:01 -0700
excerpt_separator: <!--more-->
---

I have been on a mission to bring reproducibility through the use of [Nix](http://nixos.org/) into my workplace as we invision the next version of our development environment.

Similar to the movies I watch that take place in space, it only takes a small hole to destroy your hermetic environment. 🧑‍🚀 

<!--more-->

I've [written previously]({% post_url _posts/2020-11-12-debugging-a-jnr-ffi-bug-in-nix %}) about my encounters trying to remove all impurities within a JVM environment.

I've actually [upstreamed](https://github.com/NixOS/nixpkgs/pull/123708) fixing the default _java.library.path_ for the OpenJDK distributed by Nixpkgs. 🙌 

Awesome! That should have solved my problem, right ?...

Unfortunately, _impurities_ are tough to stamp out. NixOS is trying to accomplish a paradigm shift by dismissing the _[filesystem hierarchy standard](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard)_ but it is deeply routed in assumptions when people build for Linux.

In my specific case, the search paths for the JNR libraries were [hardcoded](https://github.com/jnr/jnr-ffi/blob/2161d3d875869bdaf292b0e9267bb0fbdb0f3f2b/src/main/java/jnr/ffi/LibraryLoader.java#L511).

```java
// paths should have no duplicate entries and have insertion order
LinkedHashSet<String> paths = new LinkedHashSet<String>();
try {
    paths.addAll(getPropertyPaths("jnr.ffi.library.path"));
    paths.addAll(getPropertyPaths("jaffl.library.path"));
    // Add JNA paths for compatibility
    paths.addAll(getPropertyPaths("jna.library.path"));
    // java.library.path should take care of Windows defaults
    paths.addAll(getPropertyPaths("java.library.path"));
} catch (Exception ignored) {
}
if (Platform.getNativePlatform().isUnix()) {
    // order is intentional!
    paths.add("/usr/local/lib");
    paths.add("/usr/lib");
    paths.add("/lib");
}
```

> I've sent [a fix upstream](https://github.com/jnr/jnr-ffi/pull/264/) please feel free to comment.

This meant that I had to make sure the _java.library.path_ resolved to the _glibc_ I am using in Nixpkgs first.

I couldn't get rid of the `JAVA_TOOL_OPTIONS` just yet. 😤

## What's the cost of all this?

First off, the JDK emits `JAVA_TOOL_OPTIONS` via _stderr_ which is [non-configurable](https://github.com/AdoptOpenJDK/openjdk-jdk8u/blob/9a751dc19fae78ce58fb0eb176522070c992fb6f/hotspot/src/share/vm/runtime/arguments.cpp#L3753).

```c
if (os::getenv(name, buffer, sizeof(buffer)) &&
    !os::have_special_privileges()) {
  JavaVMOption options[N_MAX_OPTIONS];      // Construct option array
  jio_fprintf(defaultStream::error_stream(),
            "Picked up %s: %s\n", name, buffer);
```

This is frustrating because plenty of tools (i.e. IntelliJ) assume failure if anything is emitted to _stderr_.

Secondly, we have many developers that are being hit by this particular workflow:

1. Developer sets up their IntelliJ JRuby SDK to point to Jruby which points to _/nix/store_ path **A** linked with glibc **B**.
2. Developer changes their Git branch to a different point in time where JRuby points to a different _/nix/store_ path **X** linked with glibc **Z**.
3. The developer restarts IntelliJ and picks up the new environment variable _JAVA_TOOL_OPTIONS_ 💥

> If you read [my earlier post]({% post_url _posts/2020-11-12-debugging-a-jnr-ffi-bug-in-nix %}), you'll understand why _JAVA_TOOL_OPTIONS_ includes glibc.

That _JAVA_TOOL_OPTIONS_ references glibc **Z** but their JRuby SDK is pointing to JRuby **A** which was built against glibc **B**.

Ugh! The fix here is straightforward ultimately -- the developer needs to be mindful of their JRuby SDK set in IntelliJ and keep it in sync with their local checkout.

Unfortunately it's a sharp edge many are running into; and I don't blame them!

We will be thinking of some sane ways to keep these two tools in sync so that we can remain on upstream for now... 🤔 