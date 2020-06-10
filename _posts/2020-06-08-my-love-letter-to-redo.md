---
layout: post
title: my love letter to redo
date: 2020-06-08 16:09 -0700
excerpt_separator: <!--more-->
---

> This is a _public love letter_ to **redo** & the joy it brings building
> software.

I remember when I first finished [The Little Schemer](https://amzn.to/3cJLe9T) and wrote my first _semi_ useful "JSON Diff" program. I was exalted. I was elated. I was ecstatic.

There is something magical when you learn Lisp that is really tough to convey over a blog post or short article. **One must try it, to grok it**. 

I have not professionally used Lisp much since however it's been immensely impactful in the way I think about & construct software. 

**Redo is this for build systems**.

<!--more-->

I must have come across several articles about _Redo_ or even [djb's](https://en.wikipedia.org/wiki/Daniel_J._Bernstein) own [cryptic posts](https://cr.yp.to/redo.html) on it however I filed it mentally in the same mental folder I put a lot of stuff I come across on Hacker News; "Cool".

> [apenwarr's post](https://apenwarr.ca/log/20101214) announcing his implementing is c.2010 !

Redo however is **eye opening**. I may not use it professionally, similar to Lisp, but it's made an impact on how I view build systems going forward.

Many of you reading this post will do what I've done previously coming across Redo; however I hope that at least some fraction of you try it. **Take the red pill.**

My goal here is not to explain _how_ to use Redo; I think Apenwarr's [documentation](https://redo.readthedocs.io/) does a great job of walking one through it. Here though are some standout bits of Redo that were amazing:

: Redo is a simple set of primitives executed via the shell.

: Redo primitives (build scripts) can be written in _any_ language. 

: Redo is _tiny_!

: Redo can integrate seamlessly in any build system or wrap them.

: Redo supports checksumming of targets, not just [mtime](https://apenwarr.ca/log/20181113).

I really encourage everyone to read Apenwarr's original blog post announcing it
[https://apenwarr.ca/log/20101214](https://apenwarr.ca/log/20101214).

If you've read this far and are thinking _"If Redo is so great, how come it hasn't taken over?"_

**I'm asking myself the same thing.**