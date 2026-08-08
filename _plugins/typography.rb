# frozen_string_literal: true

# Build-time typography passes over the rendered HTML.
#
# Everything here exists so that the browser does no work at runtime — the site
# ships zero JavaScript, so anything that would normally need a script has to
# happen once, here, at build time.
#
#   1. Footnotes are lifted out of the endnote list and planted next to the
#      sentence that references them, so they can be floated into the right
#      margin as Tufte-style sidenotes.
#   2. Rouge's `language-foo` wrapper gets a `data-lang` attribute so the
#      stylesheet can print the language on the code block.
#   3. Tables are wrapped in a scroll container so a wide table scrolls itself
#      instead of the whole page.
module Typography
  # <div class="footnotes" role="doc-endnotes"><ol> ... </ol></div>
  FOOTNOTES = %r{<div class="footnotes"[^>]*>\s*<ol>(.*?)</ol>\s*</div>}m

  # <li id="fn:1"> ... </li>, split apart rather than matched greedily so that
  # a footnote containing its own list still comes out whole.
  NOTE = %r{\A<li id="fn:([^"]+)"[^>]*>(.*)</li>\s*\z}m

  # The "↩" backlink kramdown appends; pointless once the note is in the margin.
  BACKLINK = %r{\s*<a href="\#fnref:[^"]*"[^>]*class="reversefootnote"[^>]*>.*?</a>}m

  # <sup id="fnref:1"><a href="#fn:1" ...>1</a></sup>
  REF = %r{<sup id="fnref:([^"]+?)(?::\d+)?"[^>]*>\s*<a href="\#fn:[^"]*"[^>]*>(.*?)</a>\s*</sup>}m

  # A sidenote is a <span> living inside the referencing <p>, so its body may
  # only contain phrasing content. A stray block element would make the parser
  # close the paragraph early and spill the note into the main column, so any
  # note containing one disqualifies the whole page.
  BLOCK_ELEMENT = %r{<(?:div|ul|ol|li|pre|table|blockquote|figure|h[1-6])[\s>]}i

  # Kramdown already gives every heading an id; this turns the § that hangs in
  # the gutter into a link to it, so a section can be cited directly.
  HEADING = %r{<(h[1-3]) id="([^"]+)">}

  CODE_BLOCK = %r{<div class="language-([A-Za-z0-9_+#-]+) highlighter-rouge">}

  # Languages where a label would be noise rather than information.
  UNLABELLED = %w[text plaintext plain console output].freeze

  module_function

  def apply(html)
    html = sidenotes(html)
    html = heading_anchors(html)
    html = code_labels(html)
    scrollable_tables(html)
  end

  def heading_anchors(html)
    html.gsub(HEADING) do
      tag = Regexp.last_match(1)
      id = Regexp.last_match(2)

      %(<#{tag} id="#{id}">) +
        %(<a class="hanchor" href="##{id}" aria-label="Permalink to this section">§</a>)
    end
  end

  # Move each footnote's body inline, immediately after its reference marker.
  #
  # This is all-or-nothing on purpose: if any note cannot be paired with a
  # reference the whole page falls back to the ordinary endnote list rather
  # than showing some notes twice.
  def sidenotes(html)
    match = html.match(FOOTNOTES)
    return html if match.nil?

    notes = parse_notes(match[1])
    return html if notes.empty?

    placed = {}
    rewritten = html.sub(FOOTNOTES, "").gsub(REF) do
      id = Regexp.last_match(1)
      label = Regexp.last_match(2)
      body = notes[id]

      if body.nil?
        Regexp.last_match(0)
      elsif placed.key?(id)
        # A second reference to the same note: marker only, no duplicate body.
        %(<sup class="sn-ref">#{label}</sup>)
      else
        placed[id] = true
        %(<sup class="sn-ref">#{label}</sup>) +
          %(<span class="sidenote"><span class="sn-num">#{label}</span>#{body}</span>)
      end
    end

    # Every note found a home, or we keep the original markup untouched.
    placed.size == notes.size ? rewritten : html
  end

  def parse_notes(list)
    notes = {}

    list.split(/(?=<li id="fn:)/).each do |chunk|
      chunk = chunk.strip
      next if chunk.empty?

      m = chunk.match(NOTE)
      next if m.nil?

      body = m[2].gsub(BACKLINK, "").strip
      return {} if body.match?(BLOCK_ELEMENT)

      notes[m[1]] = phrasing(body)
    end

    notes
  end

  # Paragraphs become spans so the note stays legal inside its host paragraph.
  def phrasing(body)
    body.gsub(/<p(\s[^>]*)?>/) { %(<span class="sn-p"#{Regexp.last_match(1)}>) }
        .gsub("</p>", "</span>")
  end

  def code_labels(html)
    html.gsub(CODE_BLOCK) do
      lang = Regexp.last_match(1)
      next Regexp.last_match(0) if UNLABELLED.include?(lang.downcase)

      %(<div class="language-#{lang} highlighter-rouge" data-lang="#{lang}">)
    end
  end

  def scrollable_tables(html)
    return html unless html.include?("<table")

    html
      .gsub(/<table(\s[^>]*)?>/) { %(<div class="table-scroll"><table#{Regexp.last_match(1)}>) }
      .gsub("</table>", "</table></div>")
  end
end

# Strips footnote machinery out of a rendered fragment.
#
# An excerpt is rendered on its own, so kramdown numbers its footnotes from
# scratch and appends the whole endnote list to it. `Typography.apply` never
# sees that fragment — the `post_render` hook below only fires for documents
# and pages — so the index page would otherwise print the citations as part of
# the teaser. This filter drops both the endnote list and the superscript
# markers that point at it, leaving just the prose.
module Jekyll
  module FootnoteFilter
    def strip_footnotes(input)
      return input if input.nil?

      input.to_s.gsub(Typography::FOOTNOTES, "").gsub(Typography::REF, "")
    end
  end
end

Liquid::Template.register_filter(Jekyll::FootnoteFilter)

Jekyll::Hooks.register %i[documents pages], :post_render do |doc|
  next unless doc.output_ext == ".html"

  doc.output = Typography.apply(doc.output)
end
