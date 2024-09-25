---
layout: post
title: 'Bazel Knowledge: Secret //external directory'
date: 2024-09-25 13:47 -0700
excerpt_separator: <!--more-->
---

Did you know Bazel has a _secret_ `//external` package that is created that contains
all the external repositories that are you added to _WORKSPACE.bazel_ or _MODULE.bazel_ ? 🤓

Let's start with a very minimal _WORKSPACE_ that pulls in the [GNU Hello](https://www.gnu.org/software/hello/) codebase.

```python
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "gnu_hello",
    urls = ["https://ftp.gnu.org/gnu/hello/hello-2.10.tar.gz"],
    strip_prefix = "hello-2.10",
    sha256 = "31e066137a962676e89f69d1b65382de95a7ef7d914b8cb956f41ea72e0f516b",
    build_file = "//third_party:gnu_hello.BUILD",
)
```

<!--more-->

We can query for this repository directly. You can provide any of the output types (i.e. build, label, graph) but I tend to find *build* useful to see how a transitive dependency might be defined.

```console
> bazel query //external:gnu_hello --output build

# /Users/fzakaria/code/playground/bazel/external-example/WORKSPACE:3:13
http_archive(
  name = "gnu_hello",
  urls = ["https://ftp.gnu.org/gnu/hello/hello-2.10.tar.gz"],
  sha256 = "31e066137a962676e89f69d1b65382de95a7ef7d914b8cb956f41ea72e0f516b",
  strip_prefix = "hello-2.10",
  build_file = "//third_party:gnu_hello.BUILD",
)
# Rule gnu_hello instantiated at (most recent call last):
#   /Users/fzakaria/code/playground/bazel/external-example/WORKSPACE:3:13 in <toplevel>
# Rule http_archive defined at (most recent call last):
#   /private/var/tmp/_bazel_fzakaria/33b8700aff3f6dee9e443aa52af0983c/external/bazel_tools/tools/build_defs/repo/http.bzl:382:31 in <toplevel>
```

🕵️ I wrote earlier about [WORKSPACE chunking]({% post_url 2024-08-29-bazel-workspace-chunking %}) that talks about how figuring out the version for a particular version can be challenging. Unfortunately, it's a known bug that querying `//external` gives you a different result than what's actually fetched. 😭

Finally, if we wanted to audit **all** repositories (i.e. `http_archive`) we are bringing in you can use `//external:*` or `//external:all-targets`.

```console
> bazel query //external:all-targets | head
Loading: 0 packages loaded
//external:WORKSPACE
//external:android/crosstool
//external:android/d8_jar_import
//external:android/dx_jar_import
//external:android/sdk
...
```

🟢 This is a great way to see which repositories are included by _default_ by Bazel.

This `//external` directory contains all the downloaded source information. This is useful to audit as you write the _BUILD_ files for the third-party package.

💁 A great tip is to create a symlink _external_ in the root of your project that maps to this "secret" directory.

```console
ln -s $(bazel info output_base)/external external
```

We can now easily view the GNU Hello source code as we write our build files.

```console
> ll external/gnu_hello
.rw-r--r--  94k fzakaria 16 Nov  2014 ABOUT-NLS
.rw-r--r--  44k fzakaria 16 Nov  2014 aclocal.m4
.rw-r--r--  593 fzakaria 19 Jul  2014 AUTHORS
drwxr-xr-x    - fzakaria 25 Sep 13:39 build-aux
.rwxr-xr-x  622 fzakaria 25 Sep 13:39 BUILD.bazel
.rw-r--r--  13k fzakaria 16 Nov  2014 ChangeLog
...
```

You can in fact see *all source* for external repositories you are building!

```console
> tree -d -L 1 external | head
external
├── apple_support~
├── apple_support~~apple_cc_configure_extension~local_config_apple_cc_toolchains
├── bazel_features~
├── bazel_features~~version_extension~bazel_features_globals
├── bazel_features~~version_extension~bazel_features_version
├── bazel_skylib
├── bazel_skylib~
├── bazel_tools -> /var/tmp/_bazel_fzakaria/install/b80b54a596e0fa4a6772cc7889abb086/embedded_tools
├── bazel_tools~cc_configure_extension~local_config_cc
...
```

> All these external repositories have their own _WORKSPACE_ file which allows bazel to avoid building them when you use `//...`

⚠️ This is why you might have run into errors previously if you tried to create an _external_ directory in your repository - [issues#4508](https://github.com/bazelbuild/bazel/issues/4508)