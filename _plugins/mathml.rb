# frozen_string_literal: true

require "digest"
require "fileutils"
require "kramdown"
require "open3"

# Turns kramdown's $$...$$ math into MathML at build time, with latex2mathml.
#
# Kramdown already parses the math. On its own it writes the TeX back out
# between \( and \) for MathJax to typeset in the browser, and this site loads
# no MathJax, so a reader would see the raw TeX. Every browser the site cares
# about has drawn MathML natively since 2023, so the TeX can become MathML
# here instead, and the page ships no script for it.
#
#     There are $$\binom{6}{3} = 20$$ orderings.
#
#     $$
#     \sum_{i=1}^{n} i = \frac{n(n+1)}{2}
#     $$
#
# The first is inline: $$...$$ inside a paragraph. The second is display
# math: $$...$$ as a paragraph of its own. That split is kramdown's, not this
# plugin's.
#
# This replaces kramdown's built-in mathjax engine instead of registering one
# under a new name. Jekyll requires a gem called kramdown-math-<name> for any
# engine other than mathjax, so a new name would need a gem that exists only to
# satisfy that require. Taking over mathjax also means no config change: it is
# kramdown's default engine.
#
# The conversion happens inside kramdown, so jekyll-feed, which takes a
# post's converted content, carries the MathML too. Whether a feed reader
# keeps a <math> element is up to the reader.
#
# Conversions are cached. Starting Python for one expression costs more than
# the conversion itself, and an expression changes far less often than the
# prose around it.
#
# Jekyll caches too: .jekyll-cache keeps kramdown's HTML for each page, keyed
# on the page's markdown. A change to this file alone therefore shows up only
# on pages whose text changed, until `jekyll clean` or a build with
# --disable-disk-cache. The Nix build starts with no cache and is unaffected.
module MathML
  CACHE_DIR = ".mathml-cache"

  # Converts the TeX on stdin and prints the MathML. The display mode is the
  # one argument: "inline" or "block", exactly the values latex2mathml takes.
  HARNESS = <<~PYTHON
    import sys

    from latex2mathml.converter import convert

    sys.stdout.write(convert(sys.stdin.read(), display=sys.argv[1]))
  PYTHON

  # The two kinds of math kramdown parses, named by the value latex2mathml
  # takes for each.
  module Display
    INLINE = "inline"
    BLOCK = "block"
  end

  def self.call(converter, el, opts)
    display = el.options[:category] == :block ? Display::BLOCK : Display::INLINE
    math = converter_instance.convert(el.value, display)

    # An IAL after the math lands on a wrapper, since the attributes belong to
    # the author's markup and not to the <math> latex2mathml writes.
    return math if el.attr.empty?

    if display == Display::BLOCK
      converter.format_as_block_html("div", el.attr, math, opts[:indent])
    else
      converter.format_as_span_html("span", el.attr, math)
    end
  end

  # One converter for the whole build, so the interpreter is probed once and
  # the counts below add up across every page.
  def self.converter_instance
    @converter_instance ||= Converter.new
  end

  def self.report
    converter_instance.report
  end

  class Converter
    def initialize
      @converted = 0
      @reused = 0
    end

    def convert(tex, display)
      require_python

      key = Digest::SHA256.hexdigest("#{version}\0#{HARNESS}\0#{display}\0#{tex}")
      unsize(cached(key) { run(tex, display) })
    end

    def report
      total = @converted + @reused
      return if total.zero?

      Jekyll.logger.info "MathML:", "#{total} expression(s); #{@converted} converted, #{@reused} cached"
      @converted = 0
      @reused = 0
    end

    private

    # The cache lives beside the source, like the graphviz and plotnine
    # caches. Jekyll is not consulted because this runs inside kramdown, which
    # knows nothing of the site; the working directory is the source in every
    # way this site is built.
    def cached(key)
      path = File.join(CACHE_DIR, "#{key}.mathml")
      if File.exist?(path)
        @reused += 1
        return File.read(path, encoding: Encoding::UTF_8)
      end

      math = yield
      @converted += 1
      FileUtils.mkdir_p(CACHE_DIR)
      File.write(path, math, encoding: Encoding::UTF_8)
      math
    end

    # latex2mathml gives the brackets of a \binom a fixed minsize and maxsize
    # of 2.047em, the height of a display-style binomial, whatever the display
    # mode. Inline, that is a bracket twice the height of the line around a
    # fraction drawn at script size, and the paragraph's leading opens up to
    # fit it. Without the fixed size a bracket stretches to what it encloses,
    # the way TeX sizes it. Applied on read, like plotnine's theming, so a
    # change here needs no new .mathml-cache entries.
    def unsize(math)
      math.gsub(/ (?:minsize|maxsize)="[^"]*"/, "")
    end

    # Math that fails to convert stops the build, the same way a chart that
    # fails to draw does: otherwise the post ships with a hole in a sentence.
    def run(tex, display)
      output, errors, status = Open3.capture3(python, "-c", HARNESS, display, stdin_data: tex)
      return output if status.success?

      raise "MathML: cannot convert $$#{tex}$$\n#{errors}"
    end

    # The latex2mathml version rather than Python's: an upgrade of the
    # converter is what changes the markup.
    def version
      @version ||= Open3.capture2e(
        python, "-c", "import importlib.metadata as m; print(m.version('latex2mathml'))"
      ).first.strip
    end

    # latex2mathml is a build dependency for the same reason plotnine is:
    # carrying on without it would print raw TeX in the middle of a sentence.
    # nix/python.nix provides it.
    def require_python
      return if @checked

      probe, status = Open3.capture2e(python, "-c", "import latex2mathml")
      raise "MathML: #{python} cannot import latex2mathml\n#{probe}" unless status.success?

      @checked = true
    end

    # The same override plotnine.rb reads, so one interpreter serves both.
    def python
      @python ||= ENV.fetch("JEKYLL_PYTHON", "python3")
    end
  end
end

Kramdown::Converter.add_math_engine(:mathjax, MathML)

Jekyll::Hooks.register :site, :post_render do
  MathML.report
end
