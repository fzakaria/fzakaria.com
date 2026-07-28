---
layout: post
title: The mean means nothing
date: 2026-07-27 09:00 -0700
---

I was recently trying to validate some performance improvements related to `lld` at `$DAYJOB` and it was a little frustrating to see the improvements in our benchmarks but not in the live-production dashboards.

Having come from a background working on web-services, I was used to looking at individual time-series dashboards, sometimes over a few percentiles, and I was expecing to see some noticeable change but the data seemed too noisy to make any conclusions.

Turns out a colleague had also faced similar issues when trying to evaluate build-speed improvements. There are lots of variables that can affect the build: cold-cache, incremental, local, remote, etc. and the build times can vary wildly depending on the state of the system and the workload. She ended up leveraging a cummulative distribution function (CDF) to visualize the data and it was a revelation to me.

This led me to explore a few other different ways to visualize data, in addition to the CDF, and how a single image or statistic is often not enough to tell the whole story. This post will walk through a single _synthetic_ dataset and show how different visualizations can tell different stories about the same data. The goal is to convince you to _look_ at your data and not just summarize it with a single number.


Everything below comes from one synthetic dataset with a fixed seed. The
full script can be found [here](https://gist.github.com/fzakaria/17c72f0eddc0f10469e008e67e1385cc); it is a single file with a
`nix-shell` shebang, so you can drop it in a gist, `chmod +x`, and reproduce
every figure exactly as long as you are using [nix](https://nixos.org/).

> **Note**
> I leverage AI to help generate the data and charts in this post for the story.
> If that bugs you, sorry. 🤷
{: .alert .alert-note }

### The rollout that "made it worse"

Here is the setup: We operate a typical web-service and we rolled out a new caching tier over a week, hoping to cut request latency.

The change is fully deployed, and the latency dashboard that plots the **mean** looks like this:

![Bar chart of mean latency before and after the rollout; after is 122 ms, about 9% higher than the 112 ms before](/assets/images/latency-1-mean.svg)

Mean latency went _up_, from 112 ms to 122 ms. ☹️

A SEV is cut, we revert the change and write the postmortem. Right? 🤔

### One number, four stories

It's often good practice especially for web-services to look at various percentiles, especially the tail end of the distribution like the p95 and p99. 


| statistic     | before | after  | change   |
| ------------- | ------ | ------ | -------- |
| mean          | 112 ms | 122 ms | **+9%**  |
| p50 (median)  | 99 ms  | 54 ms  | **−46%** |
| p95           | 224 ms | 454 ms | **+103%** |
| p99           | 309 ms | 678 ms | **+119%** |

Now we have a problem, and the problem is that _everyone is right_. The mean says
the change is a mild regression. The median (p50), says the
change is a big-win, the typical request got **nearly twice as fast**. The p99
says it's a SEV, the worst requests more than doubling.

The mean and the median, computed from the very same numbers, point in _opposite
directions_.

{: .aside}
Engineers are often taught to be data-oriented, but often it's easy to cherry-pick the statistic that supports your argument.


### Look at the shape

The next basic thing you can do with a distribution is plot its shape.
Here are the two latency distributions, before and after, as densities:

![Density plot of latency before and after; before is a single hump, after has a tall fast peak plus a second hump out in the slow region](/assets/images/latency-2-density.svg)

There it is. 🤓☝️ The "before" is **one tidy hump**. The "after" is **two humps**.

This already explains the earlier contradiction but it's a bit tricky to visualize correctly. The shape depends on a smoothing parameter we chose, the two fills muddy each other where they overlap, and it's genuinely hard to read a _percentile_ off it. I can see there are two populations; I can't easily see where the median went.

### The best chart you're not using

The cumulative distribution function (CDF) answers one question for every percentile at once: **what fraction
of requests came in at or below _x_ milliseconds?**

![CDF of latency before and after; the two step curves cross near 140 ms](/assets/images/latency-3-cdf.svg)

CDFs are an extremely easy way to visualize multiple percentiles in a single chart. Depending on the curve, we can understand how the request latency is distributed across the entire population.

I found it incredibly useful to then plot the "before" and "after" CDFs on the same chart to see how they compare. You can then visualize the shifts at various percentiles and understand how the change affected the entire population.

In our story, the "after" curve has shifted left for request latencies below 140ms. That means more requests are finishing faster than before. The "after" curve is higher than the "before" curve to the right of 140ms which means more requests are finishing slower than before. The two curves cross at ~140ms which is the tipping point where the change goes from being a win to a loss.

> **Tip**
> Two CDFs that cross are the unmistakable signature of a change that _no single percentile can summarize_, because the sign of the effect depends on which percentile you ask.
{: .alert .alert-tip }


### Who won, and by how much

The CDF tells us _that_ the effect changes sign: faster or slower. The obvious next question is _by
how much_, at each point in the distribution. We can plot for
every percentile _p_, the after-latency minus the before-latency, known as the
**shift function**.

![Shift function: change in latency at each percentile, negative up to about p76 then rising steeply into the tail](/assets/images/latency-4-shift.svg)

Below the zero line the change is faster; above it, slower. 
We can visualize the magnitude of the change at each percentile.

### The regression was there all along

So far we have looked at two frozen snapshots, before and after. Rollouts though are often not instant. In this story, we rolled out the new caching tier over a week, ramping from 0% to 100% of traffic.

What did each _day_ look like? Stack one distribution per day and you get a **ridgeline**:

![Ridgeline plot of latency for each rollout day on a log axis; a second peak grows in as the rollout ramps from 0 to 100 percent](/assets/images/latency-5-ridge.svg)

We can now visualize the regression emerging over time. We can see the main peak (the fast requests) sliding left as the rollout progresses, and a second peak (the slow requests) emerging on the right. The median is dropping, but the slow requests are quietly growing in number and latency.

{: .aside}
The x-axis here is logarithmic. Latency is roughly lognormal, and on a linear
axis the fast peak is a tall spike next to an invisible smear; the log axis is
what lets both humps read as humps.

We can do something similar, squeezed into a single grid, as a **heatmap**. One column per day, colour for how much traffic lands at each latency:

![Heatmap of latency density by rollout day; a dark main band descends while a second band appears higher up as the rollout progresses](/assets/images/latency-5b-heatmap.svg)

Whichever you prefer, the point is the same: any aggregate computed over the
whole week would have blended these seven very different days into one muddy
number and hidden the trend completely.

### The bimodality had a cause

We've now thoroughly established _what_ happened. The next question is _why_.
This is in fact very similar to `$DAYJOB` where I had to cut the data by binary sizes (i.e. >50MiB) to observe the bimodality in the latency distribution.

In our story, new tier either serves a request from cache (a **hit**) or falls through to the backend with an extra hop (a **miss**). We can split the "after" requests by that property and draw a CDF for each:

![Filtered CDF of after-rollout latency split by cache hit and miss, with the baseline as a dashed reference; two clean unimodal curves flank it](/assets/images/latency-6-filtered.svg)

Conditioned on cache outcome, each population is unimodal again. 

We can easily see that cache **hits** are faster than the old baseline as they are shifted left.

Cache **misses** pay for the extra hop and land far to the right.

### Why _those_ requests?

"Some requests miss the cache" is a mechanism, but it isn't yet a cause. _Which_
requests miss, and why? 

Each request carries one more field I haven't used yet: its **response size**.

A cache holds small, hot objects; big ones get evicted or never fit.
We can plot the latency against the response size, and colour each point by whether it was a cache hit or miss. We can also add a density to each margin to see how the two populations are distributed along each axis: a **jointplot**:

![Jointplot of latency versus response size for after traffic, coloured by cache outcome; cache hits cluster small-and-fast, cache misses cluster large-and-slow, with marginal densities showing the split on each axis](/assets/images/latency-7-joint.svg)

We can see two clean population clusters: small-and-fast (cache hits) and large-and-slow (cache misses). It's clear that the bimodality in the latency distribution is caused by the bimodality in the response size distribution.

We now have something actionable: raise the cache's max object size, or split the big responses. 🔥

### A graph is worth a thousand numbers

Often a single panel or graph is too small to tell the whole story at best. At worst, it can be misleading. It is beneficial to have multiple views of the same data to understand the full story.

I was especially impressed with the way the CDF can convey the entire distribution in a single chart especially when comparing what might appear to be multiple populations.

> "Do not trust any statistics you did not fake yourself."
> -- Winston Churchill