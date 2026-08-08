# frozen_string_literal: true

# Renders a string as Liquid before it is used.
#
# Jekyll runs Liquid over pages and posts, but never over the strings it loads
# out of `_data`. That means a note in `_data/talks.yml` cannot say
# `{% post_url 2026-06-25-guixpkgs-every-guix-package-as-a-nix-flake %}` and has
# to hardcode `/2026/06/25/...` instead — a link that silently rots the moment a
# post is renamed. Piping the note through this filter first restores the tag:
#
#     {{ item.note | liquify | markdownify }}
#
# Rendering with `render!` rather than `render` is deliberate: a `post_url`
# pointing at a post that no longer exists should fail the build, not quietly
# emit an empty link.
module Jekyll
  module LiquifyFilter
    def liquify(input)
      return input if input.nil?

      Liquid::Template.parse(input.to_s).render!(@context)
    end
  end
end

Liquid::Template.register_filter(Jekyll::LiquifyFilter)
