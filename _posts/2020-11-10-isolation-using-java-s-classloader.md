---
layout: post
title: Isolation using Java's ClassLoader
date: 2020-11-10 10:32 -0800
excerpt_separator: <!--more-->
---

> This is a small write-up of one I sent to my team to help disseminate some knowledge regarding Java's ClassLoader mechanism.

A codebase I'm working on uses Java [ClassLoader](https://docs.oracle.com/javase/7/docs/api/java/lang/ClassLoader.html) to help load multiple JDBC drivers with their *complete* dependencies.

Typically, using Maven or Gradle, a project would have to pin to common dependencies due to the diamond dependency problem at the cost of potential unforeseen bugs due to drift in versions.

Can we do better? Let's dig into ClassLoaders.

<!--more-->

Java uses the _CLASS_PATH_, similar to your shell's _PATH_ when searching to resolve classes.

It's important to understand though that the _CLASS_PATH_ is used during **compilation** and during **runtime**.

> Did you know JAR files are just zip files ?

```console
$ file some-jar.jar
some-jar.jar: Zip archive data, at least v1.0 to extract
```

Let's consider a trivial example where I have three files:

_Dog.java_
```java
public interface Dog {
  void bark();
}
```

_Rottweiler.java_
```java
public class Rottweiler implements Dog {
  public void bark() {
    System.out.println("Woof!");
  }
}
```
_Main.java_
```java
public class Main {
  public static void main(String[] args) {
    Dog moose = new Rottweiler();
    moose.bark();
  }
}
```

I can go ahead and compile these classes & run it.
```console
$ javac Main.java
$ java Main
Woof!
```

> Java searches the current directory automatically as part of the _CLASS_PATH_

I can however go ahead and change _Rottweiler.java_ to now emit _meow_ instead.

```java
public class Rottweiler implements Dog {
  public void bark() {
    System.out.println("Meow!");
  }
}
```
```console
$ javac Dog.java
$ java Main
Starting application!
Meow!
```

I **did not** have to recompile _Main.java_ however.

This distinguishes that a class file or dependency can be compiled against a certain version of a class but run using a different version ultimately.

This gets at the heart of _dependency management_ & why we use tools like Gradle.

When you perform **compilation**, Java resolves classes to validate the public API (public classes & methods) are present, however at **runtime** you can use a different implementation.

