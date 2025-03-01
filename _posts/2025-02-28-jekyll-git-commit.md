---
layout: post
title: Jekyll Git commit
date: 2025-02-28 21:23 -0800
---

I wanted to include a hyperlink on my blog that included the commit it was published with.

Being a _newbie_ in Jekyll, I did what anyone would do and asked the Internet which pointed me towards: [jekyll-github-metadata](https://github.com/jekyll/github-metadata).

This plugin worked well enough, except it needs network access on builds which didn't work when I wanted to build my software with [Nix](https://nixos.org).

There was no way to disable the network calls if I knew all the Git information I needed ahead of time.

Let's do something simpler! We can write an incredibly simple Jekyll plugin that will provide a variable with the _commit_hash_ for use in our pages. Place the following file in `_plugins/git_commit.rb`.

```ruby
module Jekyll
  class GitCommitGenerator < Generator
    priority :highest

    def generate(site)
      commit_hash = ENV['JEKYLL_BUILD_REVISION'] ||
            `git rev-parse HEAD`.strip
      site.config['commit_hash'] = commit_hash
    end
  end
end
```

I have also included an environment variable `JEKYLL_BUILD_REVISION`, which if present, has the plugin short-circuit.

Our _view commit source_ hyperlink is now pretty simple to cook up.

```html
<p>
  <a href="https://github.com/org/repo/tree/{% raw %}{{ site.commit_hash }}/{{ page.path }}{% endraw %}"
  >Improve this page @ {% raw %}{{ site.commit_hash | slice: 0, 7 -}}{% endraw %}
  </a>
</p>
```

🥳 Simplified our build by removing dependencies and removed the necessity of having network access to build our blog.