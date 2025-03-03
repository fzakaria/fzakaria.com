---
layout: post
title: 404s and updated CSS
date: 2025-03-03 09:39 -0800
---
### CSS

I just _"revamped"_ the CSS of this site; ableit somewhat minimally.
Please let [me know](mailto:farid.m.zakaria@gmail.com) what you think: if you like it 🫶 or dislike it 👎.

My personal taste is I like very minimal CSS. This blog is modeled after [Drew Devault's blog](https://drewdevault.com/). I largely removed dead CSS cruft and improved readability (i.e. line spacing) slightly.

### 404s

You might have noticed some pages were giving **404** -- sorry about that.🙇

I had recently migrated [this blog](https://fzakaria) to deploy with GitHub actions. I didn't realize that Jekyll uses the local Time Zone for when to process the dates for pages and seems to ignore the Time Zone information I put in the frontmatter.

```markdown
---
layout: post
title: 404s and updated CSS
date: 2025-03-03 09:39 -0800
---
```

> Looks like there is an active issue [jekyll#issue9278](https://github.com/jekyll/jekyll/issues/9278)

GitHub actions' machines use UTC, _which makes total sense_, but it changed a lot of the dates of my pages unbeknownst to me as I was previously publishing from my laptop which was set to Pacific Time Zone.

I've since rectified this issue by being explicit about my Time Zone for the whole site.