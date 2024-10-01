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

```bash
❯ file some-jar.jar
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
```bash
❯ javac Main.java
❯ java Main
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
```bash
❯ javac Dog.java
❯ java Main
Starting application!
Meow!
```

I **did not** have to recompile _Main.java_ however.

This distinguishes that a class file or dependency can be compiled against a certain version of a class but run using a different version ultimately.

This gets at the heart of _dependency management_ & why we use tools like Gradle.

When you perform **compilation**, Java resolves classes to validate the public API (public classes & methods) are present, however at **runtime** you can use a different implementation.

> If you are familiar with C/C++ this is similar in concept to header & object files. In fact Google has a neat tool [ijar](https://github.com/bazelbuild/bazel/tree/master/third_party/ijar) that turns class files into only their public signatures, resembling even more closer to header files.

A common problem though is what if I am pulling in two libraries that both require the same dependency but were built (compiled) using different versions -- this is known as the "_diamond dependency problem_".

![Diamond Dependency](/assets/images/version-sat.svg)

Oftentimes "code just works", especially if the dependency is properly following semantic versioning, you are hopefully not likely to encounter a _ClassNotFoundException_ or _MethodNotFoundException_.

There's **no guarantee** that internal logic hasn't changed enough to make the different versions meaningful such as in the case of the Dog example above (woof vs meow).

The best you can do for classes A, B & C is to make sure they were both built & run with the same version (Google's raison d'etre for the mono repo) or extensive testing to make sure there's no meaningful drift in implementation when pinning to a single version.

Let's change our Dog example to resemble the following:

```bash
❯ tree
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

```bash
❯ java Main
Woof!
Meow!
```

Ultimately, we used _ClassLoader_ as a way to create **isolation** between the classes so we can resolve to multiple versions at a time.

For this to work though, we must have used an _interface_ (Dog) otherwise there would be no way to perform the casting to the _Rottweiler_ implementation, since that would need to be resolved at compile time!

You can do a lot of fancier stuff with _ClassLoaders_, such as even creating classes dynamically at runtime. Wow! I'll leave that as a follow-up exercise :)