> If you are familiar with C/C++ this is similar in concept to header & object files. In fact Google has a neat tool [ijar](https://github.com/bazelbuild/bazel/tree/master/third_party/ijar) that turns class files into only their public signatures, resembling even more closer to header files.

A common problem though is what if I am pulling in two libraries that both require the same dependency but were built (compiled) using different versions -- this is known as the "_diamond dependency problem_".

<figure>
<svg class="version-sat" viewBox="-1 -1 296 165" width="296pt" height="165pt" role="img"
     style="display:block;margin-inline:auto"
     aria-label="Diamond Dependency">
<style>
  .version-sat { --vs-ok: #0432ff; --vs-bad: #ff2600; }
  @media (prefers-color-scheme: dark) { .version-sat { --vs-ok: #5c7cff; } }
  .version-sat .box { fill: none; stroke: var(--ink, #1a1815); stroke-linecap: round; stroke-linejoin: round; stroke-width: 1; }
  .version-sat .ver { fill: none; stroke: var(--ink-muted, #565046); stroke-linecap: round; stroke-linejoin: round; stroke-width: 1; }
  .version-sat .dep { stroke: var(--ink, #1a1815); stroke-linecap: round; stroke-linejoin: round; stroke-width: 1; }
  .version-sat .ok { stroke: var(--vs-ok); stroke-linecap: round; stroke-linejoin: round; stroke-width: 1; }
  .version-sat .bad { stroke: var(--vs-bad); stroke-linecap: round; stroke-linejoin: round; stroke-width: 1; stroke-dasharray: 1,3; }
  .version-sat .key { stroke-width: .75; }
  .version-sat text { font-family: Arial, Helvetica, sans-serif; font-size: 12px; font-weight: 500; fill: var(--ink, #1a1815); }
  .version-sat text.legend { font-family: Helvetica, Arial, sans-serif; font-size: 8px; }
  .version-sat text.ok { fill: var(--vs-ok); stroke: none; }
  .version-sat text.bad { fill: var(--vs-bad); stroke: none; }
</style>
<defs>
  <marker orient="auto" overflow="visible" markerUnits="strokeWidth" id="version-sat-arrow" viewBox="-1 -4 10 8" markerWidth="10" markerHeight="8">
    <path d="M 8 0 L 0 -3 L 0 3 Z" style="fill: var(--ink, #1a1815); stroke: var(--ink, #1a1815)" stroke-width="1"/>
  </marker>
  <marker orient="auto" overflow="visible" markerUnits="strokeWidth" id="version-sat-ok" viewBox="-1 -4 10 8" markerWidth="10" markerHeight="8">
    <path d="M 8 0 L 0 -3 L 0 3 Z" style="fill: var(--vs-ok); stroke: var(--vs-ok)" stroke-width="1"/>
  </marker>
  <marker orient="auto" overflow="visible" markerUnits="strokeWidth" id="version-sat-bad" viewBox="-1 -4 10 8" markerWidth="10" markerHeight="8">
    <path d="M 8 0 L 0 -3 L 0 3 Z" style="fill: var(--vs-bad); stroke: var(--vs-bad)" stroke-width="1"/>
  </marker>
</defs>

<!-- A depends on B and C -->
<rect class="box" x="78" y="0" width="76" height="23.5"/>
<text x="111.998047" y="15.553711" textLength="8.003906">A</text>
<rect class="box" x="0" y="48" width="76" height="23.5"/>
<text x="33.998047" y="63.55371" textLength="8.003906">B</text>
<rect class="box" x="156" y="46" width="76" height="23.5"/>
<text x="189.666992" y="61.55371" textLength="8.666016">C</text>
<line class="dep" x1="135.92391" y1="23.5" x2="165.54856" y2="40.97095" marker-end="url(#version-sat-arrow)"/>
<line class="dep" x1="96.90625" y1="23.5" x2="65.52517" y2="42.811435" marker-end="url(#version-sat-arrow)"/>

<!-- D, in two versions -->
<rect class="box" x="48" y="117" width="136" height="46.5"/>
<text x="111.66699" y="155.60742" textLength="8.666016">D</text>
<rect class="ver" x="59.5" y="128.5" width="47.5" height="23.5"/>
<text x="66.9111328" y="144.05371" textLength="32.677734">vers 1</text>
<rect class="ver" x="125" y="128.5" width="47.5" height="23.5"/>
<text x="132.4111328" y="144.05371" textLength="32.677734">vers 2</text>

<!-- B and C each work with one version and break with the other -->
<line class="ok" x1="44.604814" y1="71.5" x2="71.794145" y2="119.86997" marker-end="url(#version-sat-ok)"/>
<line class="ok" x1="187.5553" y1="69.5" x2="159.9556" y2="119.81991" marker-end="url(#version-sat-ok)"/>
<line class="bad" x1="54.16537" y1="71.5" x2="124.57658" y2="122.67925" marker-end="url(#version-sat-bad)"/>
<line class="bad" x1="178.22652" y1="69.5" x2="106.9628" y2="122.58584" marker-end="url(#version-sat-bad)"/>

<!-- legend -->
<line class="bad key" x1="199.5" y1="130" x2="275.95" y2="130" marker-end="url(#version-sat-bad)"/>
<text class="legend bad" x="219.042969" y="128" textLength="44.91406">incompatible</text>
<line class="ok key" x1="199.5" y1="150" x2="275.95" y2="150" marker-end="url(#version-sat-ok)"/>
<text class="legend ok" x="222.15625" y="148" textLength="38.6875">compatible</text>
</svg>
</figure>

Oftentimes "code just works", especially if the dependency is properly following semantic versioning, you are hopefully not likely to encounter a _ClassNotFoundException_ or _MethodNotFoundException_.

There's **no guarantee** that internal logic hasn't changed enough to make the different versions meaningful such as in the case of the Dog example above (woof vs meow).

The best you can do for classes A, B & C is to make sure they were both built & run with the same version (Google's raison d'etre for the mono repo) or extensive testing to make sure there's no meaningful drift in implementation when pinning to a single version.

Let's change our Dog example to resemble the following:

```console
$ tree
.
├── Dog.class
├── Dog.java
├── Main.class
├── Main.java
├── v1
│   ├── Rottweiler.class
│   └── Rottweiler.java
└── v2
    ├── Rottweiler.class
    └── Rottweiler.java
```

We now have a V1 and V2 of the Rottweiler class (V1 has the incorrect _Meow!_)

We can load both versions of the Rottweiler class using a custom _ClassLoader_ for each version.

```java
import java.io.File;
import java.net.URL;
import java.net.URLClassLoader;

public class Main {
    public static void main(String[] args) throws Exception {
        final ClassLoader v1Loader =
                new URLClassLoader(
                        new URL[] { new File("v1/").toURL() },
                        ClassLoader.getSystemClassLoader());
        Class<?> clazzV1 = v1Loader.loadClass("Rottweiler");
        Dog mooseV1 = (Dog) clazzV1.newInstance();
        mooseV1.bark();

        final ClassLoader v2Loader =
                new URLClassLoader(
                        new URL[] { new File("v2/").toURL() },
                        ClassLoader.getSystemClassLoader());
        Class<?> clazzV2 = v2Loader.loadClass("Rottweiler");
        Dog mooseV2 = (Dog) clazzV2.newInstance();
        mooseV2.bark();
    }
}
```

```console
$ java Main
Woof!
Meow!
```

Ultimately, we used _ClassLoader_ as a way to create **isolation** between the classes so we can resolve to multiple versions at a time.

For this to work though, we must have used an _interface_ (Dog) otherwise there would be no way to perform the casting to the _Rottweiler_ implementation, since that would need to be resolved at compile time!

You can do a lot of fancier stuff with _ClassLoaders_, such as even creating classes dynamically at runtime. Wow! I'll leave that as a follow-up exercise :)