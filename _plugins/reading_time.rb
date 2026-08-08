# frozen_string_literal: true

# A Liquid filter that drops code blocks before a word count is taken.
#
# The reading estimate in _layouts/post.html counts `content`, which at layout
# time is rendered HTML but *not* yet post-processed: _plugins/plotnine.rb and
# _plugins/graphviz.rb both run at :site, :post_render, which is after layouts
# are applied. So a ```plotnine fence is still its Python source when the count
# happens, and a ```graphviz fence is still its DOT. Neither is prose, and a
# fence that carries a data table -- the multiverse post inlines 1,391 revision
# dates as digits -- reads as a couple of thousand words that nobody will ever
# read. That post was estimated at 21 minutes, of which roughly seven were the
# digits.
#
# Everything between <pre> and </pre> goes, which covers both shapes kramdown
# emits: the <div class="highlight"><pre><code> nesting Rouge produces, and the
# bare <pre><code class="language-x"> that comes back with the highlighter off.
# Graphviz's own fence regexes match the same two for the same reason.
#
# Inline <code> is deliberately kept. A backticked identifier in a sentence is
# read like any other word, and stripping it would undercount prose that talks
# about code, which is most of what is written here.
module ReadingTime
  # Non-greedy so that two fences in a row are two matches rather than one that
  # swallows the prose between them. //m so a block spanning lines is matched.
  CODE_BLOCK = %r{<pre\b.*?</pre>}m

  module Filters
    def strip_code_blocks(input)
      input.to_s.gsub(CODE_BLOCK, " ")
    end
  end
end

Liquid::Template.register_filter(ReadingTime::Filters)
