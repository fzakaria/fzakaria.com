---
layout: post
title: 'Bazel Knowledge: transition with style'
date: 2025-07-08 17:05 -0700
---

One of the more seemingly complex features of [Bazel](https://bazel.build) are [transitions](https://bazel.build/versions/6.0.0/extending/config#user-defined-transitions).

What even are "transitions" ? 🤨

They are the capability for Bazel to apply modifications to a rule, but more importantly, apply it transitively for every dependency as well.

```
                              root
                          (transtion = none)
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              A                                 C
     (transtion = X)                  (style = inherited: none)
              │
              B
  (transtion = inherited: X)
```

These modifications can be whatever values your rule supports and may be things like `java_language_version` or even `copts`.

As always, I learn by seeing & doing -- so let's write a very simple example similar to the Graphviz rules I wrote when [investigating depset]({% post_url 2025-05-20-bazel-knowledge-a-practical-guide-to-depset %}).

For our example, we will write a `text` rule -- we might want to use this rule to construct a _thesis_.

It might look like the following.

```python
text(
  name = "thesis",
  text = "This is my thesis.\n",
  includes = [":chapter1", ":chapter2"],
)

text(
  name = "chapter1",
  text = "Welcome to chapter 1.\n",
  includes = [":chatper1part1"],
)

text(
  name = "chatper1part1",
  text = "Welcome to chapter 1 part 1.\n",
)

text(
  name = "chapter2",
  text = "Welcome to chapter 2.\n",
)
```

This looks very suspicious like our Graphviz ruleset as I like simple text rules 🫠.

```python
"""Rule to produce a text file with specified content."""

load(":style.bzl", "StyleProviderInfo")
load(":transition.bzl", "style_transition")

TextProviderInfo = provider(
  doc = "A provider for text",
  fields = {
    "fragment": "The text fragment for this target.",
    "deps": "A depset of the dependencies of this target",
  },
)

def _text_impl(ctx):
  """Implementation function for the text rule."""

  fragment = ctx.attr.text
  # Create a file with the specified text content
  output_file = ctx.actions.declare_file(ctx.label.name + ".txt")
  ctx.actions.write(output = output_file, content = fragment)

  # Aggregate transitive dependencies using depset
  transitive_deps = depset(
    direct = ctx.attr.includes,
    transitive = [dep[TextProviderInfo].deps for dep in ctx.attr.includes],
  )

  return [
    DefaultInfo(files = depset([output_file])),
    TextProviderInfo(fragment = fragment, deps = transitive_deps),
  ]

text = rule(
  implementation = _text_impl,
  attrs = {
    "text": attr.string(),
    "includes": attr.label_list(
      doc = "List of files to include in the text",
      providers = [TextProviderInfo],
    ),
  },
  doc = "Produce some text.",
)
```

We can now `bazel build` our `//:thesis` target and we should get our expected result. 👌

```bash
> bazel build //:thesis
INFO: Invocation ID: eab79aac-86e7-4810-8465-abaca38f3b33
INFO: Analyzed target //:thesis (0 packages loaded, 6 targets configured).
INFO: Found 1 target...
Target //:thesis up-to-date:
  bazel-bin/thesis.txt
INFO: Elapsed time: 0.148s, Critical Path: 0.00s
INFO: 2 processes: 2 internal.
INFO: Build completed successfully, 2 total actions

> cat bazel-bin/thesis.txt
This is my thesis.
Welcome to chapter 1.
Welcome to chapter 1 part 1.
Welcome to chapter 2.
```

Now before we even make a transition, we must first specify a [build_setting](https://bazel.build/versions/6.0.0/extending/config#user-defined-build-settings) for us to modify via the transition. These are configurable values you can specify on the command-line or through `config_setting` which can control the build.

We want to create a `build_setting` that will control the _style_ of our produced text such as uppercase and lowercase.

`build_setting` are setup like a normal `rule` with a twist 🌀, they define a `build_setting` attribute.

```python
StyleProviderInfo = provider(fields = ["style"])

ALLOWED_STYLES = ["none", "upper", "lower"]

def _impl(ctx):
  raw_style = ctx.build_setting_value
  if raw_style not in ALLOWED_STYLES:
    fail(str(ctx.label) + " build setting allowed to take values {" +
         ", ".join(ALLOWED_STYLES) + "} but was set to unallowed value " +
         raw_style)
  return StyleProviderInfo(style = raw_style)

style = rule(
  implementation = _impl,
  build_setting = config.string(flag = True),
)
```

Now in a `BUILD.bazel` file we declare an instance of this setting with a desired name and give it a default.

```python
style(
    name = "style",
    build_setting_default = "none",
)
```

We now modify our rule slightly to take advantage of this setting. We add a new _hidden_ attribute `_style` which we
assign to our instance declared earlier and add a switch statement to handle the text accordingly.

```patch
@@ -14,7 +14,19 @@
 def _text_impl(ctx):
   """Implementation function for the text rule."""

-  fragment = ctx.attr.text
+  style = ctx.attr._style[StyleProviderInfo].style
+  fragment = ""
+  if style == "upper":
+    fragment = ctx.attr.text.upper()
+  elif style == "lower":
+    fragment = ctx.attr.text.lower()
+  elif style == "none":
+    fragment = ctx.attr.text
+  else:
+    fail("Unrecognized style: {}".format(style))
+    fragment += "".join(
+      [dep[TextProviderInfo].fragment for dep in ctx.attr.includes],
+    )
   # Create a file with the specified text content
   output_file = ctx.actions.declare_file(ctx.label.name + ".txt")
   ctx.actions.write(output = output_file, content = fragment)
@@ -38,6 +50,11 @@
       doc = "List of files to include in the text",
       providers = [TextProviderInfo],
     ),
+    "_style": attr.label(
+      default = Label("//:style"),
+      doc = "Style file to apply to the text",
+      providers = [StyleProviderInfo],
+    ),
   },
   doc = "Produce some text.",
 )
```

Now we can control the value with the command line using `--//:style=<value>` to modify **all** the produced text files.

```bash
> bazel build //:thesis --//:style=upper
INFO: Invocation ID: f1f9ee1b-0c2e-49d1-be9e-926948c5ec09
INFO: Analyzed target //:thesis (0 packages loaded, 5 targets configured).
INFO: Found 1 target...
Target //:thesis up-to-date:
  bazel-bin/thesis.txt
INFO: Elapsed time: 0.099s, Critical Path: 0.00s
INFO: 2 processes: 2 internal.
INFO: Build completed successfully, 2 total actions

> cat bazel-bin/thesis.txt
THIS IS MY THESIS.
WELCOME TO CHAPTER 1.
WELCOME TO CHAPTER 1 PART 1.
WELCOME TO CHAPTER 2.
```

What if I want _only a certain part_ of the thesis to be uppercased **and** I don't want to specify a style on every individual rule ? 🕵️

Aha! Now we finally come to the raison d'être for transitions. ✨

Let's create a `style` transition. Transitions are special `transition` objects that are attached to one or more `build_setting`.
They effectively toggle that setting depending on the logic of the transition for that particular rule and it's dependencies.

Our transition is pretty straightforward, it simply sets the value of our `build_setting` to the desired value.

```python
def _transition_impl(_, attr):
  if not attr.style:
    return {}
  return {"//:style": attr.style}

style_transition = transition(
  implementation = _transition_impl,
  inputs = [],
  outputs = ["//:style"],
)
```

We augment our `text` rule to now accept a `style` attribute but importantly, this is applied via the transition and not set by the rule.

```patch
@@ -50,11 +50,15 @@
       doc = "List of files to include in the text",
       providers = [TextProviderInfo],
     ),
+    "style": attr.string(
+      doc = "Style to apply to the text and all included files",
+    ),
     "_style": attr.label(
       default = Label("//:style"),
       doc = "Style file to apply to the text",
       providers = [StyleProviderInfo],
     ),
   },
+  cfg = style_transition,
   doc = "Produce some text.",
 )
```

Now let's say I want only _Chapter 1 and it's included parts (dependencies)_ to be all _uppercase_ -- I can accomplish this now with a transition.

```python
text(
    name = "chapter1",
    text = "Welcome to chapter 1.\n",
    includes = [
        ":chatper1part1",
    ],
    style = "upper",
)
```


```bash
> bazel build //:thesis
INFO: Invocation ID: d6bb1d4e-9d6b-412e-9161-7a75dae37ecc
INFO: Analyzed target //:thesis (0 packages loaded, 6 targets configured).
INFO: Found 1 target...
Target //:thesis up-to-date:
  bazel-bin/thesis.txt
INFO: Elapsed time: 0.125s, Critical Path: 0.00s
INFO: 2 processes: 2 internal.
INFO: Build completed successfully, 2 total actions

> cat bazel-bin/thesis.txt
This is my thesis.
WELCOME TO CHAPTER 1.
WELCOME TO CHAPTER 1 PART 1.
Welcome to chapter 2.
```

Wow okay that was pretty cool 🔥.

We can even mix and match the command-line flag and the transition.

In the following example, I set my `style` transition to be _lower_ and the command line flag to be _upper_.

```bash
> bazel build //:thesis --//:style=upper
INFO: Invocation ID: efadd96d-dab1-4771-a26d-9960ab0785b9
WARNING: Build option --//:style has changed, discarding analysis cache (this can be expensive, see https://bazel.build/advanced/performance/iteration-speed).
INFO: Analyzed target //:thesis (0 packages loaded, 7 targets configured).
INFO: Found 1 target...
Target //:thesis up-to-date:
  bazel-bin/thesis.txt
INFO: Elapsed time: 0.132s, Critical Path: 0.01s
INFO: 2 processes: 2 internal.
INFO: Build completed successfully, 2 total actions

> cat bazel-bin/thesis.txt
THIS IS MY THESIS.
welcome to chapter 1.
welcome to chapter 1 part 1.
WELCOME TO CHAPTER 2.
```

So far this looks pretty simple but you can get into some confusing setups by including the same target twice. For instance, I can do the following:

```python
text(
    name = "thesis",
    text = "This is my thesis.\n",
    includes = [
        ":chapter1",
        ":chatper1part1",
        ":chapter2",
    ],
)
```

I have for demonstrative purposes added `//:chapter1part1` to `//:thesis` -- even though it's a dependency of `//:chapter1`. When this happens in a "normal" Bazel setup, you don't have to recompile the duplicate target however here we have it applied _without the transition_.


```bash
> bazel build //:thesis
INFO: Invocation ID: 5e897401-b516-48fe-bb1b-225ab326fb35
INFO: Analyzed target //:thesis (0 packages loaded, 8 targets configured).
INFO: Found 1 target...
Target //:thesis up-to-date:
  bazel-bin/thesis.txt
INFO: Elapsed time: 0.134s, Critical Path: 0.00s
INFO: 2 processes: 2 internal.
INFO: Build completed successfully, 2 total actions

> cat bazel-bin/thesis.txt
This is my thesis.
WELCOME TO CHAPTER 1.
WELCOME TO CHAPTER 1 PART 1.
Welcome to chapter 1 part 1.
Welcome to chapter 2.
```

This is straightforward in this simple example but can be confusing if you are including binary artifacts such as Java bytecode. If your targets are expensive, you will notice that you are compiling the artifacts twice which _at best can cause slower builds_ and at worst case failures by including different artifacts for the same label twice in your closure.

👉 A great tip to avoid this headaches is to only apply transitions to "root" (i.e., `cc_binary` or `java_binary`) targets so that you never have to think about targets getting added twice.

Breaking down rules to simple text files makes learning some of the more complex corners of Bazel much more approachable, easier to reason through and faster to iterate  😂.
