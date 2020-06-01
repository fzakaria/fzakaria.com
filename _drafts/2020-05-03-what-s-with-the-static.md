---
layout: post
title: what's with the static
date: 2020-05-03 21:40 -0700
---

Twenty years ago, we use to write software that was incredibly hard to test. Everything referenced concrete implementations, singletons and global variable.

```java
class SomeClass {

   public static boolean DoThing() {
        return SomeOtherClass.SINGLETON.DoThing();
   }
}
```

The benefits of employing [inversion of control](https://en.wikipedia.org/wiki/Inversion_of_control) has been "mainstream" for a while now. In fact, we might have jumped the shark on it one or more time[^1].

> The Spring Framework was released in 2002. Wow.

[^1]: https://github.com/EnterpriseQualityCoding/FizzBuzzEnterpriseEdition