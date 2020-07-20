---
layout: post
title: Packaging a Maven application with Nix
date: 2020-07-20 14:26 -0700
excerpt_separator: <!--more-->
---

Surprisingly for Java's popularity, the Nix Java ecosystem is pretty immature & fragmented. There are several community driven solutions for integrating Maven (Java's package manager) with Nix all which have their own _pitfalls_.

This post will go through a _single idiom_ on how to package a Maven project in Nix that at the very least does not rely on 3rd party support: **Double invoking Maven**

<!--more-->

The main _crux_ of packaging a Maven application in a Nix derivation is that the derivation is restricted from performing any network access. The builder is also in a _chroot_ directory without access to the local Maven repository _~/.m2_.

How can we hydrate the local Maven repository within a Nix derivation?

Using **Fixed output derivations**!

## Fixed Output Derivation

Fixed output derivations (FOD) are derivations that specify the hash of the output contents (Nix typically calculates the hash of the input). These derivations are allowed to perform network access in sandboxed mode.

Here is a very simple _fixed output derivation_ to demonstrate.
```nix
{ pkgs ? import <nixpkgs> {} }:
with pkgs;
runCommand "fetching-with-curl" {
  outputHash = "01c7d3wsq6g4s6k2vl95z2gix8q9spk86knwmgvkfijp04jq00z0";
  outputHashAlgo = "sha256";
  buildInputs = [ curl ];
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
} ''
  curl https://repo.maven.apache.org/maven2/org/codehaus/plexus/plexus-interpolation/1.25/plexus-interpolation-1.25.jar --output $out
''
```

If **outputHash** was not provided; the _cURL_ command would fail to establish a connection.

## Maven Repository as a Fixed Output Derivation

Armed with the knowledge, a Fixed Output Derivation can make network calls, we can construct a derivation that will download all necessary dependencies.

```nix
{ stdenv, jdk11_headless, maven }:
with stdenv;
mkDerivation {
    name = "maven-dependencies";
    buildInputs = [ jdk11_headless maven ];
    src = ./.;
    buildPhase = ''
      while mvn package -Dmaven.repo.local=$out/.m2 -Dmaven.wagon.rto=5000; [ $? = 1 ]; do
        echo "timeout, restart maven to continue downloading"
      done
    '';
    # keep only *.{pom,jar,sha1,nbm} and delete all ephemeral files with lastModified timestamps inside
    installPhase = ''
        find $out/.m2 -type f -regex '.+\\(\\.lastUpdated\\|resolver-status\\.properties\\|_remote\\.repositories\\)' -delete
    '';
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "026wmcpbdvkm7xizxgg0c12z4sl88n2h7bdwvvk6r7y5b6q18nsf";
  };
```

The key insight here is `-Dmaven.repo.local=$out/.m2`; which will cause the execution of _maven_ to download all the necessary dependencies into a maven repository rooted within the derivation's output directory.

> Some additional files are deleted that would cause the output hash to change potentially on subsequent runs.

If your package uses **SNAPSHOT** dependencies; there is a string likelihood that over-time your output hash will change.

We now have an entry in our _/nix/store_ that is a Maven repository of all the necessary dependencies our application needs.

```
/nix/store/bxhr4p2x99jvqk027jsv250b861wklsq-dependencies/.m2
├── backport-util-concurrent
│   └── backport-util-concurrent
│       └── 3.1
│           ├── backport-util-concurrent-3.1.pom
│           ├── backport-util-concurrent-3.1.pom.sha1
│           └── _remote.repositories
├── classworlds
│   └── classworlds
│       ├── 1.1
│       │   ├── classworlds-1.1.jar
│       │   ├── classworlds-1.1.jar.sha1
│       │   ├── classworlds-1.1.pom
│       │   ├── classworlds-1.1.pom.sha1
│       │   └── _remote.repositories
```

## Building the Java Application

With a derivation setup to contain our full Maven repository, we are ready to build the Maven application.

```nix
{ stdenv, jdk11_headless, maven, makeWrapper }:
with stdenv;
let dependencies = { # see above
};
in mkDerivation rec {
  pname = "maven-application";
  inherit version;
  name = "${pname}-${version}";
  src = ./.;
  buildInputs = [ jdk11_headless maven makeWrapper ];
  buildPhase = ''
    # 'maven.repo.local' must be writable so copy it out of nix store
    mvn package --offline -Dmaven.repo.local=${dependencies}/.m2
  '';

  installPhase = ''
    # create the bin directory
    mkdir -p $out/bin

    # create a symbolic link for the lib directory
    ln -s ${dependencies}/.m2 $out/lib

    # copy out the JAR
    # Maven already setup the classpath to use m2 repository layout
    # with the prefix of lib/
    cp target/${name}.jar $out/

    # create a wrapper that will automatically set the classpath
    # this should be the paths from the dependency derivation
    makeWrapper ${jdk11_headless}/bin/java $out/bin/${pname} \
          --add-flags "-jar $out/${name}.jar"
  '';
}
```

