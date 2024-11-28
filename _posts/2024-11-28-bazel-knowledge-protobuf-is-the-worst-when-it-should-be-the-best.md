---
layout: post
title: 'Bazel Knowledge: Protobuf is the worst when it should be the best'
date: 2024-11-28 14:07 -0800
excerpt_separator: <!--more-->
---

Bazel has always had support for [protocol buffers (protobuf)](https://protobuf.dev/) since the beginning.
Both being a Google product, one would think that their integration would be seamless and the best experience.
Unfortunately, it's some of the worst part of the user experience with Bazel I've found. 😔

Let's start with the basics; _What rule should I adopt for protobufs?_

Well first I Google _"Bazel protobuf"_ and land on the [protobuf reference page](https://bazel.build/reference/be/protocol-buffer) for Bazel
which states:

> If using Bazel, please load the rule from https://github.com/bazelbuild/rules_proto.

One may think the sensible [rules_proto](https://github.com/bazelbuild/rules_proto) is a good starting
point but the _README.md_ states:

> This repository is **deprecated**...we decided to move the implementation of
> the rules together with proto compiler into protobuf repository.

OK...🤔

Let's go check [protobuf](https://github.com/protocolbuffers/protobuf).

The _README.md_ claims one can install one of two ways by inserting the following
into your _MODULE.bazel_ without much explanation as to the difference. 🤷‍♂️

```python
bazel_dep(name = "protobuf", version = <VERSION>)
#
# or
#
bazel_dep(name = "protobuf", version = <VERSION>,
          repo_name = "com_google_protobuf")
```

I decide to audit the source to see what's going on.
You quickly land on the [rule definition](https://github.com/protocolbuffers/protobuf/blob/cbecd9d2fa1d7187cca63a8c18838e87a4f613ec/bazel/private/bazel_proto_library_rule.bzl#L239)
for _proto_library_ and see the following documentation for the rule. 🤦

```python
proto_library = rule(
    _proto_library_impl,
    # TODO: proto_common docs are missing
    # TODO: ProtoInfo link doesn't work and docs are missing
    doc = """
<p>If using Bazel, please load the rule from
<a href="https://github.com/bazelbuild/rules_proto">
https://github.com/bazelbuild/rules_proto</a>.
```

Where is the **protoc** (protobuf compiler) ultimately coming from for the rule?
I notice these interesting snippets in the rule.

```python
toolchains.if_legacy_toolchain({
        "_proto_compiler": attr.label(
            cfg = "exec",
            executable = True,
            allow_files = True,
            default = configuration_field("proto", "proto_compiler"),
```

```python
_incompatible_toolchain_resolution =
    getattr(native_proto_common,
            "INCOMPATIBLE_ENABLE_PROTO_TOOLCHAIN_RESOLUTION", False)

def _if_legacy_toolchain(legacy_attr_dict):
    if _incompatible_toolchain_resolution:
        return {}
    else:
        return legacy_attr_dict
```

Turns out that _INCOMPATIBLE_ENABLE_PROTO_TOOLCHAIN_RESOLUTION_ is set from the command line [ref](https://bazel.build/reference/command-line-reference#flag--incompatible_enable_proto_toolchain_resolution).

> --[no]incompatible_enable_proto_toolchain_resolution default: "false"
> If true, proto lang rules define toolchains from protobuf repository.
> Tags: loading_and_analysis, incompatible_change

I don't have that in my `.bazelrc` so let's ignore it.
That means our `_proto_compiler` is coming from `configuration_field("proto", "proto_compiler")`.

You then search the [bazelbuild/bazel](https://github.com/bazelbuild/bazel/blob/a3f0cebd35989e120d5cdaf7882b4e93df82e590/src/main/java/com/google/devtools/build/lib/rules/proto/ProtoConfiguration.java#L68) source to find where it's defined.
```java
@Option(
    name = "proto_compiler",
    defaultValue = ProtoConstants.DEFAULT_PROTOC_LABEL,
    converter = CoreOptionConverters.LabelConverter.class,
    documentationCategory = OptionDocumentationCategory.UNCATEGORIZED,
    effectTags = {OptionEffectTag.AFFECTS_OUTPUTS, OptionEffectTag.LOADING_AND_ANALYSIS},
    help = "The label of the proto-compiler.")
public Label protoCompiler;
```

```java
// The flags need to point to @bazel_tools, because this is a canonical repo
// name when either bzlmod or WORKSPACE mode is used.
/** Default label for proto compiler.*/
public static final String DEFAULT_PROTOC_LABEL
        = "@bazel_tools//tools/proto:protoc";
```

Chasing down the ultimate target in the defining [BUILD](https://github.com/bazelbuild/bazel/blob/3d528ac42cce1a71d8358b57cdbe4b3e743bd307/tools/proto/BUILD#L15)
file you discover it's an alias to `"@com_google_protobuf//:protoc"`.

```python
# Those aliases are needed to resolve the repository name correctly in both
# bzlmod and WORKSPACE mode. They are resolved in the namespace of MODULE.tools

alias(
    name = "protoc",
    actual = "@com_google_protobuf//:protoc",
)
```

😲 So we discovered why `com_google_protobuf` may want to be the `repo_name` in the `bazel_dep` rule.
The repository name `com_google_protobuf` is _hard-coded_ within the Bazel source code for the location
to discover the protoc compiler.

> You'll have to trust me that the resolution to the compiler for the language toolchains
> such as _java_proto_library_ is the same as well; just way more obfuscated.

The rabbit hole only goes deeper if you consider [gRPC](https://grpc.io/), other languages and then having to manage
various runtimes (compatibility matrix) for your language across your codebases if they leave source of truth.

I feel like we discovered a lot but didn't really learn or accomplish anything. 😩

### Brighter Future?

Lots of interesting work is being done by the [rule-authors SIG](https://bazel-contrib.github.io/SIG-rules-authors/proto-grpc.html) (Special Interest Group).

> That doc has a great in-depth overview of the current _state of affairs_.

The most notable changes on the horizon are migrating protocol buffers to Bazel's toolchain mechanism.
This should make binding to `protoc` look like other toolchains in Bazel and no longer special case
`com_google_protobuf`.

> What are toolchains? In my mind effectively the capability to late bind a label to a target.

To me, a simple immediate improvement would be fixing the documentation around _rules_proto_ and
having a more clear path on how to adopt Bazel given some constraint (i.e. Bazel >= 7.0).

> The [latest blog post](https://blog.bazel.build/2017/02/27/protocol-buffers.html) from Bazel on protobuf
> is from 2017!

The work [Aspect Build](https://www.aspect.build/) is doing to improve the protobuf ecosystem is great as well.
Their video series on [_"Never Compile Protoc Again"_](https://www.youtube.com/watch?v=s0i_Ra_mG9U) is excellent
and served as a great resource for my previous post on [minding your PATH]({% post_url 2024-10-23-bazel-knowledge-mind-your-path %}).
