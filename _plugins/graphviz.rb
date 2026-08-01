# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "open3"

# Renders ```graphviz fenced blocks with Graphviz, at build time.
#
# The alternative is what this site did before: keep the source in
# assets/images/thing.dot, render it by hand, commit the SVG beside it, and
# leave an HTML comment hoping the two stay in step. They do not. The diagram
# in a post is then a picture of what the graph used to say.
#
# A fence keeps the source in the post, which means editing the graph is
# editing the post and there is no second copy to forget.
#
#     ```graphviz
#     digraph { a -> b }
#     ```
#
# The fence is `graphviz` and not `dot` deliberately, so that a post can still
# quote DOT as source -- ```dot is left alone and highlighted like any other
# code. An engine other than dot is a suffix: ```graphviz-neato.
#
# The output is inline <svg> rather than an <img>, which is what makes it
# possible to follow the page's theme. Graphviz draws on an opaque white canvas
# in black ink, and on a dark page that is a bright rectangle with the labels
# outside the nodes -- cluster titles, edge labels -- rendered black on black.
#
# Three changes fix it, and all of them need the SVG to be markup rather than a
# file: the canvas is made transparent so --paper shows through; the black
# Graphviz writes out is rewritten to currentColor; and the root <svg> is given
# fill="currentColor" for the black it does *not* write out. That last one is
# the whole reason labels stayed dark for so long -- Graphviz emits
#
#     <text text-anchor="middle" x="27" y="-85.33" ...>a</text>
#
# with no fill at all, and SVG's initial fill is black. There is nothing there
# to rewrite; the colour has to be supplied. Every shape Graphviz draws carries
# an explicit fill, so inheriting from the root reaches the text and nothing
# else. Node fills a diagram sets for itself are left alone; they are the
# author's choice, and light fills read on either theme.
#
# Rendering is cached, because Graphviz is slow enough to notice on a full
# rebuild and a diagram changes far less often than prose. What is cached is
# Graphviz's own output, untouched; everything above is applied on read, so
# changing how a diagram is themed costs nothing and invalidates nothing.
module Graphviz
  CACHE_DIR = ".graphviz-cache"

  # Where the click-through copies are written, under the built site. Nothing
  # lands in the source tree: these are generated the way images.rb generates
  # its derivatives.
  ASSET_DIR = "assets/graphviz"

  # The one fence that renders. ```dot stays a code block, so DOT can be
  # quoted as source in a post about DOT.
  LANGUAGE = "graphviz"

  # Everything Graphviz can lay out. The engine is chosen per fence with
  # ```graphviz-neato and friends; unqualified means dot, which is what a
  # dependency graph wants.
  ENGINES = %w[dot neato fdp sfdp circo twopi osage patchwork].freeze

  DEFAULT_ENGINE = "dot"

  # What Kramdown emits for a tagged fence, which is not what you would guess.
  #
  # With a highlighter -- Rouge, which Jekyll turns on by default -- the block
  # is wrapped twice and the code inside is shot through with <span>s:
  #
  #   <div class="language-graphviz highlighter-rouge" data-lang="graphviz">
  #   <div class="highlight"><pre class="highlight"><code>
  #   <span class="k">digraph</span> ...
  #
  # Without one it is the plainer <pre><code class="language-graphviz">. Both
  # shapes are matched, because which one appears depends on a config setting
  # that has nothing to do with this plugin.
  #
  # Every tag here allows trailing attributes. Jekyll appends data-lang to the
  # wrapper that kramdown alone does not, so a pattern written against
  # kramdown's output in isolation matches nothing on a real site -- which is
  # exactly how this was first got wrong.
  ROUGE_FENCE = %r{
    <div\s+(?<attrs>[^>]*class="[^"]*\blanguage-#{LANGUAGE}(?:-(?<engine>\w+))?\b[^"]*"[^>]*)>
    \s*<div\s+class="highlight"[^>]*>
    \s*<pre[^>]*>\s*<code[^>]*>(?<code>.*?)</code>\s*</pre>
    \s*</div>\s*</div>
  }mx

  PLAIN_FENCE = %r{
    <pre[^>]*><code\s+(?<attrs>class="[^"]*\blanguage-#{LANGUAGE}(?:-(?<engine>\w+))?\b[^"]*")>
    (?<code>.*?)
    </code></pre>
  }mx

  FENCES = [ROUGE_FENCE, PLAIN_FENCE].freeze

  def self.process(site)
    Renderer.new(site).process
  end

  # A file with no file behind it. Jekyll writes static files by copying from
  # source, and there is no source here -- the bytes were produced a moment ago
  # by Graphviz -- so the write is overridden and the emptiness declared.
  class Generated < Jekyll::StaticFile
    def initialize(site, dir, name, content)
      super(site, site.source, dir, name)
      @content = content
    end

    def write(dest)
      path = destination(dest)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @content, encoding: Encoding::UTF_8)
      true
    end

    def modified?
      true
    end
  end

  class Renderer
    def initialize(site)
      @site = site
    end

    def process
      @rendered = 0
      @reused = 0
      @failed = 0

      documents.each do |document|
        next unless document.output.respond_to?(:gsub)
        # Two multiline patterns over every page on the site is not free, and
        # almost no page has a diagram on it. A substring test costs nothing
        # and is true of both fence shapes.
        next unless document.output.include?("language-#{LANGUAGE}")

        FENCES.each do |fence|
          document.output = document.output.gsub(fence) do
            match = Regexp.last_match
            render(plain_text(match[:code]),
                   match[:engine] || DEFAULT_ENGINE,
                   match[:attrs],
                   document)
          end
        end
      end

      report
    end

    private

    # Silence on success is what made the first version of this plugin so hard
    # to tell apart from one that was never loaded at all: a build with no
    # Graphviz line could mean every diagram rendered, or that the hook had not
    # run. Images: reports a count for the same reason.
    def report
      total = @rendered + @reused + @failed
      return if total.zero?

      message = "#{total} diagram(s); #{@rendered} rendered, #{@reused} cached"
      message += ", #{@failed} FAILED" if @failed.positive?
      Jekyll.logger.info "Graphviz:", message
    end

    # Posts, drafts and pages alike: a diagram is as useful on the styleguide
    # as it is in an article.
    #
    # Pages that are not HTML are left with the code block, which matters for
    # exactly one of them: feed.xml embeds the rendered post verbatim, and an
    # inline <svg> is the first thing a feed reader's sanitiser throws away.
    # A subscriber is better served by the DOT source, which at least says
    # what the picture said.
    def documents
      (@site.pages + @site.documents).select { |document| document.output_ext == ".html" }
    end

    # Rouge marks up every token, so the code has to be reduced back to text
    # before Graphviz sees it: tags out first, then entities, or an escaped
    # &lt;span&gt; in someone's label would turn into markup.
    def plain_text(html)
      unescape(html.gsub(/<[^>]*>/, ""))
    end

    def unescape(text)
      text
        .gsub("&lt;", "<")
        .gsub("&gt;", ">")
        .gsub("&quot;", '"')
        .gsub("&#39;", "'")
        .gsub("&amp;", "&")
    end

    # Attributes kramdown put on the block that belong to the author rather
    # than to the highlighter, carried onto the figure.
    #
    # This is what makes a per-diagram knob possible without a stylesheet
    # edit. A kramdown IAL on the line after the fence lands here:
    #
    #     ```graphviz
    #     digraph { … }
    #     ```
    #     {: style="--graphviz-height: 20rem"}
    #
    # An extra fence word cannot do the same job -- kramdown stops treating
    # ```graphviz height=20rem as a code block at all and renders it as a
    # paragraph -- so the IAL is the only spelling that survives the parser.
    HIGHLIGHTER_CLASSES = /\A(?:language-[\w-]+|highlighter-rouge)\z/.freeze

    def figure_attributes(attrs)
      classes = ["graphviz"]
      rest = []

      attrs.to_s.scan(/([\w:-]+)="([^"]*)"/) do |name, value|
        case name
        when "class"
          classes.concat(value.split(/\s+/).reject { |c| c.match?(HIGHLIGHTER_CLASSES) })
        when "data-lang"
          next
        else
          rest << %(#{name}="#{value}")
        end
      end

      ([%(class="#{classes.uniq.join(" ")}")] + rest).join(" ")
    end

    def render(source, engine, attrs, document)
      unless ENGINES.include?(engine)
        warn_once(document, "unknown Graphviz engine #{engine.inspect}")
        @failed += 1
        return failed(source)
      end

      require_engine(engine)

      key = cache_key(source, engine)
      svg = cached(key) { layout(source, engine) }
      if svg.nil?
        @failed += 1
        return failed(source)
      end

      href = publish(key, svg)
      inline = theme(strip_prologue(svg), key)

      %(<figure #{figure_attributes(attrs)}>) +
        %(<a href="#{href}" class="graphviz-full" ) +
        %(title="Open this diagram on its own">#{inline}</a></figure>)
    end

    # The same graph as a file, so the figure can be clicked through to a page
    # of its own where the browser's zoom and pan apply. A diagram that has
    # been shrunk to fit a column is not always readable in it.
    #
    # What is written is Graphviz's untouched output, not the copy that goes
    # inline. Inline, black is rewritten to currentColor so the graph follows
    # the page; standalone there is no page to follow, and currentColor would
    # resolve to whatever the browser defaults to.
    def publish(key, svg)
      name = "#{key[0, 16]}.svg"
      unless @published&.include?(name)
        (@published ||= []) << name
        @site.static_files << Generated.new(@site, ASSET_DIR, name, svg)
      end
      File.join("", ASSET_DIR, name)
    end

    # A graph the author got wrong must not take the build down -- a typo in a
    # draft should not stop the site -- but it must not disappear either, so
    # the source is left visible where the picture would have been, and the
    # warning Graphviz printed says which line to look at.
    #
    # A missing engine is the other kind of problem entirely and is not handled
    # here; see require_engine.
    #
    # Tagged `dot` rather than `graphviz`, and not only because it is DOT shown
    # as source: the two fence patterns are applied in turn, and output tagged
    # `graphviz` would be matched by the second one, tried again, and counted a
    # second time. Emitting the fence that does not render ends it here.
    def failed(source)
      %(<pre><code class="language-dot">#{CGI.escapeHTML(source)}</code></pre>)
    end

    # Graphviz writes UTF-8 and this says so, because nothing else in the
    # pipeline will.
    #
    # Ruby tags a subprocess's output with Encoding.default_external, which is
    # whatever the locale says -- and a Nix build sandbox has no locale, so it
    # is US-ASCII. The bytes are UTF-8 either way; only the label on them is
    # wrong, and the first regex to touch a `→` in a node label then dies with
    # "invalid byte sequence in US-ASCII". Reading the bytes as binary and
    # naming the encoding once, here, keeps every pattern downstream honest.
    def layout(source, engine)
      svg, error, status = Open3.capture3(
        engine, "-Tsvg", "-Gbgcolor=transparent", stdin_data: source, binmode: true
      )
      return utf8(svg) if status.success?

      Jekyll.logger.warn "Graphviz:", utf8(error).strip
      nil
    end

    def utf8(bytes)
      bytes.dup.force_encoding(Encoding::UTF_8)
    end

    # Graphviz's default ink, in every spelling it emits, handed over to CSS.
    # This covers the black it states outright -- node outlines, edges,
    # arrowheads. The black it leaves implicit is handled by ROOT_FILL.
    BLACK = /(?<=stroke=|fill=)"(?:black|#000000|#000)"/.freeze

    # SVG's initial fill, said out loud, so that <text> with no fill of its own
    # inherits the page's ink instead of the specification's black. Everything
    # else Graphviz draws states its own fill and ignores this.
    ROOT_FILL = ' fill="currentColor"'

    # What is left of the canvas once bgcolor is transparent: a polygon the
    # size of the graph, filled with nothing. It costs a node in the DOM and
    # can pick up a stroke from a stylesheet, so it goes.
    #
    # Graphviz 12 stopped emitting it, so on a current toolchain this matches
    # nothing; it stays for older ones. Substituting once rather than globally
    # is the point: `fill="none" stroke="none"` is also exactly what a
    # style=invis node renders as, and those belong to the author.
    CANVAS = %r{<polygon[^>]*fill="none"[^>]*stroke="none"[^>]*/>\s*}.freeze

    # Graphviz sizes the root <svg> in points, which is a paper measurement and
    # has nothing to say about a browser column. Dropping width and height
    # leaves the viewBox as the only intrinsic size, so the aspect ratio
    # survives and everything else -- how wide, how tall, how it is capped --
    # is decided by the stylesheet. See figure.graphviz in _sass/style.scss.
    ROOT_SIZE = /(<svg\b[^>]*?)\s+width="[^"]*"\s+height="[^"]*"/.freeze

    VIEWBOX = /viewBox="[\d.\-]+\s+[\d.\-]+\s+([\d.]+)\s+([\d.]+)"/.freeze

    def theme(svg, key)
      themed = svg
        .gsub(BLACK, '"currentColor"')
        .sub(CANVAS, "")
        .sub(ROOT_SIZE, '\\1')
        .sub(/<svg\b/) { |tag| "#{tag}#{ROOT_FILL}#{ratio_style(svg)}" }

      namespace_ids(themed, key)
    end

    # Ids Graphviz defines, and the two ways it refers back to one: url(#x)
    # for a gradient fill, href for a link into the same document.
    ID = /\bid="([^"]+)"/.freeze

    # Graphviz numbers from scratch in every file it writes -- graph0, node1,
    # edge1 -- which is fine for a file and wrong the moment two diagrams share
    # a page. Duplicate ids are invalid HTML, and #node1 in a stylesheet then
    # means whichever diagram the browser reached first.
    #
    # Only ids this SVG actually defines are rewritten. An author's
    # URL="#section" on a node is a link to the page around the diagram and has
    # to keep pointing there.
    #
    # The prefix comes from the cache key rather than a running counter, so a
    # diagram keeps its ids when another one is inserted above it in the post.
    # It is prefixed with a letter because an id may not begin with a digit.
    def namespace_ids(svg, key)
      prefix = "g#{key[0, 8]}"

      svg.scan(ID).flatten.uniq.reduce(svg) do |markup, id|
        markup
          .gsub(%(id="#{id}"), %(id="#{prefix}-#{id}"))
          .gsub("url(##{id})", "url(##{prefix}-#{id})")
          .gsub(%(href="##{id}"), %(href="##{prefix}-#{id}"))
      end
    end

    # An inline <svg> carrying only a viewBox has no height for `height: auto`
    # to resolve against, so a max-height never binds and the graph collapses
    # to a couple of dozen pixels. Stating the ratio outright gives the box
    # something to be proportional to, and then max-width and max-height can
    # both do their jobs: whichever binds first wins and the other follows.
    def ratio_style(svg)
      width, height = svg[VIEWBOX, 1], svg[VIEWBOX, 2]
      return "" if width.nil? || height.nil? || height.to_f.zero?

      %( style="aspect-ratio: #{width} / #{height}")
    end

    # <?xml?> and <!DOCTYPE> belong to a standalone file. Inline in a page they
    # are at best ignored and at worst a parse error, and the comment Graphviz
    # writes above them is noise in the source of every page.
    def strip_prologue(svg)
      svg.sub(/\A.*?(?=<svg)/m, "")
    end

    # Everything that decides what Graphviz writes, and nothing else.
    #
    # The version belongs in here because a Graphviz upgrade lays the same
    # graph out differently, and an entry keyed on the source alone would keep
    # serving the old picture until someone thought to empty the directory by
    # hand. What this plugin does to that output afterwards does not belong in
    # here: it is applied on read, so it cannot go stale.
    def cache_key(source, engine)
      Digest::SHA256.hexdigest("#{version(engine)}\0#{engine}\0#{source}")
    end

    # `dot -V` reports on stderr, which is why both streams are captured.
    def version(engine)
      @versions ||= {}
      @versions[engine] ||= Open3.capture2e(engine, "-V").first.strip
    end

    def cached(key)
      path = File.join(cache_root, "#{key}.svg")
      if File.exist?(path)
        @reused += 1
        # Stated for the same reason layout states it: a cache hit under a
        # locale-less build would otherwise come back US-ASCII and take the
        # build down where a cache miss would have succeeded.
        return File.read(path, encoding: Encoding::UTF_8)
      end

      svg = yield
      return nil if svg.nil?

      @rendered += 1
      FileUtils.mkdir_p(cache_root)
      File.write(path, svg, encoding: Encoding::UTF_8)
      svg
    end

    def cache_root
      @cache_root ||= File.join(@site.source, CACHE_DIR)
    end

    # Graphviz is a build dependency, not an enhancement. Carrying on without
    # it would publish a post whose diagram is a wall of DOT -- the failure is
    # silent in the built site and obvious only to the reader -- so the build
    # stops instead. The flake's devShell provides every engine; see flake.nix.
    #
    # Checked per engine and at the point of use, so the message names the one
    # the fence actually asked for rather than reporting that some other engine
    # happens to be installed.
    def require_engine(engine)
      @present ||= {}
      return if @present[engine]

      raise "Graphviz: #{engine} is not on PATH; cannot render a #{LANGUAGE} block" unless which(engine)

      @present[engine] = true
    end

    def which(binary)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, binary))
      end
    end

    def warn_once(document, message)
      @warned ||= {}
      key = [document.relative_path, message]
      return if @warned[key]

      @warned[key] = true
      Jekyll.logger.warn "Graphviz:", "#{document.relative_path}: #{message}"
    end
  end
end

# After rendering, before writing -- the same point images.rb works at, and for
# the same reason: the HTML exists but nothing has been committed to disk.
Jekyll::Hooks.register :site, :post_render do |site|
  Graphviz.process(site)
end
