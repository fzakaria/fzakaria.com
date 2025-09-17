---
layout: post
title: Talks & Publications
---

I enjoy speaking! Here are _some_ of my talks and publications available online. I have not done a great job of keeping all the slides, sorry.

<div style="display: flex; gap: 3em;">
<div style="flex-basis: 50%;">
<h4>Talks</h4>
<ul>
    <li><a href="#talk-learn-nix">Learn Nix The Fun Way (2025)</a></li>
    <li><a href="#talk-looker-nix">[High|Low]Lights of Adopting Nix at Looker (2024)</a></li>
    <li><a href="#talk-sql-elf">A SQL Approach to Exploring ELF Objects (2023)</a></li>
    <li><a href="#talk-mapping-dependency-chaos">Mapping Out the HPC Dependency Chaos (2022)</a></li>
    <li><a href="#talk-rethinking-primitives">Rethinking basic primitives for store based systems (2022)</a></li>
    <li><a href="#talk-java-hermetic">Challenges with Java in a hermetic world (2021)</a></li>
    <li><a href="#talk-nix-java">Nix in the Java ecosystem (2020)</a></li>
</ul>

<h4>Panels &amp; Podcasts</h4>
<ul>
    <li><a href="#podcast-rebuild-world">Rebuild The World: Access to secure software dependency management everywhere with Nix (2025)</a></li>
    <li><a href="#podcast-bazel">Bazel for Everyone? Hard Questions with Confluent Engineers (2025)</a></li>
    <li><a href="#podcast-tech-over-tea">Tech Over Tea Appearance (2025)</a></li>
    <li><a href="#podcast-fulltime-nix">FullTime Nix Appearance (2025)</a></li>
    <li><a href="#podcast-dockercon">The Impact of AI on Cloud-Native Engineering (2023)</a></li>
</ul>
</div>
<div style="flex-basis: 50%;">
<h4>Publications</h4>
<ul>
    <li><a href="#pub-dissertation">Dissertation: Exploiting Stability in Software Systems (2025)</a></li>
    <li><a href="#pub-matrs">Symbol Resolution MatRs (2025)</a></li>
    <li><a href="#pub-sqlelf">sqlelf: a SQL-centric Approach to ELF Analysis (2024)</a></li>
    <li><a href="#pub-hpc-chaos">Mapping Out the HPC Dependency Chaos (2022)</a></li>
</ul>
</div>
</div>

---

<h2>Talks</h2>

<h3>2025</h3>
<ul>
    <li id="talk-learn-nix">
        "Learn Nix The Fun Way" &mdash; <strong>Nix Vegas @ DEF CON 33</strong>.
        <a href="https://www.youtube.com/watch?v=hX1aRF_Rnu0">[Video]</a>
        <a href="https://fzakaria.com/2024/07/05/learn-nix-the-fun-way">[Slides]</a>
        <br><em>A hands-on, approachable introduction to the Nix ecosystem for beginners. I also presented this talk at <a href="https://www.socallinuxexpo.org/scale/22x/presentations/learn-nix-fun-way">PlanetNix 2025</a>.</em>
    </li>
</ul>

<h3>2024</h3>
<ul>
    <li id="talk-looker-nix">
        "[High|Low]Lights of Adopting Nix at Looker (Google Cloud)" &mdash; <strong>PlanetNix 2024</strong>.
        <a href="https://www.youtube.com/watch?v=GkgsFbwYdYA">[Video]</a>
        <br><em>A retrospective on the experience of integrating Nix into a large-scale enterprise environment at Google Cloud.</em>
    </li>
</ul>

<h3>2023</h3>
<ul>
    <li id="talk-sql-elf">
        "A SQL Approach to Exploring ELF Objects" &mdash; <strong>SCaLE 21x</strong>, Pasadena, CA.
        <a href="https://www.youtube.com/watch?v=mEHWb4dCAFI">[Video]</a>
        <a href="https://www.socallinuxexpo.org/sites/default/files/presentations/A%20SQL%20Approach%20to%20Exploring%20ELF%20Objects.pdf">[Slides]</a>
        <br><em>An exploration of using SQL queries to analyze and introspect ELF binary files with the <a href="https://github.com/fzakaria/sqlelf">sqlelf</a> tool.</em>
    </li>
</ul>

<h3>2022</h3>
<ul>
    <li id="talk-mapping-dependency-chaos">
        "Mapping Out the HPC Dependency Chaos" &mdash; <strong>SuperComputing 2022</strong>.
        <a href="https://sc22.supercomputing.org/presentation/index-333.htm?post_type=page&p=3479&id=pap132&sess=sess159">
        [Event]</a>
        <br><em>A talk on the associated <a href="#pub-hpc-chaos">published paper</a> and the tool <a href="https://github.com/fzakaria/shrinkwrap">shrinkwrap</a>.</em>
    </li>
    <li id="talk-rethinking-primitives">
        "Rethinking basic primitives for store based systems" &mdash; <strong>NixCon 2022</strong>, Paris, France.
        <a href="https://www.youtube.com/watch?v=HZKFe4mCkr4">[Video]</a>
        <br><em>I introduce some of the simple improvements one can uncover starting at the linking phase of object building and process startup. I challenge the community to take Nix further.</em>
    </li>
