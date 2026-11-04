# frozen_string_literal: true

require "digest"
require "fileutils"
require "rexml/document"
require "set"

# Every inline <svg> figure becomes a link to a standalone copy of itself.
#
# A figure in the column is drawn at whatever size the column leaves it:
# graphviz.rb caps a diagram at --graphviz-height, a chart is squeezed to the
# measure, a hand-written <svg> in a post is held to its own max-width. A
# label that is legible at the size the figure was drawn can be too small at
# the size it is shown. Clicking the figure opens it on a page of its own,
# where it fills the window and is never drawn smaller than its natural size.
#
# This runs once over the rendered HTML rather than inside each renderer, so
# every source of inline SVG gets it the same way and a new post needs no
# markup for it:
#
#   - ```graphviz fences, rendered by graphviz.rb;
#   - ```plotnine fences, rendered by plotnine.rb;
#   - <svg> written by hand inside a <figure> in the post itself.
#
# What all three share is the shape <figure><svg>…</svg></figure>, and that is
# what is matched. A figure whose <svg> is already inside an <a> is left
# alone, so an author who wants the figure to link somewhere else can say so.
#
# The standalone copy cannot simply be the inline markup in a file. Inline, a
# figure takes its ink from the page: graphviz.rb rewrites black to
# currentColor, plotnine.rb rewrites its sentinel the same way, and a
# hand-written figure reads var(--ink) and friends. Opened on its own there is
# no page, so currentColor is the browser default and every var() falls back
# to whatever the author wrote as its fallback -- the light theme, on a dark
# reader's screen. The copy therefore carries a <style> of its own with the
# theme tokens it uses, light and dark, read out of the compiled stylesheet,
# and paints --paper behind itself so the ink has the background it was
# chosen against.
#
# The feed gets the same copies by another route. feed.xml embeds each post's
# HTML, and a feed reader's sanitiser throws away an inline <svg>, so a
# subscriber would see nothing where the figure was -- or, for a fence, the
# Python or DOT that drew it. In the feed every figure's <svg> is swapped for
# an <img> of its standalone copy instead, which a reader fetches like any
# other picture. The copy themes itself through prefers-color-scheme, and that
# still works inside an <img>; the web fonts do not load there, so a label
# falls back to the generic face at the end of its stack.
module Figures
  # Under the built site; nothing lands in the source tree. Named by content,
  # so a figure used on two pages is one file and an edit is a new URL.
  ASSET_DIR = "assets/figures"

  # Read for the theme tokens and the @font-face rules, the same file
  # images.rb reads its layout from.
  STYLESHEET_URL = "/assets/css/base.css"

  # jekyll-feed's default path, and the one page that is not HTML but still
  # carries figures. graphviz.rb and plotnine.rb render their fences in it too,
  # so that this plugin finds a <figure><svg> there to replace.
  FEED_URL = "/feed.xml"

  # The text alternative when a figure has none of its own. Every figure ought
  # to carry a title or an aria-label; this is for the ones that do not yet.
  UNTITLED_ALT = "Figure"

  LINK_CLASS = "figure-full"
  LINK_TITLE = "Open this figure on its own"

  SVG_NAMESPACE = "http://www.w3.org/2000/svg"
  XLINK_NAMESPACE = "http://www.w3.org/1999/xlink"

  # Tokens every standalone copy gets whether or not the figure names them:
  # the canvas, the ink currentColor resolves to, and the face unstyled text
  # falls back to -- the same three the page's <body> sets.
  BASE_TOKENS = %w[--paper --ink --serif].freeze

  # The opening tag of a <figure> whose first child is an <svg>. Only the
  # figure is consumed; the <svg> is found and measured separately.
  FIGURE_SVG = /<figure\b[^>]*>\s*(?=<svg\b)/.freeze

  # An <svg> open or close tag, for finding where the root one ends when a
  # figure nests another <svg> inside itself.
  SVG_TAG = %r{<svg\b|</svg\s*>}.freeze

  # The root's opening tag, attributes and all. Quoted values are skipped
  # whole, because an aria-label is prose and prose may contain a ">".
  ROOT_TAG = /\A<svg\b(?:[^>"']|"[^"]*"|'[^']*')*>/.freeze

  # A var() reference, for working out which tokens a figure needs.
  VAR_REFERENCE = /var\(\s*(--[\w-]+)/.freeze

  # HTML has some two thousand named entities and XML has five. Kramdown
  # passes an author's &rarr; through untouched, which is fine in a page and
  # a parse error in a .svg, so every other name is spelled as a number.
  NAMED_ENTITY = /&([A-Za-z][A-Za-z0-9]*);/.freeze
  XML_ENTITIES = %w[amp lt gt quot apos].freeze

  # A length the root can be drawn at by itself. A percentage, or no width at
  # all, means "the size of whatever contains me", and in a file of its own
  # that is the whole window.
  ABSOLUTE_LENGTH = /\A\s*([\d.]+)(px|pt|pc|mm|cm|in)?\s*\z/.freeze

  # A viewBox, for the <img> a feed figure becomes: its width and height are
  # the figure's natural size, which a reader then scales to its column.
  VIEWBOX = /\A[\d.\-]+[\s,]+[\d.\-]+[\s,]+([\d.]+)[\s,]+([\d.]+)\z/.freeze

  def self.process(site)
    Linker.new(site).process
  end

  def self.feed?(document)
    document.url == FEED_URL
  end

  # A file with no file behind it, the same shape graphviz.rb and plotnine.rb
  # used for their own copies before this plugin took the job over: the
  # bytes were made a moment ago, so the write is overridden and the
  # emptiness declared.
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

  class Linker
    def initialize(site)
      @site = site
      @published = Set.new
      @linked = 0
      @pictured = 0
      @warnings = []
    end

    def process
      @theme = read_theme

      # Without the theme a standalone copy would open in the wrong colours on
      # a dark screen, which is worse than not offering one. The figures stay
      # exactly as they are and the build says why.
      if @theme.nil?
        report
        return
      end

      documents.each do |document|
        next unless document.output.include?("<figure")

        document.output = replace_figures(document.output, document) { |svg| link(svg, document) }
      end

      feed = @site.pages.find { |page| Figures.feed?(page) }
      if feed&.output&.include?("<figure")
        feed.output = replace_figures(feed.output, feed) { |svg, figure| picture(svg, figure, feed) }
      end

      report
    end

    private

    # HTML only. The feed is handled apart, by picture: a link around an <svg>
    # a feed reader has already thrown away would be a link around nothing.
    def documents
      (@site.pages + @site.documents).select do |document|
        document.output_ext == ".html" && document.output.respond_to?(:include?)
      end
    end

    # --- Finding each figure's <svg> -----------------------------------------

    # Hand each figure's root <svg>, and the <figure> tag that opens it, to the
    # block, and put whatever the block returns in the <svg>'s place.
    def replace_figures(html, document)
      out = +""
      cursor = 0

      while (figure = html.match(FIGURE_SVG, cursor))
        start = figure.end(0)
        finish = svg_end(html, start)

        # An <svg> that never closes is a broken page already. Leave the rest
        # of it as it was rather than guess where the figure ends.
        break if finish.nil?

        out << html[cursor...start] << yield(html[start...finish], figure[0])
        cursor = finish
      end

      out << html[cursor..]
    end

    # Where the <svg> that opens at `start` ends, counting nested ones so that
    # an inner </svg> does not end the figure early.
    def svg_end(html, start)
      depth = 0
      position = start

      while (tag = html.match(SVG_TAG, position))
        depth += tag[0].start_with?("</") ? -1 : 1
        position = tag.end(0)
        return position if depth.zero?
      end

      nil
    end

    # --- The page: wrap each figure's <svg> in a link ------------------------

    # draggable="false" is what lets the labels be selected: a drag that starts
    # inside a link is a link drag. See figure > a.figure-full in _sass.
    def link(svg, document)
      copy = standalone(svg)

      # A copy that is not well-formed XML opens as a parse error, so the
      # figure keeps no link at all rather than one to a broken page.
      error = xml_error(copy)
      unless error.nil?
        @warnings << "#{document.relative_path}: figure left unlinked, its SVG is not XML (#{error})"
        return svg
      end

      @linked += 1
      %(<a href="#{publish(copy)}" class="#{LINK_CLASS}" draggable="false" ) +
        %(title="#{LINK_TITLE}">#{svg}</a>)
    end

    # --- The feed: replace each figure's <svg> with a picture of it ---------

    # The src is absolute because a feed reader resolves a relative one
    # against whatever it likes, and not every reader honours xml:base.
    def picture(svg, figure, document)
      copy = standalone(svg)

      # The same rule as the page: a copy that is not XML would be a broken
      # image, so the <svg> stays and the reader does what it does with it.
      error = xml_error(copy)
      unless error.nil?
        @warnings << "#{document.relative_path}: figure left as <svg> in the feed, its SVG is not XML (#{error})"
        return svg
      end

      @pictured += 1
      src = @site.config["url"].to_s.chomp("/") + publish(copy)
      %(<img src="#{src}" alt="#{alt(svg[ROOT_TAG].to_s, figure)}"#{natural_dimensions(svg[ROOT_TAG].to_s)}>)
    end

    # The figure's own words for itself: the title a fence's IAL puts on the
    # <figure>, or the aria-label a hand-written <svg> carries. Both are
    # attribute values already, escaped as such, so they go across as they are.
    def alt(root, figure)
      attribute(figure, "title") || attribute(root, "aria-label") || UNTITLED_ALT
    end

    def natural_dimensions(root)
      width, height = attribute(root, "viewBox").to_s.strip.match(VIEWBOX)&.captures
      return "" if width.nil?

      %( width="#{width.to_f.round}" height="#{height.to_f.round}")
    end

    def publish(copy)
      name = "#{Digest::SHA256.hexdigest(copy)[0, 16]}.svg"
      unless @published.include?(name)
        @published << name
        @site.static_files << Generated.new(@site, ASSET_DIR, name, copy)
      end
      File.join("", ASSET_DIR, name)
    end

    def xml_error(copy)
      REXML::Document.new(copy)
      nil
    rescue REXML::ParseException => e
      e.message.lines.first.to_s.strip
    end

    # --- The file: the same <svg>, able to stand by itself -------------------

    def standalone(svg)
      body = numeric_entities(svg)
      root = body[ROOT_TAG]
      return body if root.nil?

      %(<?xml version="1.0" encoding="UTF-8"?>\n) +
        namespaced(root, body) +
        %(<style><![CDATA[#{stylesheet(body, root)}]]></style>) +
        body[root.length..]
    end

    # An <svg> inline in HTML is SVG because the HTML parser says so. In a file
    # of its own only the namespace says so, and without it the browser shows
    # the markup as an unstyled XML tree. Hand-written figures never carry it.
    def namespaced(root, body)
      tag = root
      tag = tag.sub(/\A<svg\b/, %(<svg xmlns="#{SVG_NAMESPACE}")) unless tag.match?(/\sxmlns=/)

      if body.include?("xlink:") && !tag.include?("xmlns:xlink=")
        tag = tag.sub(/\A<svg\b/, %(<svg xmlns:xlink="#{XLINK_NAMESPACE}"))
      end

      tag
    end

    def numeric_entities(svg)
      svg.gsub(NAMED_ENTITY) do |whole|
        name = Regexp.last_match(1)
        next whole if XML_ENTITIES.include?(name)

        entity = Kramdown::Utils::Entities.entity(name)
        entity.nil? ? whole : "&##{entity.code_point};"
      end
    end

    # The copy's own stylesheet, in three parts.
    #
    # The tokens: every --name the figure reads, plus BASE_TOKENS, with the
    # light values on :root and the dark ones under prefers-color-scheme.
    #
    # The canvas: in a standalone SVG document the root's background is the
    # window's, so --paper fills the screen the way it fills the page, and
    # `color` gives currentColor the page's ink. The size is window_size's,
    # forced with !important because a hand-written figure sizes itself in
    # its style attribute -- max-width: 44rem -- for the column, and that
    # would hold the copy to the size of the figure it was opened from.
    #
    # The faces: the @font-face rules for every family the figure or its
    # tokens name, so JetBrains Mono is the face it was measured in and not a
    # guess. Each family stack still ends in a generic, so a font that fails
    # to load costs the metrics and not the text.
    def stylesheet(body, root)
      names = token_closure(body)
      light = declarations(@theme[:light], names)
      dark = declarations(@theme[:dark], names)
      faces = @theme[:faces].select do |face|
        family = face[/font-family:\s*["']?([^"';]+)/, 1]
        family && (body.include?(family) || light.include?(family))
      end

      css = [":root{#{light}color-scheme:light dark;background:var(--paper);" \
             "color:var(--ink);font-family:var(--serif);#{window_size(root)}}"]
      css << "@media (prefers-color-scheme: dark){:root{#{dark}}}" unless dark.empty?
      css.concat(faces).join("\n")
    end

    # The tokens a figure reads, and the tokens those read, until nothing new
    # turns up. --accent-wash is a literal today, but a token defined in terms
    # of another would otherwise arrive in the copy pointing at nothing.
    def token_closure(body)
      names = Set.new(BASE_TOKENS) + body.scan(VAR_REFERENCE).flatten
      loop do
        found = names.flat_map do |name|
          [@theme[:light][name], @theme[:dark][name]].compact.flat_map { |v| v.scan(VAR_REFERENCE).flatten }
        end
        added = found.to_set - names
        break if added.empty?

        names.merge(added)
      end
      names
    end

    def declarations(tokens, names)
      names.select { |name| tokens.key?(name) }.map { |name| "#{name}:#{tokens[name]};" }.join
    end

    # The copy fills the window, scaled up to it with its proportions kept,
    # and is never drawn smaller than its natural size. Every figure on these
    # pages is drawn about as wide as the column, so its natural size is what
    # the reader already had; filling the window is what makes the copy
    # larger. The floor is for a graph bigger than the window, which then
    # scrolls at full size instead of shrinking to fit.
    #
    # The natural size is the root's own width and height when they are
    # absolute lengths -- matplotlib writes points -- and its viewBox in user
    # units otherwise. graphviz.rb strips the points Graphviz wrote, so a
    # diagram lands here and is drawn at one CSS pixel per point.
    def window_size(root)
      width, height = attribute(root, "width"), attribute(root, "height")
      size = [length(width), length(height)]

      if size.any?(&:nil?)
        box = attribute(root, "viewBox").to_s.split(/[\s,]+/)
        return "" unless box.size == 4

        size = [length(box[2]), length(box[3])]
      end
      return "" if size.any?(&:nil?)

      "width:100% !important;height:100% !important;" \
        "min-width:#{size[0]} !important;min-height:#{size[1]} !important;" \
        "max-width:none !important;max-height:none !important;"
    end

    def attribute(tag, name)
      tag[/\s#{name}\s*=\s*"([^"]*)"/, 1] || tag[/\s#{name}\s*=\s*'([^']*)'/, 1]
    end

    # SVG's unitless length is a CSS pixel.
    def length(value)
      number, unit = value.to_s.match(ABSOLUTE_LENGTH)&.captures
      return nil if number.nil?

      "#{number}#{unit || "px"}"
    end

    # --- The theme, out of the compiled stylesheet ---------------------------

    # Read rather than repeated here, so a change to the palette in
    # _sass/style.scss reaches the standalone copies on the next build.
    #
    # Light tokens are every :root block at the top level; the tokens and the
    # syntax palette each have one. Dark tokens are every :root inside a
    # prefers-color-scheme: dark query. A :root inside any other query -- the
    # layout breakpoints, print -- is neither, and is told apart by the "{"
    # that opens the query in front of it.
    def read_theme
      css = @site.pages.find { |page| page.url == STYLESHEET_URL }&.output
      raise "#{STYLESHEET_URL} not found" if css.nil?

      light = {}
      css.to_enum(:scan, /:root\s*\{([^}]*)\}/).each do
        match = Regexp.last_match
        next if css[0...match.begin(0)].rstrip.end_with?("{")

        light.merge!(tokens(match[1]))
      end

      dark = {}
      css.scan(/@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)\s*\{\s*:root\s*\{([^}]*)\}/) do |(block)|
        dark.merge!(tokens(block))
      end

      raise "no theme tokens in #{STYLESHEET_URL}" if light.empty? || dark.empty?

      { light: light, dark: dark, faces: css.scan(/@font-face\s*\{[^}]*\}/) }
    rescue StandardError => e
      @warnings << "could not read the theme (#{e.message}); figures left unlinked"
      nil
    end

    def tokens(block)
      block.split(";").each_with_object({}) do |declaration, out|
        name, value = declaration.split(":", 2).map(&:strip)
        out[name] = value if name&.start_with?("--") && value && !value.empty?
      end
    end

    # --- Reporting ------------------------------------------------------------

    # A count on success for the same reason graphviz.rb gives one: silence is
    # indistinguishable from the hook never having run.
    def report
      if @linked.positive?
        Jekyll.logger.info "Figures:", "#{@linked} figure(s) linked to #{@published.size} standalone SVG(s)"
      end
      if @pictured.positive?
        Jekyll.logger.info "Figures:", "#{@pictured} figure(s) in the feed drawn as <img>"
      end

      @warnings.each { |warning| Jekyll.logger.warn "Figures:", warning }
    end
  end
end

# After graphviz.rb and plotnine.rb, which turn their fences into the
# <figure><svg> this looks for. Hooks of equal priority run in the order their
# files load, which is alphabetical and would put this one first.
Jekyll::Hooks.register :site, :post_render, priority: :low do |site|
  Figures.process(site)
end
