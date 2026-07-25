# frozen_string_literal: true

require "digest"

# Publishes a short content hash of the stylesheet sources as `site.css_version`.
#
# base.css keeps a stable filename, so after a redesign a browser will happily
# keep serving the copy it cached — which is exactly what happened on the first
# deploy of this design. Appending ?v=<hash> to the link makes the URL change
# whenever the CSS does, and only when it does: a hash of the sources rather
# than the commit means an ordinary new post does not force every reader to
# re-download the stylesheet.
module Jekyll
  class AssetVersionGenerator < Generator
    priority :highest

    SOURCES = ["_sass", "assets/css"].freeze

    def generate(site)
      digest = Digest::SHA256.new

      files(site).each do |path|
        digest.update(File.basename(path))
        digest.update(File.read(path))
      end

      site.config["css_version"] = digest.hexdigest[0, 12]
    end

    private

    def files(site)
      SOURCES.flat_map { |dir| Dir.glob(File.join(site.source, dir, "**", "*.{scss,sass,css}")) }.sort
    end
  end
end
