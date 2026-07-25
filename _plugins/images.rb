# frozen_string_literal: true

require "open3"
require "fileutils"

# Image handling, done once at build time so the browser does no work and the
# author does no resizing.
#
# For every local <img> in the rendered HTML this:
#
#   1. reads the real pixel dimensions out of the file header (pure Ruby, no
#      dependencies) and writes them onto the tag, so the browser reserves the
#      right box and the page stops shifting as images arrive;
#   2. adds loading="lazy" and decoding="async";
#   3. generates down-scaled derivatives with ImageMagick and points the tag at
#      them via srcset, so a 4152px screenshot is never sent to a 700px column.
#
# The ladder is not hardcoded: the widths and the `sizes` attribute are derived
# from the compiled stylesheet, which publishes --measure, --root-max and
# --layout-breakpoint for exactly this purpose. Widen the prose column and the
# images follow on the next build.
#
# ImageMagick is optional. Without it, steps 1 and 2 still happen and the build
# logs which images are larger than they can ever display.
module Images
  # Used only when the stylesheet cannot be read, so that a CSS refactor
  # degrades to the previous behaviour instead of producing nonsense.
  FALLBACK_COLUMN_PX = 700
  FALLBACK_BREAKPOINT_PX = 1081

  # 1x and 2x. A 3x tier is not worth the bytes at this column width.
  DENSITIES = [1, 2].freeze

  STYLESHEET_URL = "/assets/css/base.css"

  # Media queries resolve rem against the initial font size, not the root's.
  MEDIA_QUERY_REM = 16.0

  CACHE_DIR = ".image-cache"
  DERIVED_DIR = "assets/images/derived"

  RESIZABLE = %w[.png .jpg .jpeg .webp].freeze

  # Down-scaling a flat diagram re-encodes it as truecolour and the file often
  # comes out *larger* than the original. Re-quantising to a 256-colour palette
  # undoes that — typically a 60-70% saving — but it would visibly band a
  # photograph. Rather than guess from the file name or the colour count, the
  # two candidates are compared and the palette version is only kept when the
  # measured distortion is inaudible to the eye. 45 dB PSNR is comfortably
  # inside "indistinguishable" for synthetic images; the photographs in this
  # repo land between 32 and 43 dB and are correctly left alone.
  QUANTISE_MIN_PSNR = 45.0

  # WebP is offered alongside the original format via <picture>, which is the
  # only mechanism that negotiates *format* — srcset varies size only and has
  # no way to say "this file is WebP", so a browser that could not decode it
  # would still pick it and fail.
  #
  # The bar is lower than QUANTISE_MIN_PSNR because this comparison is against
  # a lossy encoder rather than a near-lossless palette: 36 dB is the usual
  # "fine for web imagery" line, where JPEG at q80 also lands. Detailed line
  # art fails it — the dependency graph in this repo measures 18 dB — and
  # simply keeps its PNG.
  WEBP_MIN_PSNR = 36.0
  WEBP_QUALITY = "82"

  IMG_TAG = %r{<img\s+([^>]*?)\s*/?>}i
  ATTRIBUTE = /([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*"([^"]*)"/

  class << self
    def process(site)
      @site = site
      @plans = {}
      @warnings = []
      @layout = read_layout(site)

      documents(site).each { |doc| scan(doc.output) }
      build_derivatives
      documents(site).each { |doc| doc.output = rewrite(doc.output) }
      register_static_files
      report
    end

    private

    # --- Layout, taken from the stylesheet rather than repeated here ---------

    def read_layout(site)
      css = site.pages.find { |page| page.url == STYLESHEET_URL }&.output
      raise "#{STYLESHEET_URL} not found" if css.nil?

      measure = css[/--measure:\s*([\d.]+)rem/, 1]
      root_max = css[/--root-max:\s*([\d.]+)px/, 1]
      breakpoint = css[/--layout-breakpoint:\s*([\d.]+)rem/, 1]
      raise "layout custom properties missing" if [measure, root_max, breakpoint].any?(&:nil?)

      {
        column: (Float(measure) * Float(root_max)).round,
        breakpoint: (Float(breakpoint) * MEDIA_QUERY_REM).round,
      }
    rescue StandardError => e
      @warnings << "could not read layout from the stylesheet (#{e.message}); using defaults"
      { column: FALLBACK_COLUMN_PX, breakpoint: FALLBACK_BREAKPOINT_PX }
    end

    # The srcset ladder: the rendered column at each pixel density.
    def widths
      @widths ||= DENSITIES.map { |density| @layout[:column] * density }
    end

    # How wide the image actually renders: the column above the layout
    # breakpoint, the full viewport below it.
    def sizes
      @sizes ||= "(min-width: #{@layout[:breakpoint]}px) #{@layout[:column]}px, 100vw"
    end

    def documents(site)
      (site.documents + site.pages).select { |doc| doc.output_ext == ".html" && doc.output }
    end

    # --- Pass one: find every local image and work out what it needs ---------

    def scan(html)
      html.scan(IMG_TAG) do |(raw_attrs)|
        src = attributes(raw_attrs)["src"]
        next if src.nil?

        plan_for(src)
      end
    end

    def plan_for(src)
      return @plans[src] if @plans.key?(src)

      @plans[src] = nil
      return nil unless src.start_with?("/assets/")

      source = source_path(src)
      return nil if source.nil?

      size = Dimensions.of(source)
      return nil if size.nil?

      width, height = size
      @plans[src] = {
        source: source,
        width: width,
        height: height,
        ext: File.extname(source).downcase,
        rel: src.sub(%r{\A/assets/images/}, ""),
        derivatives: [],
        webp: [],
      }
    end

    def source_path(src)
      relative = src.sub(%r{\A/}, "")
      [relative, Addressable::URI.unencode(relative)].uniq.each do |candidate|
        path = File.join(@site.source, candidate)
        return path if File.file?(path)
      end
      nil
    rescue StandardError
      path = File.join(@site.source, src.sub(%r{\A/}, ""))
      File.file?(path) ? path : nil
    end

    # --- Pass two: generate the derivatives ---------------------------------

    def build_derivatives
      wanted = @plans.values.compact.select do |plan|
        RESIZABLE.include?(plan[:ext]) && plan[:width] > widths.first
      end
      return if wanted.empty?

      if tool.nil?
        wanted.each do |plan|
          @warnings << "#{plan[:rel]} is #{plan[:width]}px wide but displays at most #{widths.first}px"
        end
        return
      end

      wanted.each { |plan| generate(plan) }
    end

    def generate(plan)
      # What would be served at each width if WebP were not on the table: the
      # same-format derivative when it is a win, the original otherwise. Also
      # remembers a same-size file to measure WebP's distortion against, since
      # `compare` needs both images at identical dimensions.
      baseline = {}

      widths.each do |width|
        # No point emitting a variant that is larger than the original.
        next if width > plan[:width]

        name = derivative_name(plan[:rel], width)
        target = File.join(cache_root, name)

        unless fresh?(target, plan[:source])
          FileUtils.mkdir_p(File.dirname(target))
          next unless resize(plan[:source], target, width, plan[:ext])
        end

        # Re-encoding can make a file bigger — an indexed-palette PNG comes
        # back as truecolour, a small JPEG comes back less aggressively
        # compressed. Only reference a derivative that is an actual win. The
        # rejected file stays in the cache so the work is not repeated.
        accepted = File.size(target) < File.size(plan[:source])
        plan[:derivatives] << { width: width, name: name } if accepted

        baseline[width] = {
          reference: target,
          bytes: File.size(accepted ? target : plan[:source]),
        }
      end

      generate_webp(plan, baseline)
    end

    # A WebP tier offered through <picture>. The originals that survive the
    # palette step are the photographic ones, and PNG is simply the wrong
    # container for those.
    def generate_webp(plan, baseline)
      return if plan[:ext] == ".webp"

      wanted = webp_widths(plan)
      accepted = wanted.filter_map do |width|
        name = derivative_name(plan[:rel], width).sub(/\.\w+\z/, ".webp")
        target = File.join(cache_root, name)

        unless fresh?(target, plan[:source])
          FileUtils.mkdir_p(File.dirname(target))
          next unless encode_webp(plan[:source], target, width)
        end

        # At the original's own width there is no same-format derivative, so
        # the original itself is both the size baseline and the reference —
        # and it is already the right dimensions to compare against.
        against = baseline[width] || { reference: plan[:source], bytes: File.size(plan[:source]) }

        next unless File.size(target) < against[:bytes]
        next unless File.exist?(against[:reference])
        next unless distortion_db(against[:reference], target) >= WEBP_MIN_PSNR

        { width: width, name: name }
      end

      # All or nothing. A partial ladder is worse than none: <source> wins over
      # the <img> whenever the browser understands WebP, so if the small rung
      # were missing a phone would be handed the large one instead of the
      # correctly-sized PNG it would otherwise have picked.
      plan[:webp] = accepted if accepted.size == wanted.size
    end

    # As the same-format ladder, plus the original's own width when it falls
    # short of the top rung — otherwise a <picture> would cap a retina display
    # below the resolution the plain <img> fallback could have given it.
    def webp_widths(plan)
      list = widths.select { |width| width <= plan[:width] }
      list << plan[:width] if plan[:width] < widths.last
      list.uniq.sort
    end

    def encode_webp(source, target, width)
      command = [tool, source, "-auto-orient", "-strip",
                 "-resize", "#{width}x>", "-quality", WEBP_QUALITY, target]
      ok = system(*command, out: File::NULL, err: File::NULL)
      @warnings << "could not encode #{File.basename(target)}" unless ok
      ok
    end

    def cache_root
      @cache_root ||= File.join(@site.source, CACHE_DIR, DERIVED_DIR)
    end

    def derivative_name(rel, width)
      dir = File.dirname(rel)
      base = File.basename(rel, ".*")
      ext = File.extname(rel)
      name = "#{base}-#{width}w#{ext}"
      dir == "." ? name : File.join(dir, name)
    end

    def fresh?(target, source)
      File.file?(target) && File.mtime(target) >= File.mtime(source)
    end

    def resize(source, target, width, ext)
      # `>` means "only shrink". No shell is involved, so it needs no quoting.
      command = [tool, source, "-auto-orient", "-strip",
                 "-resize", "#{width}x>", *encoding(ext), target]
      ok = system(*command, out: File::NULL, err: File::NULL)
      unless ok
        @warnings << "could not resize #{source}"
        return false
      end

      quantise(target, ext)
      true
    end

    # Replace the derivative with a palette version when doing so is both
    # smaller and visually indistinguishable.
    def quantise(target, ext)
      return unless ext == ".png"

      candidate = "#{target}.pal.png"
      return unless system(tool, target, "+dither", "-colors", "256",
                           "-quality", "95", "-define", "png:compression-level=9",
                           candidate, out: File::NULL, err: File::NULL)

      if File.size(candidate) < File.size(target) && distortion_db(target, candidate) >= QUANTISE_MIN_PSNR
        FileUtils.mv(candidate, target)
      else
        FileUtils.rm_f(candidate)
      end
    rescue StandardError
      FileUtils.rm_f(candidate)
    end

    # Distortion between two same-sized images, in decibels.
    #
    # Measured as RMSE and converted rather than asking for PSNR directly:
    # ImageMagick 7.1.1 — the version this flake pins — reports PSNR wildly
    # out of scale (25059 dB for an image that is visibly wrecked), so a
    # "must exceed 36 dB" gate silently accepts everything. Its normalised
    # RMSE agrees with newer versions to the last digit, and PSNR is just
    # -20·log10 of it, so this keeps the thresholds in familiar units while
    # being stable across whatever ImageMagick the build happens to find.
    #
    # `compare` exits non-zero whenever the images differ at all, so the exit
    # status carries no information — only the metric on stderr does.
    #
    # A failure must not break the build, but it must not pass silently
    # either: returning "infinitely distorted" without a word is how a plain
    # NameError once disabled this whole step unnoticed.
    def distortion_db(a, b)
      command = tool.end_with?("magick") ? [tool, "compare"] : ["compare"]
      _out, err, = Open3.capture3(*command, "-metric", "RMSE", a, b, "null:")

      # "8355.18 (0.127492)" — the parenthesised figure is normalised to 0..1.
      # ImageMagick may print its own diagnostics first, so search the whole
      # output rather than assuming which line it lands on.
      normalised = err.to_s[/\(([\d.eE+-]+)\)/, 1]
      raise ArgumentError, "no metric in #{err.to_s.strip.inspect}" if normalised.nil?

      value = Float(normalised)
      return Float::INFINITY if value <= 0

      -20 * Math.log10(value)
    rescue StandardError => e
      @warnings << "could not measure #{File.basename(a)}: #{e.class}: #{e.message}"
      -Float::INFINITY
    end

    # For PNG, ImageMagick reads -quality as two digits: zlib compression level
    # and filter type. 95 is "compress hard, adaptive filter", which is a very
    # different thing from 95 on a lossy format.
    def encoding(ext)
      case ext
      when ".png" then ["-quality", "95", "-define", "png:compression-level=9"]
      else ["-quality", "82", "-interlace", "none"]
      end
    end

    def tool
      return @tool if defined?(@tool)

      @tool = %w[magick convert].filter_map { |bin| which(bin) }.first
    end

    def which(bin)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, bin)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    # --- Pass three: rewrite the tags ---------------------------------------

    def rewrite(html)
      html.gsub(IMG_TAG) do
        raw = Regexp.last_match(1)
        attrs = attributes(raw)
        plan = @plans[attrs["src"]]

        attrs["loading"] ||= "lazy"
        attrs["decoding"] ||= "async"

        next "<img #{serialize(attrs)}>" if plan.nil?

        attrs["width"] ||= plan[:width].to_s
        attrs["height"] ||= plan[:height].to_s
        already_authored = attrs.key?("srcset")
        apply_srcset(attrs, plan)

        tag = "<img #{serialize(attrs)}>"
        already_authored ? tag : wrap_in_picture(tag, plan)
      end
    end

    def apply_srcset(attrs, plan)
      return if plan[:derivatives].empty?
      return if attrs.key?("srcset")

      candidates = plan[:derivatives].map do |derivative|
        { url: derivative_url(derivative[:name]), width: derivative[:width] }
      end

      # If the original is smaller than the 2x variant we would have liked,
      # keep it in the running: dropping it would leave a retina display with
      # less detail than it had before this plugin existed.
      candidates << { url: attrs["src"], width: plan[:width] } if plan[:width] < widths.last

      attrs["srcset"] = candidates.map { |c| "#{c[:url]} #{c[:width]}w" }.join(", ")
      attrs["sizes"] ||= sizes
      # Point src at the largest candidate, so an oversized original is only
      # ever fetched when a post links to it directly.
      attrs["src"] = candidates.max_by { |c| c[:width] }[:url]
    end

    # The <img> stays exactly as it was and becomes the fallback; browsers that
    # understand WebP take the <source> instead.
    def wrap_in_picture(tag, plan)
      return tag if plan[:webp].empty?

      srcset = plan[:webp].map { |w| "#{derivative_url(w[:name])} #{w[:width]}w" }.join(", ")
      %(<picture><source type="image/webp" srcset="#{srcset}" sizes="#{sizes}">#{tag}</picture>)
    end

    def derivative_url(name)
      "/#{DERIVED_DIR}/#{name}"
    end

    def attributes(raw)
      raw.scan(ATTRIBUTE).to_h
    end

    def serialize(attrs)
      attrs.map { |key, value| %(#{key}="#{value}") }.join(" ")
    end

    # --- Wiring and reporting ------------------------------------------------

    def register_static_files
      @plans.values.compact.each do |plan|
        (plan[:derivatives] + plan[:webp]).each do |derivative|
          dir = File.join("/", DERIVED_DIR, File.dirname(derivative[:name]))
          @site.static_files << Jekyll::StaticFile.new(
            @site,
            File.join(@site.source, CACHE_DIR),
            dir,
            File.basename(derivative[:name]),
          )
        end
      end
    end

    def report
      plans = @plans.values.compact
      resized = plans.sum { |plan| plan[:derivatives].size }
      webp = plans.sum { |plan| plan[:webp].size }
      if resized.positive? || webp.positive?
        Jekyll.logger.info "Images:",
                           "#{resized} resized + #{webp} webp for #{plans.size} image(s); " \
                           "column #{@layout[:column]}px, breakpoint #{@layout[:breakpoint]}px"
      end

      return if @warnings.empty?

      Jekyll.logger.warn "Images:", "ImageMagick not found; serving originals" if tool.nil?
      @warnings.first(10).each { |warning| Jekyll.logger.warn "Images:", warning }
      Jekyll.logger.warn "Images:", "...and #{@warnings.size - 10} more" if @warnings.size > 10
    end
  end

  # Pixel dimensions straight out of the file header. Deliberately dependency
  # free so that dimensions (and therefore layout stability) still work on a
  # machine without ImageMagick.
  module Dimensions
    module_function

    def of(path)
      File.open(path, "rb") do |io|
        head = io.read(32)
        return nil if head.nil? || head.bytesize < 16

        if head.start_with?("\x89PNG\r\n\x1a\n".b) then png(head)
        elsif head.start_with?("GIF8".b) then gif(head)
        elsif head.start_with?("\xFF\xD8".b) then jpeg(io)
        elsif head[0, 4] == "RIFF".b && head[8, 4] == "WEBP".b then webp(io, head)
        end
      end
    rescue StandardError
      nil
    end

    def png(head)
      # IHDR is always the first chunk: width and height are big-endian at 16.
      head[16, 8].unpack("N2")
    end

    def gif(head)
      head[6, 4].unpack("v2")
    end

    def jpeg(io)
      io.seek(2)
      loop do
        byte = io.read(1)
        return nil if byte.nil?
        next unless byte == "\xFF".b

        marker = io.read(1)
        return nil if marker.nil?

        code = marker.ord
        next if code == 0xFF || code == 0x01 || (0xD0..0xD9).cover?(code)

        length = io.read(2)&.unpack1("n")
        return nil if length.nil? || length < 2

        # SOF0..SOF15 carry the frame size; DHT/JPG/DAC do not.
        if (0xC0..0xCF).cover?(code) && ![0xC4, 0xC8, 0xCC].include?(code)
          frame = io.read(5)
          return nil if frame.nil? || frame.bytesize < 5

          return [frame[3, 2].unpack1("n"), frame[1, 2].unpack1("n")]
        end

        io.seek(length - 2, IO::SEEK_CUR)
      end
    end

    def webp(io, head)
      case head[12, 4]
      when "VP8 ".b
        # Lossy: 14-bit dimensions after the 3-byte start code.
        body = read_at(io, 26, 4)
        body && [body[0, 2].unpack1("v") & 0x3FFF, body[2, 2].unpack1("v") & 0x3FFF]
      when "VP8L".b
        body = read_at(io, 21, 4)
        return nil if body.nil?

        bits = body.unpack1("V")
        [(bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1]
      when "VP8X".b
        body = read_at(io, 24, 6)
        return nil if body.nil?

        [le24(body[0, 3]) + 1, le24(body[3, 3]) + 1]
      end
    end

    def read_at(io, offset, length)
      io.seek(offset)
      data = io.read(length)
      data && data.bytesize == length ? data : nil
    end

    def le24(bytes)
      bytes.unpack("C3").each_with_index.sum { |byte, index| byte << (8 * index) }
    end
  end
end

# Runs after every document is rendered but before anything is written, which
# is the one point where static files can still be added to the site.
Jekyll::Hooks.register :site, :post_render do |site|
  Images.process(site)
end
