---
layout: post
title: nix-build in under 100 lines
date: 2026-06-21 10:00 -0700
---

I've said before that [Nix is a lie]({% post_url 2026-03-07-nix-is-a-lie-and-that-s-ok %}), and that underneath the ceremony Nix is really just an [Input Output Machine]({% post_url 2026-06-05-the-guix-nix-abomination-leveraging-guix-derivations-in-nix %}).

The `nix` daemon _feels_ like a black box. You type `nix build` and somewhere behind a Unix socket a privileged process does inscrutable things, and out the other end pops a path in `/nix/store`. 🪄

What if I told you the part everyone thinks is magic and that turning a derivation into a store path is nearly an _exec_ ?

Let's reimplement `nix-build` in under 100 lines of Go.

First off, What is a derivation, really?

A derivation (`.drv`) is just a build plan. Let's instantiate the most boring one imaginable.

```nix
# hello.nix
derivation {
  name = "hello";
  system = builtins.currentSystem;
  builder = "/bin/sh";
  args = [ "-c" "echo 'Hello World' > $out" ];
}
```

```console
$ nix derivation show $(nix-instantiate hello.nix)
```

```json
{
  "derivations": {
    "gifgxsqfsjg8pxna1kv0nbzz1zvivs0b-hello.drv": {
      "args": [
        "-c",
        "echo 'Hello World' > $out"
      ],
      "builder": "/bin/sh",
      "env": {
        "builder": "/bin/sh",
        "name": "hello",
        "out": "/nix/store/ddmbmrgzcqqp0b8i9gmzav8zs8ch3176-hello",
        "system": "x86_64-linux"
      },
      "inputs": { "drvs": {}, "srcs": [] },
      "name": "hello",
      "outputs": {
        "out": {
          "path": "ddmbmrgzcqqp0b8i9gmzav8zs8ch3176-hello"
        }
      },
      "system": "x86_64-linux",
      "version": 4
    }
  },
  "version": 4
}
```

That's the _whole_ thing. A program to run (`builder` + `args`), an environment (`env`), the outputs it must produce, and the other derivations it depends on (`inputDrvs`), which in this case is empty. No magic 🪄.

So "realising" a derivation is just four steps:

1. Realise its `inputDrvs` first recursively. This _is_ the build graph.
2. Scrub the environment down to a known set of variables.
3. Set `$out` to the store path the build must create.
4. `exec` the builder and check it produced `$out`.


Here is the whole program in Go, in less than 100 lines (excluding comments 😉).
You can find the source [here](https://gist.github.com/fzakaria/1be0657cc5f10df5e45d4ff1574b0273).

> **Note**
> I _cheated_ a tiny bit and rather than writing a parser for Nix's [ATerm format](https://nix.dev/manual/nix/2.25/protocols/derivation-aterm), I leveraged `nix show derivation` to get the JSON equivalent.
{: .alert .alert-note }

<details markdown="1">
<summary markdown="span">build.go</summary>
```go
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const store = "/nix/store"

type drv struct {
	Args    []string          `json:"args"`
	Builder string            `json:"builder"`
	Env     map[string]string `json:"env"`
	Inputs  struct {
		Drvs map[string]any `json:"drvs"`
	} `json:"inputs"`
	Outputs map[string]struct {
		Path string `json:"path"`
	} `json:"outputs"`
}

func exists(path string) bool { _, err := os.Stat(path); return err == nil }

// storePath makes a store path absolute; Nix's JSON uses bare basenames.
func storePath(p string) string {
	if strings.HasPrefix(p, "/") {
		return p
	}
	return store + "/" + p
}

// loadDrv shells out to Nix to turn a .drv into JSON, then decodes it.
func loadDrv(path string) (error, drv) {
	data, err := exec.Command("nix", "--extra-experimental-features", "nix-command",
		"derivation", "show", path).Output()
	if err != nil {
		return err, drv{}
	}
	var doc struct {
		Derivations map[string]drv `json:"derivations"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return err, drv{}
	}
	for _, d := range doc.Derivations {
		return nil, d // exactly one entry: the derivation we asked for
	}
	panic("no derivation found for " + path)
}

