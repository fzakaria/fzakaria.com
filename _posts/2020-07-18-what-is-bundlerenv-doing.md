---
layout: post
title: what is bundlerEnv doing?
date: 2020-07-18 22:41 -0700
excerpt_separator: <!--more-->
---

The [Nix wiki](https://nixos.wiki/) is _pretty great_ for a lot of technical content however it sometimes fails to gently walk users through how something works.

I've been doing some Ruby work as part of my day-to-day job and wanted to better understand Nix's approach to Ruby.

<!--more-->

If you Google "Nix Ruby", you'll inevitably find the [Packaging/Ruby](https://nixos.wiki/wiki/Packaging/Ruby) Nix wiki page.

The page walks the reader quickly through some _Nix incantations_, including calling a utility _bundix_ without much explanation. I hope the remaining portion of this post serves as a better guide & deeper understanding of what's happening.

## Setup

First let's setup the most simple bundler project, using only a single gem: [hello-world](https://rubygems.org/gems/hello-world/versions/1.2.0).

Let's initialize our directory to create the _Gemfile_ & add our _hello-world_ dependency.
```bash
bundle init
bundle add hello-world
```

Create an extremely _minimal_ Ruby script **main.rb**.
```ruby
require 'rubygems'
require 'bundler/setup'

require 'hello-world'
```

Finally let's run the utility [bundix](https://github.com/nix-community/bundix); with more explanation to follow. You may not have _bundix_ in your current environment, I found it useful just to run it directly from the _nix-shell_.

```bash
nix-shell -p bundix --run 'bundix -l'
```

**Bundix's** role is very simple. It traverses your _Gemfile.lock_, and generates a file _gemset.nix_ to be consumed by the subsequent Nix Ruby functions.

> _gemset.nix_ should be seen simply as the Nix transformation of the _Gemfile.lock_in the Nix language.

```nix
{
  hello-world = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "141r6pafbwjf8aczsilxxhdrdbbmdhimgbsq8m9qsvjm522ln15p";
      type = "gem";
    };
    version = "1.2.0";
  };
}
```

With all that _fanfare_ out of the way, time to write the  _shell.nix_ file.
Below is an extremely minimal _shell.nix_ to get started.

```nix
{ pkgs ? import <nixpkgs> { } }:
with pkgs;
with stdenv;
let
  app = bundlerEnv {
    name = "my-app";
    ruby = ruby;
    gemdir = ./.;
  };
in mkShell {
  name = "bundler-shell";
  buildInputs = [app bundix ruby];
}
```

> You can change the assignment of Ruby to any version you want.

At this point, things worked. Great! However I was pretty confused as to what was going on. Let's dig in!

**bundlerEnv** is defined in [ruby-modules/bundled-common/default.nix](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/ruby-modules/bundled-common/default.nix) in [nixpkgs](https://github.com/NixOS/nixpkgs).

One of the first thing the derivation does, is call a function to determine the *3* important files: _Gemfile_, _Gemfile.lock_ & _gemset.nix_.

Our example above didn't mention anything of the sort, so by [default](https://github.com/NixOS/nixpkgs/blob/98c9ae41de70a724517f64c0a39d4c5f68373a7c/pkgs/development/ruby-modules/bundled-common/functions.nix#L17-L27), it will find them according to the _gemdir_.

### gemset.nix

The _gemset.nix_ file is used to create _derivations_ for each gem referenced by downloading the source files into the _/nix/store_.

### bundleEnv

With all the gems downloaded, a _buildEnv_ (symlink of multiple derivations) is created.

```bash
/nix/store/ygzpgzxm25j6lfyad3zxr6rm2psahjlz-fzakaria.com/
|-- bin
|   |-- bundle
|   |-- bundler
|   `-- hello-world
`-- lib
    `-- ruby
        `-- gems
            `-- 2.6.0
                |-- bin
                |   |-- bundle -> /nix/store/niy7ivnph74z02kf8cvh9c4kz0i70nqp-bundler-2.1.4/lib/ruby/gems/2.6.0/bin/bundle
                |   |-- bundler -> /nix/store/niy7ivnph74z02kf8cvh9c4kz0i70nqp-bundler-2.1.4/lib/ruby/gems/2.6.0/bin/bundler
                |   `-- hello-world -> /nix/store/hym2fy3yiy706rm5hmwg6gmyrg8zipqm-ruby2.6.6-hello-world-1.2.0/lib/ruby/gems/2.6.0/bin/hello-world
                |-- build_info
                |-- doc
                |-- extensions
                |-- gems
                |   |-- bundler-2.1.4 -> /nix/store/niy7ivnph74z02kf8cvh9c4kz0i70nqp-bundler-2.1.4/lib/ruby/gems/2.6.0/gems/bundler-2.1.4
                |   `-- hello-world-1.2.0 -> /nix/store/hym2fy3yiy706rm5hmwg6gmyrg8zipqm-ruby2.6.6-hello-world-1.2.0/lib/ruby/gems/2.6.0/gems/hello-world-1.2.0
                `-- specifications
                    |-- bundler-2.1.4.gemspec -> /nix/store/niy7ivnph74z02kf8cvh9c4kz0i70nqp-bundler-2.1.4/lib/ruby/gems/2.6.0/specifications/bundler-2.1.4.gemspec
                    `-- hello-world-1.2.0.gemspec -> /nix/store/hym2fy3yiy706rm5hmwg6gmyrg8zipqm-ruby2.6.6-hello-world-1.2.0/lib/ruby/gems/2.6.0/specifications/hello-world-1.2.0.gemspec
```

The **gems** directory, has the symlinks to every gem declared in the Gemfile through the _gemset.nix_.

Finally a custom _bundler_ script is provided which makes sure to setup the correct _GEM_HOME_ and _Gemfile_ path.

```
#!/nix/store/arz0swkk693spw100q9d472816krr6x6-ruby-2.6.6/bin/ruby
#
# This file was generated by Nix.
#
# The application 'bundler' is installed as part of a gem, and
# this file is here to facilitate running it.
#

ENV["BUNDLE_GEMFILE"] = "/nix/store/czr32qd8zl96yzcpmdjik8malfnzfhdp-gemfile-and-lockfile/Gemfile"
ENV.delete 'BUNDLE_PATH'
ENV['BUNDLE_FROZEN'] = '1'

Gem.paths = { 'GEM_HOME' => "/nix/store/ygzpgzxm25j6lfyad3zxr6rm2psahjlz-fzakaria.com/lib/ruby/gems/2.6.0" }

$LOAD_PATH.unshift "/nix/store/niy7ivnph74z02kf8cvh9c4kz0i70nqp-bundler-2.1.4/lib/ruby/gems/2.6.0/gems/bundler-2.1.4/lib"

require 'bundler'
Bundler.setup()

load Gem.bin_path("bundler", "bundler")
```

Voila! You can run the Ruby application.

```bash
nix-shell --pure

bundle exec ruby main.rb
> hello world!
> this is hello world library
```