# `nix build` -- the Jekyll build, and the tree the pages workflow deploys.
{
  pkgs,
  self,
}: let
  fs = pkgs.lib.fileset;
in
  pkgs.stdenv.mkDerivation {
    name = "fzakaria.com";
    version = "0.1.0";
    src = fs.toSource {
      root = ../.;
      fileset = fs.unions [
        ../Gemfile
        ../Gemfile.lock
        ../index.md
        ../keybase.txt
        ../old_blog.md
        ../publickey.txt
        ../styleguide.md
        ../talks.md
        ../_config.yml
        ../_data
        ../_sass
        ../assets
        ../_posts
        ../_old_blog
        ../_layouts
        ../_includes
        ../_plugins
      ];
    };
    env = {
      # The sandbox has no /etc/zoneinfo, so the `timezone:` in _config.yml
      # (which just sets TZ) silently resolves to UTC and every post whose
      # local time is late enough gets its permalink bumped a day forward.
      TZDIR = "${pkgs.tzdata}/share/zoneinfo";
      # Same shape of problem as TZDIR: the sandbox has no locale, so Ruby
      # falls back to US-ASCII and tags anything it reads from a
      # subprocess with it -- correct UTF-8 bytes under a wrong label, and
      # the first regex to meet a `→` raises. The plugins name their own
      # encodings and do not depend on this; it is here so that the next
      # thing to shell out does not have to learn the lesson again.
      # C.UTF-8 is built into glibc, so this costs no locale archive.
      LANG = "C.UTF-8";
      # Where `dot` finds the fonts it measures labels with; see nix/fonts.nix.
      FONTCONFIG_FILE = pkgs.blog-fonts;
      JEKYLL_ENV = "production";
      PAGES_ENV = "production";
      PAGES_REPO_NWO = "fzakaria/fzakaria.com";
      JEKYLL_BUILD_REVISION = self.rev or self.dirtyRev or "dirty";
      JEKYLL_STORE_PATH = placeholder "out";
    };

    buildInputs = [
      pkgs.blog-ruby.envMinimal
      pkgs.blog-ruby.ruby
    ];

    nativeBuildInputs = pkgs.blog-render-tools;

    # Every file in the store carries mtime=1, and jekyll-sitemap stamps
    # a static file's <lastmod> from its mtime (posts and pages get theirs
    # from front matter instead). Under the `timezone:` set above that
    # prints as 1969-12-31T16:00:01-08:00, a pre-1970 date that Google
    # Search Console rejects with "An invalid date was found", taking the
    # whole sitemap with it. Restamp the tree with the flake's own
    # last-modified time: one date per revision, so the build stays
    # reproducible, and one the sitemap schema accepts. This hangs off
    # patchPhase rather than preBuild because buildPhase below is a
    # literal string, which replaces the phase's runHook calls with it.
    postPatch = ''
      find . -type f -exec touch -d @${toString self.lastModified} {} +
    '';

    buildPhase = ''
      jekyll build
    '';
    installPhase = ''
      mkdir -p $out
      cp -r _site/* $out
    '';
  }