// realise ensures the derivation's output exists, building its inputs first,
// and returns the default output's store path.
func realise(path string) (error, string) {
	err, d := loadDrv(path)
	if err != nil {
		return err, ""
	}
	out := storePath(d.Outputs["out"].Path)
	if exists(out) {
		return nil, out // already built (this also memoises shared dependencies)
	}
	for dep := range d.Inputs.Drvs {
		realise(storePath(dep)) // recurse: dependencies before dependents
	}

	fmt.Fprintln(os.Stderr, "building", out)
	tmp, err := os.MkdirTemp("", "simple-nix-")
	if (err != nil) {
		return err, ""
	}
	defer os.RemoveAll(tmp)

	// The build's entire environment: a few fixed vars, the derivation's own
	// attributes, and one var per output (this is where $out comes from).
	// These fixed variables and their values are specified by the Nix manual:
	// https://github.com/NixOS/nix/blob/f8bb823a23bf6d62f4c8feb792a77702d7a49fe1/doc/manual/source/store/building.md?plain=1#L154
	env := map[string]string{
		"PATH": "/path-not-set", "HOME": "/homeless-shelter",
		"NIX_STORE": store, "NIX_BUILD_TOP": tmp,
		"TMPDIR": tmp, "TEMPDIR": tmp, "TMP": tmp, "TEMP": tmp,
	}
	for k, v := range d.Env {
		env[k] = v
	}
	for name, o := range d.Outputs {
		env[name] = storePath(o.Path)
	}

	cmd := exec.Command(d.Builder, d.Args...)
	cmd.Dir, cmd.Stdout, cmd.Stderr = tmp, os.Stderr, os.Stderr
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}

	if err := cmd.Run(); err != nil {
		return err, ""
	}

	if !exists(out) {
		panic(fmt.Sprintf("builder did not produce %s", out))
	}
	return nil, out
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: simple-nix <file.drv> ...")
		os.Exit(2)
	}
	for _, arg := range os.Args[1:] {
		fmt.Println(realise(arg))
	}
}
```
</details>

That's it. Does it work?

```bash
$ go build -o simple-nix .

$ ./simple-nix $(nix-instantiate hello.nix)
building /nix/store/ddmbmrgzcqqp0b8i9gmzav8zs8ch3176-hello
/nix/store/ddmbmrgzcqqp0b8i9gmzav8zs8ch3176-hello

$ cat /nix/store/ddmbmrgzcqqp0b8i9gmzav8zs8ch3176-hello
Hello World
```

We can even build a real-world derivation.

```bash
$ ./simple-nix $(nix eval nixpkgs#hello --raw)

Using versionCheckHook
Running phase: unpackPhase
unpacking source archive /nix/store/wj7phsmi7ncidl8k00p489krqss7n9sd-hello-2.12.3.tar.gz
source root is hello-2.12.3
setting SOURCE_DATE_EPOCH to timestamp 1773804383 of file "hello-2.12.3/ChangeLog"
Running phase: patchPhase
Running phase: updateAutotoolsGnuConfigScriptsPhase
Updating Autotools / GNU config script to a newer upstream version: ./build-aux/config.sub
Updating Autotools / GNU config script to a newer upstream version: ./build-aux/config.guess
...
```

So what _is_ missing?

Quite a lot, honestly **but** none of it is the part that turns a derivation into a path.

* **Sandboxing**: Nix runs the builder in a mount/network/PID namespaces for security and hermiticity.
* **The database**: Nix records every valid path and its references in a SQLite db. We just check if the file exists.
* **Substitution**: Nix asks a binary cache if the derivation was already built.
* **Everything else**: Multiple output paths, support for fixed-output derivations (`fetchurl`), garbage collection, etc.

The beauty of Nix is the derivation is a pure function. Getting the store path is not magic. It's `exec` with a clean environment. Everything else, _mostly_ is bookkeeping and security.
