---
layout: post
title: mvn2nix; welcoming Maven into Nix's warm embrace
date: 2020-09-04 09:09 -0700
excerpt_separator: <!--more-->
---

I wrote [previously]({% post_url 2020-07-20-packaging-a-maven-application-with-nix %}) about the current state of affairs for Java packaging in the Nix ecosystem; including a little blurb at the end about a little project I have been working on.

I would like to announce a _beta release_ for [mvn2nix](https://github.com/fzakaria/mvn2nix).

You find find the similar announcement on <https://discourse.nixos.org/t/mvn2nix-packaging-maven-application-made-easy/8751>

> Easily package your Maven Java application with the Nix package manager.

**mvn2nix** is my attempt & re-imagining of what a lock file type Nix Java ecosystem should look like.

<!--more-->

⚠️ **mvn2nix** is seeing active development. Please pin the commit to avoid any breaking changes.

### Philosophical Goals

1. is written in Java itself;
2. is self-bootstrapped; it builds itself!
3. very easy to understand derivations
4. lots of documentation
5. examples on how to produce a runnable JAR

### Demo

You can easily run **mvn2nix** using *nix run*.
```bash
$ nix run -f https://github.com/fzakaria/mvn2nix/archive/master.tar.gz \
--command mvn2nix
```

Doing so on a Maven project with a _pom.xml_ will produce lock file contents.
```bash
$ nix run -f https://github.com/fzakaria/mvn2nix/archive/master.tar.gz \
        --command mvn2nix > mvn2nix-lock.json

$ head mvn2nix-lock.json
{
  "dependencies": {
    "org.junit.jupiter:junit-jupiter:jar:5.6.2": {
      "layout": "org/junit/jupiter/junit-jupiter/5.6.2/junit-jupiter-5.6.2.jar",
      "sha256": "dfc0d870dec4c5428a126ddaaa987bdaf8026cc27270929c9f26d52f3030ac61",
      "url": "https://repo.maven.apache.org/maven2/org/junit/jupiter/junit-jupiter/5.6.2/junit-jupiter-5.6.2.jar"
    },
    "org.codehaus.plexus:plexus-utils:pom:3.0.15": {
      "layout": "org/codehaus/plexus/plexus-utils/3.0.15/plexus-utils-3.0.15.pom",
      "sha256": "b4fe0bed469e2e973c661b4b7647db374afee7bda513560e96cd780132308f0b",
      "url": "https://repo.maven.apache.org/maven2/org/codehaus/plexus/plexus-utils/3.0.15/plexus-utils-3.0.15.pom"
    },
```

The contents of this file are the full **transitive** dependency closure for your Maven; including every dependency needed to get to the desired [lifecycle](https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html) (defaults to _package_).

You can then use this to download all the necessary dependencies to re-run the same lifecycle with Maven offline!

#### Building a Maven Repository

**mvn2nix** includes a simple derivation that creates a symlink join of every dependency found in the lock file.

```nix
let mvn2nix = import (fetchTarball https://github.com/fzakaria/mvn2nix/archive/master.tar.gz) { };
in
mvn2nix.buildMavenRepositoryFromLockFile { file = ./mvn2nix-lock.json; }
```

This creates a _/nix/store_ path which is a Maven repository that can be used, such as in `mvn package --offline -Dmaven.repo.local=${mavenRepository}`

```
$ tree /nix/store/0ylsqi62jqz5gqf0dqrz5a3hj3jrzrwx-mvn2nix-repository | head

/nix/store/0ylsqi62jqz5gqf0dqrz5a3hj3jrzrwx-mvn2nix-repository
├── com
│   └── google
│       ├── code
│       │   └── findbugs
│       │       └── jsr305
│       │           └── 3.0.2
│       │               └── jsr305-3.0.2.jar -> /nix/store/w20lb1dk730v77qis8l6sjqpljwkyql7-jsr305-3.0.2.jar
│       ├── errorprone
│       │   └── error_prone_annotations
```

A simple derivation to invoke Maven now becomes
```nix
mkDerivation rec {
  pname = "my-artifact";
  version = "0.01";
  name = "${pname}-${version}";
  src = lib.cleanSource ./.;

  buildInputs = [ jdk11_headless maven makeWrapper ];
  buildPhase = ''
    echo "Building with maven repository ${mavenRepository}"
    mvn package --offline -Dmaven.repo.local=${mavenRepository}
  '';
```

#### Runnable JAR

Executing maven is pretty simple now; but ultimately it would be great to get a runnable target.

If you've used Maven in the past you might look to re-using [Maven Assembly Plugin](http://maven.apache.org/plugins/maven-assembly-plugin/), [Maven Shade Plugin](https://maven.apache.org/plugins/maven-shade-plugin/) or [Capsule Maven Plugin](https://github.com/chrisdchristo/capsule-maven-plugin); the problem however is these solutions don't take advantage of the fact that the dependencies are already _in the store!_

Setup your _maven-jar-plugin_ to create a manifest which expects the Maven repository layout.

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
                <mainClass>com.fzakaria.mvn2nix.Main</mainClass>
            </manifest>
            <manifestEntries>
                <Class-Path>.</Class-Path>
            </manifestEntries>
        </archive>
    </configuration>
</plugin>
```

The _installPhase_ of our derivation now merely needs to link the **lib** directory to our **mavenRepository** built with _mvn2nix_.

```nix
installPhase = ''
    # create the bin directory
    mkdir -p $out/bin

    # create a symbolic link for the lib directory
    ln -s ${repository} $out/lib

    # copy out the JAR
    # Maven already setup the classpath to use m2 repository layout
    # with the prefix of lib/
    cp target/${name}.jar $out/

    # create a wrapper that will automatically set the classpath
    # this should be the paths from the dependency derivation
    makeWrapper ${jdk}/bin/java $out/bin/${pname} \
          --add-flags "-jar $out/${name}.jar" \
          --set M2_HOME ${maven} \
          --set JAVA_HOME ${jdk}
'';
```

🎆 We now have a runnable JAR! Using the dependencies from the _/nix/store_! 🎆