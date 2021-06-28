---
layout: post
title: Java, Nix & Reproducibility
date: 2021-06-27 19:01 -0700
excerpt_separator: <!--more-->
---
I've written _a lot_ about NixOS; specifically about some of the work I've done to improve the Java ecosystem.

> In fact, I've upstreamed my notes into the [Java Maven Nixpkgs documentation](https://nixos.org/manual/nixpkgs/unstable/#maven).

🎉 Recently, the minimal ISO for NixOS [has become reproducible (r13y)](https://web.archive.org/web/20210620180034/https://r13y.com/). 🎉 

The ability to produce binary reproducible artifacts is a powerful primitive. What does it take for the JVM ecosystem to adopt reproducible builds within the Nix environment?

> For rationale on the _why_, please see [https://reproducible-builds.org/](https://reproducible-builds.org/)

<!--more-->

Traditionally, Nix's primary model for addressing artifacts is via the _input-addressed store_ or _extensional model_; where the name of the package  (cryptographic hash) is derived from it's dependencies, own package description and sources. Put simply, **the _/nix/store/_ path-entry is deterministic irrespective of whether the contents are deterministic**.

This model is pragmatic since in practice, many binary differences are irrelevant (timestamps) however it leads to very pessimistic rebuilds of the source graph.

> Consider the example where a _comment_ is added to a source dependency deep in the dependency graph; this would cause the whole graph to rebuild! If we knew the binary output was the same even with the comment added, we can avoid rebuilding all upstream dependencies.

Where does Java/Maven fit in!?
Let's start with a very simple application.

```xml
<!-- pom.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.nixos</groupId>
  <artifactId>nixos-java-maven-r8</artifactId>
  <version>1.0</version>
  <packaging>jar</packaging>
  <name>NixOS Java Maven Reproducibility</name>

  <properties>
    <maven.compiler.target>1.8</maven.compiler.target>
    <maven.compiler.source>1.8</maven.compiler.source>
  </properties>

  <dependencies>

  </dependencies>

  <build>
  <plugins>
    <plugin>
        <artifactId>maven-jar-plugin</artifactId>
        <version>3.2.0</version>
        <configuration>
            <archive>
                <manifest>
                    <mainClass>Main</mainClass>
                </manifest>
            </archive>
        </configuration>
    </plugin>
  </plugins>
</build>
</project>
```
```java
// src/main/java/Main.java
class Main {
   public static void main( String[] args ){
     System.out.println("Hello NixOS!");
   }

}
```
```nix
{ pkgs ? import <nixpkgs> { }, stdenv ? pkgs.stdenv, lib ? pkgs.lib
, maven ? pkgs.maven, jre ? pkgs.jre, makeWrapper ? pkgs.makeWrapper }:
stdenv.mkDerivation rec {
  pname = "nixos-java-maven-r8";
  version = "1.0";

  __noChroot = true;

  src = lib.cleanSourceWith {
    filter = lib.cleanSourceFilter;
    src = lib.cleanSourceWith {
      filter = path: type:
        !(lib.pathIsDirectory (path) && baseNameOf (toString (path))
          == "target");
      src = ./.;
    };
  };

  buildInputs = [ maven makeWrapper];

  buildPhase = ''
    mvn package;
  '';

  installPhase = ''
    # create the bin directory
    mkdir -p $out/bin

    # copy out the JAR
    # Maven already setup the classpath to use m2 repository layout
    # with the prefix of lib/
    cp target/${pname}-${version}.jar $out/

    # create a wrapper that will automatically call the jar
    makeWrapper ${jre}/bin/java $out/bin/${pname} \
          --add-flags "-jar $out/${pname}-${version}.jar"
  '';
}
```

Nothing surprising here if you've read the Maven Nixpkgs documentation. The one _simplification_ is the use of `__noChroot` which disables sandboxing.
This is to make the use of _Maven_ a bit simpler for education purposes.

Let's build!
```bash
❯ nix-build build.nix --option sandbox relaxed --no-out-link
... bunch of output omitted ...
/nix/store/g1bgxhr84ldag0hyshlz3r7aagq551f8-nixos-java-maven-r8-1.0
```

We can then ask Nix to validate that our derivation is _binary reproducible_.
```bash
❯ nix-build build.nix --option sandbox relaxed --no-out-link --check --keep-failed
... bunch of output omitted ...
derivation '/nix/store/7hfkwwdb5y4llbgykb3dgnb2hy5xwww4-nixos-java-maven-r8-1.0.drv' may not be deterministic: output '/nix/store/g1bgxhr84ldag0hyshlz3r7aagq551f8-nixos-java-maven-r8-1.0' differs from '/nix/store/g1bgxhr84ldag0hyshlz3r7aagq551f8-nixos-java-maven-r8-1.0.check'
note: keeping build directory '/tmp/nix-build-nixos-java-maven-r8-1.0.drv-4'
error: build of '/nix/store/7hfkwwdb5y4llbgykb3dgnb2hy5xwww4-nixos-java-maven-r8-1.0.drv' failed
```

😮 We've hit an error identifying that our build _may not be deterministic_. Let's use [diffoscope](https://diffoscope.org/) to dig into why.

![VPN graphic](/assets/images/maven-diff-r13y.png)

Looks like there is a difference due to timestamps.

The JAR archive format is based on the ZIP archive format, which is [known not to be binary reproducible](https://wiki.debian.org/ReproducibleBuilds/TimestampsInZip).
The ZIP archive format record mtimes of the packed files, which will prevent reproducibility.

> This is in fact why Nix has it's own archive format, _Nix Archive_ (NAR), that addresses typical non-determinism issues with archive formats.

Luckily, Maven itself [has the ability](https://maven.apache.org/guides/mini/guide-reproducible-builds.html) to force-set these timestamps and enable reproducible builds.
```xml
<!-- We add this to our properties, set it to any time you see fit -->
<project.build.outputTimestamp>1</project.build.outputTimestamp>
```

If we try the build again, we are now reproducible.
```bash
# let's repeat the build three times
❯ nix-build build.nix --option sandbox relaxed --no-out-link --option repeat 3 --option enforce-determinism true
building '/nix/store/yvvia00l1vls1qkgypikvjivn2ash498-nixos-java-maven-r8-1.0.drv' (round 1/4)...
building '/nix/store/yvvia00l1vls1qkgypikvjivn2ash498-nixos-java-maven-r8-1.0.drv' (round 2/4)...
building '/nix/store/yvvia00l1vls1qkgypikvjivn2ash498-nixos-java-maven-r8-1.0.drv' (round 3/4)...
building '/nix/store/yvvia00l1vls1qkgypikvjivn2ash498-nixos-java-maven-r8-1.0.drv' (round 4/4)...
/nix/store/ws9flbiil6226lx5ifb1yfd3gijcz27j-nixos-java-maven-r8-1.0
```

This may all seem very _pedantic_, however I ran into the crux of having JARs non-deterministic when building out [mvn2nix](https://github.com/fzakaria/mvn2nix).

Gradle has an interesting call out in [its documentation](https://docs.gradle.org/current/userguide/dependency_verification.html#sec:trusting-several-checksums), for the problem I encountered.
> It’s quite common to have different checksums for the same artifact in the wild. How is that possible? Despite progress, it’s often the case that developers publish, for example, to Maven Central and another repository separately, using different builds.

That means that **you cannot guarantee** that a JAR published on one Maven artifactory, will give you the same binary content from another, **for the exact same version**.

![mind-blown](https://media.giphy.com/media/LpLd2NGvpaiys/giphy.gif)

Reproducible builds provide a lot of benefit. While making a build deterministic is not always feasible, and a touch of pragmatism is useful, we should provide tooling to make it simpler when possible.

_Better yet, have the default be determinism._

> Should we track in Maven Central which packages are reproducible?

## Alternative

We could also make the JAR (ZIP) archive deterministic using Debian's [strip-nondeterminism](https://tracker.debian.org/pkg/strip-nondeterminism) script.

> 🧐 Should this script be included by default in the _fixupPhase_ ?

```nix
postFixup = ''
  # Removing the nondeterminism
  ${strip-nondeterminism}/bin/strip-nondeterminism $out/${pname}-${version}.jar
'';
```