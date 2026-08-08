---
layout: post
title: 'Review a pull request by booting it'
date: 2026-09-09 14:00 -0700
---

> **tl;dr;** [trynix-preview](https://github.com/marketplace/actions/trynix-preview) is a GitHub action that comments a link on a pull request which lets you boot the PR's build in the browser using [https://trynix.dev](https://trynix.dev). No servers, just browsers.
{: .alert .alert-note }

I ended my earlier [trynix post]({% post_url 2026-09-04-any-nix-package-live-in-your-browser %}) with a list of ideas I think we could accomplish now that we can boot arbitrary `/nix/store` paths in the browser. The most obvious one was to let a reviewer boot a pull request's build in the browser for testing, validation and feedback.

That is now real. 🤯

A demo is worth a 1000 words: here is a pull request ([PR#31](https://github.com/fzakaria/sqlelf/pull/31)) against my [sqlelf](https://github.com/fzakaria/sqlelf) project, <u>from a fork</u>, with the comment our action left on it:

[![A GitHub pull request comment from github-actions[bot]. It links "Boot this build in your browser", says a Linux VM boots in the tab and fetches this pull request's build from the cache, notes which commit it was built from, and has a collapsed "Store paths" section.](/assets/images/trynix-action-pr-comment.png)](/assets/images/trynix-action-pr-comment.png)

[Click the link](https://trynix.dev/?path=/nix/store/x0cz8aax3pcn0byrm1vjyidd17aizk6i-sqlelf&cache=https://sqlelf.cachix.org+sqlelf.cachix.org-1:MLnjolA9AsKscTOJKDSA%2BZAcgIK8BwZA574j4%2BCs2bg%3D) and a Linux machine boots in your tab with that PR's `sqlelf` on `PATH`.

You did not clone anything, you did not build anything. No servers, no SSH, no VPN, no Docker, no VM, no cloud. Just a browser and a link. 😈

## Gimme. Gimme. Gimme.

As with any GitHub action, it's just a few lines to add to your workflow.

_The caveat is that you must have built and cached the path already, so the action can link to it. The action does not build or cache anything._

```yaml
# Setup Cachix as our Nix cache.
- uses: cachix/cachix-action@v17
  with:
    name: sqlelf
    authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
# We build the pull request's code and push it to the cache, so the action can link to it.
- run: nix build .#default
- uses: fzakaria/trynix@v1
  with:
    cache: https://sqlelf.cachix.org
    publicKey: sqlelf.cachix.org-1:MLnjolA9AsKscTOJKDSA+ZAcgIK8BwZA574j4+Cs2bg=
    # You can have multiple attrs if you want to boot more than one path.
    attrs: .#default
```

The action publishes and builds nothing. Whatever already fills your cache keeps doing it, and the action's whole job is to simply provide the store paths via `nix eval` and hand the cache's URL and public key to the browser.

It is not Nix cache provider specific, but I do recommend [Cachix](https://cachix.org) because it is free for open source up to 5GiB.[^signup]

[^signup]: You should definitely sign up for Cachix but you can test this out without it since the free tier is very generous.

You can checkout my [trynix.yaml](https://github.com/fzakaria/sqlelf/blob/b6546b0dbcbc6ff4d8f07f820ee563a0dcab6fcd/.github/workflows/trynix.yaml) workflow for the full example. You have to set `allow-unsafe-pr-checkout: true` in the `actions/checkout` step because the workflow runs on a fork's pull request, and that has security implications.[^private-cache]

[^private-cache]: I recommend a private segregated cache for pull request builds, so that a fork cannot push to your main cache.

If that is not your cup of tea, there is a version where a maintainer types `/trynix` on the pull request which kicks off the workflow.

In either case, the workflow runs on the default branch and checks out the pull request's code, so a fork cannot edit the workflow that builds it.

## Game over?

Did I just upend all CI products by easily letting reviewers boot a PR?

Unfortunately, no. 🥲

The performance for large binaries is pretty bad. Even with many of the improvements I AI-assisted into the engine, large binaries can still take 1-2 minutes to execute.[^bench]

[^bench]: I added a benchmark page, [https://trynix.dev/bench/](https://trynix.dev/bench/), to the site with a lot of rich data on boot and run times for various applications.

Nevertheless, this is still a pretty amazing workflow and showcases the power of Nix.

Maybe as we get closer to AGI, our AI overlords will be able to optimize the engine to execute large binaries in a few seconds, but for now, the action is best suited for small to medium-sized binaries.
