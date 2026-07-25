module Jekyll
  class NixStoreGenerator < Generator
    priority :highest

    # The nix build exports $out before invoking jekyll, so the site can name
    # the store path it lives in. Absent for a plain `jekyll build`.
    def generate(site)
      site.config['nix_store_path'] = ENV['JEKYLL_STORE_PATH']
    end
  end
end
