# The shell behind `nix develop`: everything `jekyll serve` needs, plus the
# formatters, so nothing here has to be installed on the host.
{pkgs}: {
  default = pkgs.mkShell {
    # The same fonts `nix build` renders diagrams and charts with, so that a
    # `jekyll serve` in this shell shows what the deploy will publish.
    FONTCONFIG_FILE = pkgs.blog-fonts.conf;
    PLOTNINE_FONT = pkgs.blog-fonts.file;

    # Same reason, for the same variable nix/site.nix sets: nixpkgs' glibc
    # ships no zoneinfo of its own, so the `timezone:` in _config.yml
    # resolves to UTC and an evening post previews a day later here than it
    # publishes. Set unconditionally rather than deferring to an ambient
    # TZDIR, because the host's zoneinfo is exactly what should not be
    # deciding permalinks.
    TZDIR = "${pkgs.tzdata}/share/zoneinfo";

    buildInputs =
      [
        # The gems the site builds against plus the development group -- rake,
        # webrick, ruby-lsp -- which nix/site.nix deliberately leaves out so
        # that a language server bump does not rebuild the site.
        pkgs.blog-ruby.env
        # Regenerates gemset.nix after a Gemfile change.
        pkgs.blog-bundix
        # `treefmt` runs every formatter at once, exactly as `nix fmt` and
        # `nix flake check` do. The two underneath it are named as well so
        # that a one-off `prettier --check` in the shell is the very same
        # binary, with the very same Liquid plugin, that the check runs.
        pkgs.blog-treefmt.config.build.wrapper
        pkgs.blog-prettier
        pkgs.alejandra
      ]
      # magick, dot and the plotnine interpreter, from the one list
      # nix/site.nix builds with.
      ++ pkgs.blog-render-tools;
  };
}
