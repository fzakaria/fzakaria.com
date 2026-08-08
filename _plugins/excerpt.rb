# Turns a rendered excerpt into a short teaser that keeps its inline typography.
#
# `strip_html` used to do this job, but it is all-or-nothing: it removed the
# figure a post opens with and, with it, every link, emphasis and code span in
# the teaser. This filter drops the things that cannot sit in a one-line card
# and keeps the things that carry meaning.
#
# Liquid's own `truncate` is not usable once tags survive, because it counts
# markup as characters and will happily cut through the middle of a tag. The
# truncation here counts only visible text and closes whatever is still open.
module Jekyll
  module ExcerptFilter
    # Dropped with their contents: a teaser has no room for them, and an
    # image or a plot would blow the card apart.
    DROP_WHOLE = %w[script style svg figure pre blockquote table video audio iframe noscript].freeze

    # Kept, because each one changes how the sentence reads. Attributes are
    # dropped from all of them except `a`, which keeps its href — the index
    # card stretches its title link rather than wrapping the whole teaser, so
    # a link in here is legal and clickable. See `.index-lead` in style.scss.
    KEEP = %w[a strong b em i code u del s sub sup mark abbr].freeze

    # Everything else is unwrapped rather than deleted, so its text survives.
    TAG = /<\/?\s*([a-z0-9]+)(?:\s[^>]*)?>/i

    def excerpt_html(input, max_chars = 240)
      return "" if input.nil?

      html = input.to_s
      html = drop_whole_elements(html)
      html = unwrap_foreign_tags(html)
      html = html.gsub(/\s+/, " ").strip

      truncate_html(html, max_chars.to_i)
    end

    private

    # Removes an element and everything inside it. Void elements such as <img>
    # have no closing tag, so they are matched on their own.
    def drop_whole_elements(html)
      DROP_WHOLE.each do |tag|
        html = html.gsub(%r{<#{tag}\b[^>]*>.*?</#{tag}>}mi, " ")
        html = html.gsub(%r{<#{tag}\b[^>]*/?>}i, " ")
      end

      html.gsub(%r{<(?:img|br|hr|source|track)\b[^>]*/?>}i, " ")
    end

    # Strips the tags we do not keep while leaving their text in place, and
    # drops attributes from the ones we do keep. An anchor keeps its href, and
    # loses the anchor entirely if it has none, so no empty <a> survives.
    def unwrap_foreign_tags(html)
      html.gsub(TAG) do |match|
        name = Regexp.last_match(1).downcase
        next "" unless KEEP.include?(name)
        next(match.start_with?("</") ? "</#{name}>" : "<#{name}>") unless name == "a"
        next "</a>" if match.start_with?("</")

        # Already escaped by the renderer, so it goes back verbatim. An anchor
        # with no href still opens, otherwise its closing tag is left stranded.
        href = match[/\shref\s*=\s*"([^"]*)"/i, 1] || match[/\shref\s*=\s*'([^']*)'/i, 1]
        href ? %(<a href="#{href}">) : "<a>"
      end
    end

    # Truncates on visible characters, then closes any tag left open so the
    # fragment is still well-formed.
    def truncate_html(html, max)
      return html if max <= 0

      out = +""
      open = []
      visible = 0

      html.scan(/<[^>]+>|[^<]+/) do |token|
        if token.start_with?("<")
          name = token[%r{</?\s*([a-z0-9]+)}i, 1].downcase

          if token.start_with?("</")
            open.pop if open.last == name
          else
            open.push(name)
          end

          out << token
          next
        end

        room = max - visible
        if token.length <= room
          out << token
          visible += token.length
          next
        end

        # Cut on a word boundary rather than mid-word.
        out << token[0, room].sub(/\s+\S*\z/, "") << "…"
        visible = max
        break
      end

      out << open.reverse.map { |name| "</#{name}>" }.join
      out
    end
  end
end

Liquid::Template.register_filter(Jekyll::ExcerptFilter)
