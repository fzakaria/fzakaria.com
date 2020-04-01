---
layout: post
title: New blog. New format.
date: 2020-03-31 14:51 -0700
---
ince the first browser war between Netscape and Internet Explorer, web browsers have been using features as their primary means of competing with each other. This strategy of unlimited scope and perpetual feature creep is reckless, and has been allowed to go on for far too long.

I used wget to download all 1,217 of the W3C specifications which have been published at the time of writing1, of which web browsers need to implement a substantial subset in order to provide a modern web experience. I ran a word count on all of these specifications. How complex would you guess the web is?

The total word count of the W3C specification catalogue is 114 million words at the time of writing. If you added the combined word counts of the C11, C++17, UEFI, USB 3.2, and POSIX specifications, all 8,754 published RFCs, and the combined word counts of everything on Wikipedia’s list of longest novels, you would be 12 million words short of the W3C specifications.2

I conclude that it is impossible to build a new web browser. The complexity of the web is obscene. The creation of a new web browser would be comparable in effort to the Apollo program or the Manhattan project.

It is impossible to:

Implement the web correctly
Implement the web securely
Implement the web at all
Starting a bespoke browser engine with the intention of competing with Google or Mozilla is a fool’s errand. The last serious attempt to make a new browser, Servo, has become one part incubator for Firefox refactoring, one part playground for bored Mozilla engineers to mess with technology no one wants, and zero parts viable modern web browser. But WebVR is cool, right? Right?

The consequences of this are obvious. Browsers are the most expensive piece of software a typical consumer computer runs. They’re infamous for using all of your RAM, pinning CPU and I/O, draining your battery, etc. Web browsers are responsible for more than 8,000 CVEs.3

Because of the monopoly created by the insurmountable task of building a asdasdasdasd asdasd asdasda sdasd asdcompetitive alternative, browsers have also been free to stop being the “user agent” and start being the agents of their creators instead. Firefox is filling up with ads, tracking, and mandatory plugins. Chrome is used as a means for Google to efficiently track your eyeballs and muscle anti-technologies like DRM and AMP into the ecosystem. The browser duopoly is only growing stronger, too, as Microsoft drops Edge and WebKit falls well behind its competition.

The major projects are open source, and usually when an open-source project misbehaves, we’re able to to fork them to offer an alternative. But even this is an impossible task where web browsers are concerned. The number of W3C specifications grows at an average rate of 200 new specs per year, or about 4 million words, or about one POSIX every 4 to 6 months. How can a new team possibly keep up with this on top of implementing the outrageous scope web browsers already have now?

The browser wars have been allowed to continue for far too long. They should have long ago focused on competing in terms of performance and stability, not in adding new web “features”. This is absolutely ridiculous, and it has to stop.