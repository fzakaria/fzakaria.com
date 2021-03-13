---
layout: post
title: JRuby and Sorbet
date: 2021-03-13 10:11 -0800
excerpt_separator: <!--more-->
---

A [recent tweet](https://twitter.com/jruby/status/1367170867164295170) by the JRuby folks, let me know that the work I had done a while ago to get [Sorbet](https://sorbet.org/) working seemed to have gone under the radar.

> Sorbet is a fast, powerful type checker designed for Ruby.

I wanted to reflect on it's use at our current codebase, challenges still faced and where to go next.

If you want to cut ahead and start using Sorbet right away, I've contributed some [documentation](https://github.com/sorbet/sorbet/blob/master/docs/JRuby.md).
<!--more-->

![JRuby Sorbet Tweet](/assets/images/jruby_sorbet_tweet.png){: width="500" }

## Why Sorbet?

This was a surprisingly challenging argument to make to those only accustomed to working with Ruby. Those in the _thick_ of the codebase felt unencumbered by the lack of types and imagined it would only hinder their development.

I've come to appreciate that Ruby follows a simple axiom in which **it favors the writer not the reader**. It's what makes Ruby such a pleasure to write however a pain to read.

Thankfully, the tide has been turning for most languages. Python 3 has optional types, Typescript was introduced and types have been formally released in [Ruby 3](https://github.com/ruby/rbs).

Sorbet, aware of these hesitations, was designed with them in mind. It offers: gradual typing, runtime validation, static validation and is extremely fast on large codebases.

## JRuby Integration

Sorbet was not designed to work with JRuby in mind initially, however I found that not much was needed to get it working.

## sorbet-static

The primary blocker, which I've upstreamed was the creation of a Java platform gem for _sorbet-static_. This means you can easily add it to any existing JRuby Gemfile and have the static binary available.

> If you are curious, checkout [3c508a9c948a3b456cf564a5fb01279da1ffdc44](https://github.com/sorbet/sorbet/commit/3c508a9c948a3b456cf564a5fb01279da1ffdc44). We package the Darwin and Linux compiled binary within the gem.

### Ruby Interface Files

Sorbet performs gradual typing and can easily be incorporated into large codebase, since it can auto-generate Ruby Interface (RBI) files for gems you include.

I found however that if your JRuby codebase calls out to Java-native code, the interpreter often-times fails to generate the RBI files.

> The technical reason is because the Java code is never officially required so that it never ends up being triggered through TracePoint

A pattern that worked well, was a hand-curated pattern for the creation of RBI files for the Java libraries the codebase uses.

```
tree ./sorbet
|------ config
|------ rbi
    |-------- java
    |   |---------- java_lang.rbi # this is the standard library
    |   |---------- org_eclipse_jgit.rbi
    |   |---------- org_apache_logging_log4j.rbi
    |-------------  org_slf4j.rbi
```

The naming convention is simple, it is the maven coordinates for a given Java package (replaced with underscores).

> 💡 There is an opportunity to include java_lang into [sorbet-typed](https://github.com/sorbet/sorbet-typed) at the very least.

The RBI files can be as strongly typed as you desire.
```ruby
# typed: strong
module Java
  module OrgEclipseJgitApiErrors
    class JGitInternalException < Exception; end
  end
end
```
### Naming Convention

Furthermore, there are a variety of ways in which to [call out to Java code](https://github.com/jruby/jruby/wiki/CallingJavaFromJRuby) from JRuby, but not all of them work for matching to the RBI files.

Consider these two approaches, which are _valid calling conventions_ into Java.
```ruby
# Option 1
org.foo.department.Widget

# Option 2
Java::OrgFooDepartment::Widget
```

Our codebase unfortunately **heavily** favored the former, which to Sorbet resembles method calls as opposed to the latter being module namespacing.

> 💡 There is an opportunity to fixup the code automatically via a Rubocop rule.

### Disabling Runtime Verification

This has perhaps been the most upsetting thing, the runtime verification was disabled in the codebase. I had discovered ([#2316](https://github.com/sorbet/sorbet/issues/2316)) there are some concurrency-bugs with it since the Sorbet team primarily works with CRuby which still has a global lock (GIL).

We've had to resort to the following in our codebase.
```ruby
# The Sorbet team develops strictly on MRI
# Discovered issue https://github.com/sorbet/sorbet/issues/2316
#
# To circumvent this, at the moment the `sorbet-runtime`
# is effectively changed to be T::Sig::WithoutRuntime
# https://github.com/sorbet/sorbet/blob/master/gems/sorbet/lib/t.rb
#
# We still leverage the static checker (srb tc) &
# using sig's as a form of documentation.
module T::Sig
  def sig(arg = nil, &blk); end
end
```

I am hoping with more attention and use by others in JRuby, this issue can be solved.

### Final Thoughts

Even without _runtime validation_, the **sig**'s use as a form of documentation far surpasses that of [YARDOC](https://yardoc.org/) and the _static checking_ continues to be helpful.

Without the ability to auto-generate RBI files for the code-base and the incorrect calling convention, we were not able to run **srb init** over the whole codebase.

Instead, we've taken a tactical approach of refactoring modules into their own gem and at that time raising the requirement that all new gems require Sorbet typing.

Adoption has definitely slowed, since the cost of refactoring code into a distinct gem is as high as rewriting it natively in Java/Kotlin.

I look forward to Ruby 3 and wider adoption of typing in the Ruby ecosystem.

> 😞 I am dismayed that Ruby 3 did not chose to allow inline type signatures. 