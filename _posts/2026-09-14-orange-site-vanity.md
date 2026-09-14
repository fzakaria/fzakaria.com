---
layout: post
title: Orange Site Vanity
date: 2026-09-14 15:04 -0700
---

> "Curiosity is only vanity. We usually only want to know something so that we can talk about it"
> -- Blaise Pascal, _Pensées_

I enjoy writing. Most of the time I write for myself, or that is what I tell myself. The act of writing is me trying to deeply understand something and then recording my thought process.
It has paid dividends already as I have gone back numerous times to reference myself.

When I am honest with myself though, I deeply enjoy knowing when others read my work as well. Knowing that something I found interesting and insightful landed for someone else too is incredibly satisfying. If I could have helped someone understand something better while having done so for myself, pure joy.

The peak of that vanity seems to be when the [Hacker News](https://news.ycombinator.com/) crowd has deemed your content "worthy" to have made it on the _front page_.

There is a sort of inner satisfaction when someone else messages me to let me know one of my posts has made it onto Mount Olympus. I have for years added Google Analytics tracking to my site to understand engagement but I rarely went any deeper with the metrics to understand it, until now! 🤓

I have put my vanity on public display by collecting metrics pertaining to [my readership](/readership). 🪞

[![Summary tiles from my readership page: clicks from Google, total visits, and submission counts for Hacker News, Lobsters and Reddit](/assets/images/vanity_readership_photo.png)](/assets/images/vanity_readership_photo.png)

The numbers deflate the myth a little. As of writing, my writing has been submitted to Hacker News 127 times, and 26 of those reached the front page. Those 26 bought me 121 hours up there in total, under five hours each[^mean], and exactly one ever touched #1. Mount Olympus turns out to be crowded, and difficult to climb.

[^mean]: A mean, which I have [previously argued]({% post_url 2026-07-27-the-mean-means-nothing %}) means nothing.

Turns out building the vanity site was itself rewarding. I got a better understanding of the metrics I am collecting through Google Analytics & Search Console. I also tied my writings to submissions to [Reddit](https://reddit.com), [Lobsters](https://lobste.rs/) & [Hacker News](https://news.ycombinator.com/).

The data is fetched offline and periodically updated via a [GitHub Actions workflow](https://github.com/fzakaria/fzakaria.com/blob/942ebae88aa63ee3b8e5f76eabd5141b847080f7/.github/workflows/readership.yml) and included in the site, of course, as a Nix derivation.

Pascal was probably right. I tell myself I write to understand things, and that part is true, but I have now built a daily pipeline whose only job is to tell me who else was listening. Curiosity is only vanity. Mine now has a dashboard.