This derivation builds the Maven application while instructing Maven to be in "offline" mode (do not try to contact the remote repositories) and we set the local repository to the output of the previous derivation.

```
mvn package --offline -Dmaven.repo.local=${dependencies}/.m2
```

The _makeWrapper_ portion should be straightforward as we are simply offering a simple executable to launch our application.

Another key insight is the symbolic link within our derivation's output to the Maven repository.

```
ln -s ${dependencies}/.m2 $out/lib
```

The main JAR must be instructed to search this directory as part of the ClassPath. Luckily, Maven offers a plugin to easily configure this.

```xml
<plugin>
    <artifactId>maven-jar-plugin</artifactId>
    <version>3.2.0</version>
    <configuration>
        <archive>
            <manifest>
                <addClasspath>true</addClasspath>
                <classpathPrefix>lib/</classpathPrefix>
                <classpathLayoutType>repository</classpathLayoutType>
                <mainClass>com.example.Main</mainClass>
            </manifest>
        </archive>
    </configuration>
</plugin>
```

As the JAR is located in **$out**, we've augmented the ClassPath to search for all dependencies within the **lib/** directory assuming a Maven repository layout.

Here is an example of the **META-INF/MANIFEST.MF** that may be generated
(assuming the output JAR is _application-01.jar_):
```
$ unzip -q -c  result/application-0.1.jar META-INF/MANIFEST.MF

Manifest-Version: 1.0
Created-By: Maven Jar Plugin 3.2.0
Build-Jdk-Spec: 11
Class-Path: . lib/org/slf4j/slf4j-api/1.7.30/slf4j-api-1.7.30.jar lib/or
 g/slf4j/slf4j-simple/1.7.30/slf4j-simple-1.7.30.jar lib/com/google/guav
 a/guava/29.0-jre/guava-29.0-jre.jar lib/com/google/guava/failureaccess/
 1.0.1/failureaccess-1.0.1.jar lib/com/google/guava/listenablefuture/999
 9.0-empty-to-avoid-conflict-with-guava/listenablefuture-9999.0-empty-to
 -avoid-conflict-with-guava.jar lib/com/google/code/findbugs/jsr305/3.0.
 2/jsr305-3.0.2.jar lib/org/checkerframework/checker-qual/2.11.1/checker
 -qual-2.11.1.jar lib/com/google/errorprone/error_prone_annotations/2.3.
 4/error_prone_annotations-2.3.4.jar lib/com/google/j2objc/j2objc-annota
 tions/1.3/j2objc-annotations-1.3.jar
Main-Class: com.example.Main
```

**Congratulations you've just packaged your Maven application with Nix!**

This "double invocation" solution works pretty well but has one major drawback.

Due to the _coarseness_ of having all dependencies in a single output derivation, Nix cannot make use of sharing dependencies across derivations within the _/nix/store_. The solution however is pretty simplistic minus the cost-efficiency due to the wasted space.

I hope that little deep dive into how to build a Maven application through Nix was informative.

## mvn2nix

As mentioned in the top of this post, there are a variety of tools already for integrating Maven with Nix better:
1. [haven](https://github.com/obsidiansystems/haven)
2. [mavenix](https://github.com/nix-community/mavenix)
3. [mvn2nix-maven-plugin](https://github.com/NixOS/mvn2nix-maven-plugin)

Each _somewhat work_ but have odd limitations of trying to work around Maven's clunky API. The problem though is Maven's dependency resolution is complex and rationalizing it from the outside is _error-prone_.

**mvn2nix-maven-plugin** seems like it has the best _shot_ with included support within [nixpkgs](https://github.com/NixOS/nixpkgs) through [buildMaven](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/build-maven.nix) build support but it's slow & has limited support for different repositories.

I started work on a separate binary [mvn2nix](https://github.com/fzakaria/mvn2nix/settings); and seeking collaborators.

The goal is a minimal binary that duplicates Maven's dependency resolution through the exposed APIs to generate a Nix expression for use with _fetchUrl_.
