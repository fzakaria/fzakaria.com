# frozen_string_literal: true

require "digest"

# Publishes the line under the masthead: an oscilloscope trace of the page's
# own address.
#
# The curve is a plot of SHA-256 over the page's URL. A SHA-256 digest is 32
# bytes, so there is one sample per byte and each sample's height is that
# byte's value -- which is where the 32 points come from, and why nothing about
# the digest is thrown away. `page.signal_hash` is the same digest in hex, so
# the tooltip shows a string a reader can check for themselves:
#
#   printf '/2025/03/28/what-s-in-a-nix-store-path' | sha256sum
#
# The hash is taken over the URL rather than the body, so a page's line is its
# identity and does not shift every time a typo is fixed.
module Jekyll
  class SignalGenerator < Generator
    priority :low

    # A tall, wide viewBox keeps the arithmetic in round numbers; the SVG is
    # stretched to whatever the masthead is with preserveAspectRatio="none".
    WIDTH = 1000.0
    HEIGHT = 100.0
    # Room for the curve to overshoot a peak without being clipped.
    PAD = 18.0
    # Catmull-Rom at full strength overshoots hard when neighbouring bytes are
    # far apart, which is most of the time on hash data. Slackening it keeps
    # the trace a wave rather than a whip.
    TENSION = 0.72

    def generate(site)
      (site.pages + site.documents).each do |doc|
        doc.data["signal_hash"] = Digest::SHA256.hexdigest(doc.url)
        doc.data["signal_path"] = path_for(Digest::SHA256.digest(doc.url).bytes)
      end
    end

    private

    def points_for(bytes)
      span = HEIGHT - (2 * PAD)
      bytes.each_with_index.map do |b, i|
        [i * (WIDTH / (bytes.length - 1)), PAD + (1.0 - (b / 255.0)) * span]
      end
    end

    # Catmull-Rom through every point, emitted as cubic Beziers: the curve
    # passes through each sample exactly, so nothing is lost to the smoothing.
    def path_for(bytes)
      pts = points_for(bytes)
      last = pts.length - 1
      d = +"M#{num(pts[0][0])},#{num(pts[0][1])}"
      (0...last).each do |i|
        p0 = pts[[i - 1, 0].max]
        p1 = pts[i]
        p2 = pts[i + 1]
        p3 = pts[[i + 2, last].min]
        # c1 = p1 + (p2 - p0)/6, c2 = p2 - (p3 - p1)/6, slackened by TENSION.
        c1 = [0, 1].map { |a| p1[a] + ((p2[a] - p0[a]) / 6.0 * TENSION) }
        c2 = [0, 1].map { |a| p2[a] - ((p3[a] - p1[a]) / 6.0 * TENSION) }
        d << " C#{num(c1[0])},#{num(c1[1])} #{num(c2[0])},#{num(c2[1])}" \
             " #{num(p2[0])},#{num(p2[1])}"
      end
      d
    end

    def num(f)
      format("%.2f", f).sub(/\.?0+$/, "")
    end
  end
end
