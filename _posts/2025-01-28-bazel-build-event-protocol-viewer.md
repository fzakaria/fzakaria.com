---
layout: post
title: 'Bazel: Build Event Protocol Viewer'
date: 2025-01-28 14:11 -0800
excerpt_separator: <!--more-->
---

> Visit [https://visible.build](https://visible.build) to try a _client-side only_ build event protocol viewer 🎉.
>
> You can find the MIT licensed source code [here](https://github.com/fzakaria/bazel-build-event-viewer/).

I consider myself a "backend" engineer.

Although I have dabbled in UI frameworks professionally (.NET and the occasional JavaScript) -- I rarely work on the front-end visual portion of a product.

My knowledge of HTML/CSS has been forever cemented since I learnt the technology in my teens -- culminating in the ultimate personal expression of `<marquee>` on GeoCities.

Revisiting front-end development for occasional projects has always been stress-inducing. The pace of change in the ecosystem is fast from the toolset to even the language (👋 TypeScript).

<!--more-->

Nevertheless, this last weekend I was lazer focused on a single goal.

_To build a front-end only website to visualize the [Build Event Protocol (BEP)](https://bazel.build/remote/bep) for Bazel_ 🎯.

> The Build Event Protocol (BEP) is a protocol buffer message format that describes various events during a Bazel invocation that can help provide insights or provide a beautiful UI to display build results.

Why?

I'm in awe & admiration of all the tooling others have built in the Bazel ecosystem to do something similar however they all necessitate a server.

Although running a server isn't an incredibly tall-order, it's still a step that must be taken. Providing a free & open server solution is also possible -- but then I would have to worry about scale and costs.

A _client-only_ solution although limited by what it might be able to display, felt like a great contribution to the ecosystem. A nice addition is that client-only solutions also put at ease security minded individuals when uploading potentially sensitive data.

As someone without much frontend experience, I'm happy with the results. 😊

![Build Event Protocol Viewer Overview](/assets/images/build_event_protocol_viewer_overview.png)

This project is available on [visible.build](https://visible.build), available at [https://github.com/fzakaria/build-event-protocol-viewer](https://github.com/fzakaria/build-event-protocol-viewer), hosted on GitHub Pages and should be ready to explore your Bazel invocations 🤘.

The project is built as a single-page-application (SPA) and pre-rendered so there is absolutely no server requests beyond fetching the static-content.

I chose to use [Svelte](https://svelte.dev/) to generate the UI -- oddly seemed to _fit my brain_. It's as if [React](https://react.dev/) & [Angular](https://angular.dev/) had a baby. Coupled with [Bootstrap](https://getbootstrap.com/) I was able to get a semi-decent looking CSS without much fanfare.

I leveraged & learnt TypeScript, which coupled with [protobufjs](https://github.com/protobufjs) to build the equivalent classes for the protocol definitions, made it relatively straightforward to explore the model. The main challenge was the abundance of fields, many of which were marked as _deprecated_ in the proto definition file.

A nice cherry ontop 🍒 this project is that it has a _clear end state_ that it achieved; which is rare in projects. I set out to do a _single thing_ (i.e. make a simple client-side only UI for BEP), and there's only so much you can do without a server.

I've reached that end state. Visualized _nearly_ at most what I could from the single protocol file and achieved _project nirvana_. 🧘🏼

_Give it a shot. Contribute if you see a bug. Please let me know if you are using it._