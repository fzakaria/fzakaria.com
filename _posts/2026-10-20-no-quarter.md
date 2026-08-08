---
layout: post
title: "No quarter"
date: 2026-10-25 09:00 -0700
---

> **tl;dr** Every ecosystem has gaps everyone has learned to step around.
> The reason they survive is that closing one costs a weekend nobody has.
> That cost just collapsed. With a model doing the typing, the remaining
> work is knowing what correct looks like and writing the test that proves
> it. So stop stepping around. I took one seven-year-old gap, Ruby on Nix,
> and closed it: [gemlock](https://github.com/fzakaria/gemlock.nix).
{: .alert .alert-note }

This is in the nixpkgs manual, in the Ruby section, under
"Platform-specific gems":

> Right now, bundix has some issues with pre-built, platform-specific
> gems: bundix PR #68. Until this is solved, you can tell bundler to not
> use platform-specific gems and instead build them from source each
> time.

"Right now" was written in December 2021. The pull request it points to
was opened in October 2019 and closed, unmerged, in August 2026, with
"I no longer work with bundix". The advice underneath, `bundle config
set force_ruby_platform true`, means compiling nokogiri's libxml2 on
every laptop that touches the project. People did that for years.

I am not picking on nixpkgs. Every stack I have worked in has a
paragraph like that one. A build flag that only works on one platform. A
lockfile that needs a second lockfile generated next to it. A tool whose
README says "known issue" above a workaround older than the people
running it. We stopped seeing these as bugs and started seeing them as
weather.

## Why the gaps survived

A gap like the Ruby one does not survive because nobody understands it.
It survives because fixing it properly is three days of work and the
workaround is one line. Three days is a lot to ask of a volunteer, and
the one line is right there in the manual. So the manual grows another
paragraph, and the paragraph outlives its author.

That economics is gone. The three days of typing are now an afternoon
of directing and reading. I wrote the Nix side of a Bundler lockfile
reader, a port of RubyGems' platform matching rules, a dev shell, an app
builder and a test suite in two days, and most of that time was spent
deciding what correct meant, not producing code.

## The slop objection

The obvious reply is that code produced this way is slop, and a lot of
it is. Slop is what you get when nobody checks. The check is the work,
and it is the same work it always was.

Two things kept gemlock honest. The first is tests that ask the source
of truth rather than my memory. The platform rules in RubyGems are
subtle: `x86_64-linux-gnu` runs on a Ruby that reports `x86_64-linux`,
`universal-darwin` runs on any Darwin, `x86_64-linux` runs on musl and
`x86_64-linux-gnu` does not. I did not write those rules down from
memory. A Ruby script asks RubyGems itself about 36 gem platforms
against 11 hosts and writes the answers to a JSON file, and the Nix port
fails its test if it disagrees with RubyGems on a single row. That test
is what would have caught the earlier tool that installed an aarch64
binary on an x86_64 machine.

The second is Nix. Every example in the repository is built in a
sandbox with no network, on Linux and on macOS, on every push. A
precompiled binary either runs in there or the check fails. There is no
"works on my machine" because the machine is a function of the inputs.

With those two in place, the question "did the model get it right" has
an answer you can read off a CI page, and the age of the code's author
stops mattering.

## gemlock

The fix itself turned out to be small, because Ruby had already done the
hard part. Bundler 2.6 writes a `CHECKSUMS` section into `Gemfile.lock`,
a sha256 for every gem, and `--add-platform` records every precompiled
variant. That is every hash Nix needs. The second lockfile, `gemset.nix`,
existed only to hold hashes the first one now carries.

gemlock reads the lock in pure Nix, picks the variant for the host with
the RubyGems rules above, builds each gem with nixpkgs' own
`buildRubyGem`, patches precompiled binaries with `autoPatchelfHook`, and
hands you a shell:

```console
$ nix flake init -t github:fzakaria/gemlock.nix
$ nix run .#lock
$ nix develop
$ bundle exec rails server
```

Inside the shell, `bundle install` updates the lock and tells you to
re-enter. There is no import-from-derivation and no generated file to
forget.

[![dhh yelling about how little he is doing](/assets/images/dhh_yelling_about_doing_little.png)](/assets/images/dhh_yelling_about_doing_little.png)

The first push to GitHub failed on the macOS runner, and the failure is
the point of this post. The Rails example's lock listed `arm64-darwin`
under `PLATFORMS` and had no darwin build of sqlite3. The old reflex is
a note in the README: "lock on a Mac if you need darwin". Instead I
traced Bundler. `bundle lock --add-checksums --add-platform` resolves
the bundle while adding checksums, before it has applied the new
platform, so the platform is written down with nothing behind it. Most
projects never notice because a later pass fills the platform in by
accident, and one gem whose darwin build refuses Ruby 3.4 is enough to
stop that pass. gemlock's lock tool now detects the gap and repairs it,
and the one-line fix is in a pull request to RubyGems with a regression
spec that fails on their main branch.

That is what I mean by no quarter. The gap was found by a test, explained
by reading the code, closed locally and closed upstream, in an evening.
Seven years ago that was a weekend nobody had.

## The ask

Go look at the paragraph in your stack. The one that starts with "right
now" or "known issue" or "until this is fixed". Price it again at today's
rates. Then write the test that says what correct looks like, and close
it.
