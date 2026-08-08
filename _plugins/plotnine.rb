# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "tmpdir"

# Renders ```plotnine fenced blocks with Python and plotnine, at build time.
#
# Same argument as _plugins/graphviz.rb, applied to charts. The alternative is
# what the nes-nix post did first: measure something, generate the SVG with a
# script kept in a scratch directory, commit the SVG, and leave the numbers to
# rot. A chart in a post is then a picture of what the data used to say, and
# the code that drew it is somewhere on one laptop.
#
# A fence keeps the numbers and the plot in the post. Editing the chart is
# editing the post.
#
#     ```plotnine
#     import pandas as pd
#     from plotnine import *
#
#     df = pd.DataFrame({"n": [1, 2, 3], "seconds": [1.0, 1.9, 3.2]})
#     plot = ggplot(df, aes("n", "seconds")) + geom_line()
#     ```
#
# The contract is the name `plot`: the snippet binds it to a ggplot object and
# this saves it. Nothing is printed, nothing is written by the author, and the
# fence stays pure plot code with no boilerplate about output paths. Size is
# the one optional extra: `plot.width, plot.height = 7.0, 3.4` after the plot
# is built, if the default figure is the wrong shape for that chart.
#
# The fence is `plotnine` and not `python`, so a post can still quote Python as
# source -- ```python is left alone and highlighted like any other code.
#
# Output is inline <svg> rather than <img>, for the reason graphviz.rb explains
# at length: it is the only way the figure can follow the page's theme. A chart
# is worse than a diagram here, because matplotlib writes an opaque white
# canvas *and* dark grey axes, both of which are wrong on a dark page.
#
# Theming is done by agreement rather than by guessing. The harness renders
# every structural element -- text, axis lines, ticks, the panel border -- in
# one sentinel colour that appears nowhere in any palette, and that colour is
# rewritten to currentColor on read. Data colours the author chose are left
# exactly as authored, which is the whole point of the sentinel: a rewrite of
# "every dark thing" would eat a dark series.
#
# Rendering is cached. Importing pandas and plotnine costs about a second
# before any drawing happens, and a chart changes far less often than prose.
# What is cached is the harness's own output; the theming rewrite is applied on
# read, so changing how figures are themed costs nothing and invalidates
# nothing.
module Plotnine
  CACHE_DIR = ".plotnine-cache"

  # Where the click-through copies are written, under the built site. Nothing
  # lands in the source tree; these are generated the way graphviz.rb does it.
  ASSET_DIR = "assets/plotnine"

  LANGUAGE = "plotnine"

  # The ink for the standalone copy. Inline, the sentinel becomes currentColor
  # and the page decides; opened on its own there is no page to inherit from
  # and currentColor would resolve to whatever the browser defaults to. This is
  # --ink from the light theme, which is what a bare SVG opens against.
  STANDALONE_INK = "#1a1815"

  # The object the snippet is expected to bind. Named rather than "the last
  # expression" because a fence is a script, not a REPL, and a trailing bare
  # expression in a script reads like a mistake.
  PLOT_NAME = "plot"

  # Where the harness looks for the font file to measure and name. Set by
  # nix/site.nix and nix/dev-shells.nix to the same JetBrains Mono that
  # assets/fonts serves the page. Unset -- a contributor outside the
  # devShell -- falls back to matplotlib's own default face and outlined
  # text, which still renders, just not in the site's typography.
  FONT_ENV = "PLOTNINE_FONT"

  # Chosen to be findable and to belong to nothing: not a plotnine default, not
  # in this site's palette, not a colour anyone would reach for. Every
  # structural element is drawn in it and every occurrence is rewritten.
  INK_SENTINEL = "#010203"

  # The figure a fence gets when it does not ask for one, in inches. Wide
  # enough to fill the column and short enough that a chart does not push the
  # prose off the screen; a fence that wants another shape assigns
  # `plot.width` and `plot.height` itself.
  DEFAULT_WIDTH = 7.0
  DEFAULT_HEIGHT = 3.6

  # Runs the author's snippet and saves `plot`. Kept here rather than in a
  # committed .py file so that the plugin is one file: there is no second thing
  # to find when this misbehaves.
  #
  # matplotlib needs a writable cache directory and no display; both are set by
  # the caller through the environment.
  HARNESS = <<~PYTHON
    import os
    import sys

    import matplotlib
    matplotlib.use("Agg")

    # Text as real <text> elements rather than outlined glyph paths. The
    # default is "path", which guarantees identical rendering by making the
    # letters shapes -- at the cost of size, and of text no reader can select
    # and no screen reader can reach. That trade is only worth taking because
    # the family registered below is the one the page actually serves.
    matplotlib.rcParams["svg.fonttype"] = "none"

    from matplotlib import font_manager

    # nix/fonts.nix does this for `dot`, through FONTCONFIG_FILE. It cannot
    # reach here: matplotlib has a font manager of its own and never consults
    # fontconfig, so the file has to be registered by hand.
    #
    # It matters for the same reason it matters for a diagram. Left alone,
    # matplotlib measures every label with the first face it happens to find
    # -- DejaVu Sans in this sandbox -- and then writes a family stack asking
    # the browser for Helvetica first. A reader with Helvetica renders one
    # face at coordinates computed for another, and labels drift out of the
    # space reserved for them. Naming the served font on both sides removes
    # the disagreement: what renders here is what renders there.
    FONT = os.environ.get("#{FONT_ENV}")
    FAMILY = None
    if FONT:
        font_manager.fontManager.addfont(FONT)
        FAMILY = font_manager.FontProperties(fname=FONT).get_name()
        # Through font.monospace rather than font.family, which would splice
        # matplotlib's entire monospace list into every text element.
        matplotlib.rcParams["font.monospace"] = [FAMILY, "monospace"]
        matplotlib.rcParams["font.family"] = "monospace"

    INK = "#{INK_SENTINEL}"

    import plotnine

    # Structural elements all in the sentinel, so the rewrite on the Ruby side
    # has exactly one colour to look for. Anything the author sets afterwards
    # wins, which is intended: an explicit choice should survive the theme.
    theme_site = plotnine.theme_minimal(base_family=FAMILY) + plotnine.theme(
        text=plotnine.element_text(color=INK),
        axis_text=plotnine.element_text(color=INK),
        axis_title=plotnine.element_text(color=INK),
        axis_line=plotnine.element_line(color=INK),
        axis_ticks=plotnine.element_line(color=INK),
        strip_text=plotnine.element_text(color=INK),
        legend_title=plotnine.element_text(color=INK),
        plot_title=plotnine.element_text(color=INK),
        panel_background=plotnine.element_rect(fill="none", color="none"),
        plot_background=plotnine.element_rect(fill="none", color="none"),
        legend_background=plotnine.element_rect(fill="none", color="none"),
        panel_grid=plotnine.element_line(color=INK, alpha=0.18),
    )

    # Installed as the *default* theme rather than added to the finished plot.
    # Adding it afterwards silently overrides the author: a fence asking for
    # theme(legend_position="bottom") got the legend back on the right, because
    # the last theme in a sum wins. As a default it sits underneath instead,
    # and anything the fence adds composes on top of it.
    plotnine.theme_set(theme_site)

    source_path, out_path = sys.argv[1], sys.argv[2]
    namespace = {"__name__": "__plotnine_fence__", "INK": INK}
    with open(source_path, encoding="utf-8") as handle:
        exec(compile(handle.read(), "<fence>", "exec"), namespace)

    plot = namespace.get("#{PLOT_NAME}")
    if plot is None:
        raise SystemExit(
            "a ```#{LANGUAGE} fence must bind `#{PLOT_NAME}` to a ggplot object"
        )

    # Size is optional: a fence that cares says so by assigning plot.width /
    # plot.height, and one that does not gets the column's default figure.
    # Read with getattr because those are the author's own attributes, not
    # ggplot's -- an unsized plot has no such attribute at all.
    width = getattr(plot, "width", None) or #{DEFAULT_WIDTH}
    height = getattr(plot, "height", None) or #{DEFAULT_HEIGHT}

    # facecolor is the matplotlib *figure* patch, which is not the theme's
    # plot_background and is not reachable from a plotnine theme: plotnine
    # draws plot_background as its own rectangle on top of a figure canvas
    # that matplotlib still paints white underneath. Left alone, every chart
    # carries an opaque white sheet that hides the page in dark mode. This is
    # forwarded to savefig, where "none" means paint nothing at all.
    plot.save(out_path, format="svg", verbose=False,
              width=width, height=height, dpi=96,
              facecolor="none", edgecolor="none")
  PYTHON

  # Kramdown emits one of two shapes depending on whether a highlighter is on.
  # See the long note in graphviz.rb; both are matched here for the same
  # reason, including the data-lang Jekyll appends that kramdown alone does not.
  ROUGE_FENCE = %r{
    <div\s+(?<attrs>[^>]*class="[^"]*\blanguage-#{LANGUAGE}\b[^"]*"[^>]*)>
    \s*<div\s+class="highlight"[^>]*>
    \s*<pre[^>]*>\s*<code[^>]*>(?<code>.*?)</code>\s*</pre>
    \s*</div>\s*</div>
  }mx

  PLAIN_FENCE = %r{
    <pre[^>]*><code\s+(?<attrs>class="[^"]*\blanguage-#{LANGUAGE}\b[^"]*")>
    (?<code>.*?)
    </code></pre>
  }mx

  FENCES = [ROUGE_FENCE, PLAIN_FENCE].freeze

  def self.process(site)
    Renderer.new(site).process
  end

  # A file with no file behind it: the bytes were produced a moment ago by
  # plotnine, so the write is overridden and the emptiness declared. Same
  # shape as graphviz.rb's, for the same reason.
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

      documents.each do |document|
        next unless document.output.respond_to?(:gsub)
        next unless document.output.include?("language-#{LANGUAGE}")

        FENCES.each do |fence|
          document.output = document.output.gsub(fence) do
            match = Regexp.last_match
            render(plain_text(match[:code]), match[:attrs], document)
          end
        end
      end

      report
    end

    private

    def report
      total = @rendered + @reused
      return if total.zero?

      Jekyll.logger.info "Plotnine:", "#{total} chart(s); #{@rendered} rendered, #{@reused} cached"
    end

    # Feed pages keep the source, exactly as with graphviz: an inline <svg> is
    # the first thing a feed reader's sanitiser discards, and a subscriber is
    # better served by the code that drew the chart.
    def documents
      (@site.pages + @site.documents).select { |document| document.output_ext == ".html" }
    end

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

    HIGHLIGHTER_CLASSES = /\A(?:language-[\w-]+|highlighter-rouge)\z/.freeze

    def figure_attributes(attrs)
      classes = ["plotnine"]
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

    def render(source, attrs, document)
      require_python

      key = cache_key(source)
      svg = cached(key) { draw(source, document) }
      body = fallback_font(strip_prologue(svg))
      href = publish(key, standalone(body))

      %(<figure #{figure_attributes(attrs)}>) +
        %(<a href="#{href}" class="plotnine-full" ) +
        %(title="Open this chart on its own">#{theme(body)}</a></figure>)
    end

    # The same chart as a file, so a figure shrunk to fit the column can be
    # clicked through to a page of its own where the browser's zoom applies.
    def publish(key, svg)
      name = "#{key[0, 16]}.svg"
      unless @published&.include?(name)
        (@published ||= []) << name
        @site.static_files << Generated.new(@site, ASSET_DIR, name, svg)
      end
      File.join("", ASSET_DIR, name)
    end

    # The standalone copy resolves the sentinel to a real colour and keeps the
    # XML prologue matplotlib wrote, so the file stands up on its own.
    def standalone(body)
      %(<?xml version="1.0" encoding="utf-8" standalone="no"?>\n) +
        body.gsub(/#{Regexp.escape(INK_SENTINEL)}/i, STANDALONE_INK)
    end

    # The font is in the key because it decides both the metrics every label
    # was positioned with and the family the SVG names: swapping it redraws
    # every chart, and a cached figure from the old one would be wrong.
    def cache_key(source)
      Digest::SHA256.hexdigest(
        "#{version}\0#{INK_SENTINEL}\0#{font_file}\0#{HARNESS}\0#{source}"
      )
    end

    def font_file
      @font_file ||= ENV.fetch(FONT_ENV, "")
    end

    # The plotnine version rather than Python's: a plotnine upgrade is what
    # changes the drawing, and it moves far more often than the interpreter.
    def version
      @version ||= Open3.capture2e(
        python, "-c", "import plotnine, sys; print(plotnine.__version__, sys.version)"
      ).first.strip
    end

    def cached(key)
      path = File.join(cache_root, "#{key}.svg")
      if File.exist?(path)
        @reused += 1
        return File.read(path, encoding: Encoding::UTF_8)
      end

      svg = yield
      @rendered += 1
      FileUtils.mkdir_p(cache_root)
      File.write(path, svg, encoding: Encoding::UTF_8)
      svg
    end

    def cache_root
      @cache_root ||= File.join(@site.source, CACHE_DIR)
    end

    def draw(source, document)
      Dir.mktmpdir("plotnine-fence") do |dir|
        source_path = File.join(dir, "fence.py")
        harness_path = File.join(dir, "harness.py")
        out_path = File.join(dir, "figure.svg")

        File.write(source_path, source, encoding: Encoding::UTF_8)
        File.write(harness_path, HARNESS, encoding: Encoding::UTF_8)

        output, status = Open3.capture2e(
          # MPLCONFIGDIR keeps matplotlib from trying to write a font cache into
          # a home directory that does not exist in the Nix build sandbox.
          { "MPLCONFIGDIR" => dir, "MPLBACKEND" => "Agg",
            FONT_ENV => font_file },
          python, harness_path, source_path, out_path
        )

        # A chart that failed to draw must not be a silently missing figure.
        # The build stops, the same way a missing Graphviz engine stops it.
        unless status.success? && File.exist?(out_path)
          raise "Plotnine: #{document.relative_path}: chart failed to render\n#{output}"
        end

        File.read(out_path, encoding: Encoding::UTF_8)
      end
    end

    # plotnine writes the family it was given and nothing after it, because a
    # base_family set on the theme replaces matplotlib's own family chain.
    # That is right for the inline copy, which sits in a page that @font-faces
    # the family -- and wrong for the standalone one, which opens with no
    # stylesheet at all and would land on the browser's default face. Adding
    # the generic keeps the figure monospaced either way.
    def fallback_font(svg)
      svg.gsub(/font-family: '([^']+)'(?=[;"])/, "font-family: '\\1', monospace")
    end

    # matplotlib writes an XML declaration and a DOCTYPE before the root
    # element. Both are fine in a standalone file and neither belongs in the
    # middle of an HTML document.
    def strip_prologue(svg)
      svg.sub(/\A.*?(?=<svg\b)/m, "")
    end

    # The sentinel becomes currentColor, so text and axes take the page's ink
    # in either theme. matplotlib spells colours in a few different places --
    # presentation attributes, inline style properties, and <style> rules --
    # and the sentinel is distinctive enough that a plain substitution over all
    # of them is safe.
    def theme(svg)
      svg
        .gsub(/#{Regexp.escape(INK_SENTINEL)}/i, "currentColor")
        .sub(/<svg\b/, %(<svg role="img" ))
    end

    # plotnine is a build dependency, not an enhancement: carrying on without
    # it would publish a post whose chart is a wall of Python. The flake's
    # devShell provides it; see flake.nix.
    def require_python
      return if @checked

      unless which(python)
        raise "Plotnine: #{python} is not on PATH; cannot render a ```#{LANGUAGE} block"
      end

      probe, status = Open3.capture2e(python, "-c", "import plotnine")
      raise "Plotnine: #{python} cannot import plotnine\n#{probe}" unless status.success?

      @checked = true
    end

    # Overridable so a contributor without the devShell can point at their own
    # interpreter rather than editing the plugin.
    def python
      @python ||= ENV.fetch("JEKYLL_PYTHON", "python3")
    end

    def which(binary)
      return File.executable?(binary) if binary.include?(File::SEPARATOR)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        File.executable?(File.join(directory, binary))
      end
    end
  end
end

# After rendering, before writing -- the same point graphviz.rb and images.rb
# work at.
Jekyll::Hooks.register :site, :post_render do |site|
  Plotnine.process(site)
end