</ul>

<h3>2021</h3>
<ul>
    <li id="talk-java-hermetic">
        "Challenges with Java in a hermetic world" &mdash; <strong>PackagingCon 2021</strong>.
        <a href="https://www.youtube.com/watch?v=gQstiX7H8MQ">[Video]</a>
        <br><em>A deep dive into the complexities of packaging Java applications for hermetic, reproducible builds.</em>
    </li>
</ul>

<h3>2020</h3>
<ul>
    <li id="talk-nix-java">
        "Nix in the Java ecosystem" &mdash; <strong>NixCon 2020</strong>.
        <a href="https://www.youtube.com/watch?v=HGEY6ABQUBw">[Video]</a>
        <br><em>An early look at bridging the gap between Nix's reproducible builds and the Java development world.</em>
    </li>
</ul>

---

<h2 id="podcasts">Panels &amp; Podcasts</h2>
<ul>
    <li id="podcast-rebuild-world">
        "Rebuild The World: Access to secure software dependency management everywhere with Nix" &mdash; <strong>DEFCON 2025</strong>.
        <a href="https://defcon.org/html/defcon-33/dc-33-creator-talks.html#content_60779">
        [Event]</a>
        <br><em>A panel discussion on SBOMs and how we can reclaim our services and software from vendor lockin and Docker image bitrot using Nix and NixOS.</em>
    </li>
    <li id="podcast-bazel">
        "Bazel for Everyone? Hard Questions with Confluent Engineers".
        <a href="https://www.youtube.com/watch?v=oh_b19EtDHs">[Video]</a>
        <br><em>A conversation about the trade-offs and challenges of adopting the Bazel build system.</em>
    </li>
    <li id="podcast-tech-over-tea">
        "Tech Over Tea" Podcast Appearance.
        <a href="https://www.youtube.com/watch?v=KVxk7LFdHtQ">[Video]</a>
        <br><em>A friendly chat about the pros and cons of using NixOS as a daily driver.</em>
    </li>
    <li id="podcast-fulltime-nix">
        "FullTime Nix" Podcast Appearance.
        <a href="https://podcasts.apple.com/us/podcast/stable-linking-with-farid-zakaria/id1729409279?i=1000700765989">[Listen]</a>
        <br><em>A discussion about stable linking and its implications for reproducible software.</em>
    </li>
    <li id="podcast-dockercon">
        "The Impact of AI on Cloud-Native Engineering" &mdash; <strong>DockerCon 2023</strong>.
        <a href="https://www.youtube.com/watch?v=ytOt4nyrBE8">[Video]</a>
        <br><em>A panel discussion on how AI is shaping the future of software development and cloud infrastructure.</em>
    </li>
</ul>

---

<h2 id="publications">Publications</h2>
<ul>
    <li id="pub-dissertation">
        <strong>Dissertation:</strong> "Exploiting Stability in Software Systems: Primitives for Fast Startup, Binary Introspection, and Explicit Dependency Control". <i>UC Santa Cruz</i>, 2025.
        <a href="https://escholarship.org/uc/item/5cd970wn">[Paper]</a>
        <a href="https://www.youtube.com/watch?v=ZAN2Z4_PG1E">[Defense Video]</a>
        <br><em>My Ph.D. research on creating new primitives for software systems by exploiting temporal and spatial stability.</em>
    </li>
    <li id="pub-matrs">
        "Symbol Resolution MatRs: Make it Fast and Observable with Stable Linking". <i>arXiv</i>, 2025.
        <a href="https://arxiv.org/abs/2501.06716">[Paper]</a>
        <br><em>This paper introduces MatRs, a novel approach to accelerate dynamic linking by reusing symbol resolution results.</em>
    </li>
    <li id="pub-sqlelf">
        "sqlelf: a SQL-centric Approach to ELF Analysis". <i>arXiv</i>, 2024.
        <a href="https://arxiv.org/abs/2405.03883">[Paper]</a>
        <br><em>Presents a new tool that leverages SQLite to enable powerful, query-based analysis of ELF binaries.</em>
    </li>
    <li id="pub-hpc-chaos">
        "Mapping Out the HPC Dependency Chaos". <i>arXiv</i>, 2022.
        <a href="https://arxiv.org/abs/2211.05118">[Paper]</a>
        <br><em>An analysis of the complex software dependency graphs found in High-Performance Computing environments.</em>
    </li>
</ul>