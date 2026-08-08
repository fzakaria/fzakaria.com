---
layout: post
title: Style Guide
permalink: /styleguide/
sitemap: false
noindex: true
---

Every element the site knows how to render, on one page, so CSS changes can be
checked in one place. Nothing links here and it is excluded from the sitemap,
the feed and search engines.

# Heading level one

Posts use `#` for their top-level sections, so an `h1` inside an article is a
section heading rather than the page title. On a wide screen the `§` mark hangs
out in the left gutter.

## Heading level two

Body copy is Newsreader. This paragraph exists to show the measure, the leading
and the colour of ordinary text. It runs long enough to wrap several times so
the line length can be judged honestly — roughly seventy characters, which is
where a serif of this contrast stays comfortable.

### Heading level three

#### Heading level four

Levels four through six drop to the monospace face, because at that depth a
heading is closer to a label than to a title.

##### Heading level five

###### Heading level six

## Inline elements

Ordinary text with **bold**, _italic_, **_bold italic_**, `inline code`, a
[link to another post]({% post_url 2026-02-18-linker-pessimization %}), an
[external link](https://gingerbill.org), ~~struck-through text~~, a
footnote,[^styleguide] H<sub>2</sub>O with a subscript, x<sup>2</sup> with a
superscript, and <kbd>Ctrl</kbd> + <kbd>C</kbd> as keys.

A longer run of inline code inside a sentence, such as
`readelf --relocs --wide libfoo.so | grep R_X86_64_TLSGD`, shows how a chip
behaves when it has to wrap at the end of a line.

## Blockquote

> A good tool is and ought to be invisible — striving to make such tools is the
> goal of a toolmaker.

> A quote can run to several paragraphs.
>
> This is the second one, so the internal rhythm is visible too.

## Margin notes

{: .aside}
This is an author-written aside. Write it as any block followed by
`{: .aside}`, and place it just _before_ the paragraph it belongs beside — a
float aligns with the point where it appears in the source.

Footnotes become margin notes automatically.[^second] On a screen too narrow
for a margin, both kinds fold back into the text column as indented asides.

## Alerts

> **Note**
> Alerts are a blockquote whose first line is a bold label, followed by
> `{: .alert .alert-note}`. They deliberately stay in the main column rather
> than the margin, because they are usually part of the argument.
{: .alert .alert-note }

> **Tip**
> `readelf -d` is faster than `objdump -p` when you only want the dynamic
> section.
{: .alert .alert-tip }

> **Important**
> The addend is applied before the overflow check, not after.
{: .alert .alert-important }

> **Warning**
> Rewriting an instruction in place only works when the replacement is exactly
> the same length.
{: .alert .alert-warning }

> **Caution**
> This will silently corrupt the `.eh_frame` section.
{: .alert .alert-caution }

## Lists

Unordered, with a nested level:

- Position-independent code
- Thread-local storage
  - Initial exec
  - Local dynamic
- Global offset table

Ordered:

1. Compile each translation unit
2. Emit relocations for anything not yet resolved
3. Let the linker patch the addresses
4. Discover the addend did not fit

Definition list:

Relocation
: A note left for the linker saying "fill this in once you know the address".

COMDAT
: A section group that lets the linker keep exactly one copy of a symbol that
was legitimately emitted many times.

## Code

A shell session:

```bash
gcc -std=c++17 -g -O0 -c library.cpp -o library.o
ld.lld -o main main.o library.o
```

C, to check keyword, type, string and number colours:

```c
#include <stdio.h>

static const char *kName = "libfoo.so";

int main(int argc, char **argv) {
  for (int i = 0; i < argc; i++) {
    printf("%d: %s\n", i, argv[i]);
  }
  return 0xdeadbeef & 0xff;
}
```

Nix:

```nix
{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  buildInputs = [pkgs.jekyll pkgs.nodejs_22];
  shellHook = ''
    echo "ready"
  '';
}
```

A diff, for the inserted and deleted line colours:

```patch
--- a/src/linker.c
+++ b/src/linker.c
@@ -1,5 +1,6 @@
 static bool fits_in_32(int64_t v) {
-  return v >= INT32_MIN && v <= INT32_MAX;
+  /* the addend is applied first, so check the sum */
+  return v >= INT32_MIN && v <= INT32_MAX && !overflowed;
 }
```

An unlabelled block, for output that is not really a language:

```
readelf: Warning: Section '.rela.text' has an invalid sh_link value
```

A very long line, to check horizontal scrolling inside the block rather than on
the page:

```console
$ readelf --wide --relocs ./build/x86_64-linux-gnu/libmkl_intel_lp64.so.2 | awk '$3 ~ /R_X86_64_PC32/ { print $1, $2, $3, $4, $5 }' | head -20
```

## Collapsible sections

<details markdown="1">
<summary markdown="span">vm.nix</summary>

```nix
{
  virtualisation.memorySize = 4096;
  virtualisation.diskSize = 16384;
  boot.kernelParams = ["console=ttyS0"];
}
```

</details>

<details markdown="1" open>
<summary markdown="span">An open section, holding prose rather than code</summary>

Not everything inside a `<details>` is code. This one holds ordinary
paragraphs, so the spacing inside the box can be checked too.

- with a list
- of two items

</details>

## Table

| Term          | Meaning                              | Value          |
| ------------- | ------------------------------------ | -------------- |
| **S**(ymbol)  | Address of the symbol                | ~200 MB        |
| **A** (ddend) | Constant baked into the object file  | `0x44000000`   |
| **P**osition  | Address of the instruction patched   | ~1,200 MB      |
| Result        | `S + A - P`, which must fit in 32bit | −2,062 MB      |

## Image

![A photo of my dog Moose](/assets/images/avatar-164.png)

An image fills the column. This one is 2336px wide and is served down-scaled to
whatever the column is worth at the reader's pixel density.

![A Bazel action graph, wide and short](/assets/images/action_graph_bazel.png)

### Capping an image's width

A tall image at full width is a screenful the reader has to scroll past. One
image can cap itself with `--image-width`, the same shape of escape hatch a
Graphviz figure gets from `--graphviz-height`. It stays centred at any width.

```markdown
![alt text](/assets/images/thing.png){: style="--image-width: 20rem"}
```

![The same Bazel action graph, capped at 20rem](/assets/images/action_graph_bazel.png){: style="--image-width: 20rem"}

`rem` resolves against `--root-max`, so `20rem` is 390px here. `_plugins/images.rb`
reads the cap off the tag and sizes the whole `srcset` ladder from it, so a
capped image is served a file that matches how small it is drawn rather than
one built for the full column.

## Horizontal rule

---

That is everything.

[^styleguide]: A footnote is lifted into the margin at build time by `_plugins/typography.rb`.
[^second]: A second note, to check that two in a row stack correctly rather than overlapping.
