# Everything this repository builds, as attributes on a package set.
#
# Applied by nix/pkgs.nix, so each file below takes one `pkgs` and finds its
# dependencies on it -- site.nix asks for `pkgs.blog-ruby`, serve.nix for
# `pkgs.blog-site` -- instead of every derivation being threaded a
# `<thing>For system` function by hand from flake.nix.
#
# Plain `import` rather than `callPackage`: blog-ruby is an attrset of gem
# environments rather than a derivation, and makeOverridable would graft an
# `override` attribute onto it.
{
  self,
  ruby-nix,
  bundix,
  treefmt-nix,
}: final: _prev: {
  blog-ruby = import ./ruby.nix {
    pkgs = final;
    inherit ruby-nix;
  };
  blog-python = import ./python.nix {pkgs = final;};
  blog-render-tools = import ./render-tools.nix {pkgs = final;};
  blog-fonts = import ./fonts.nix {pkgs = final;};
  blog-prettier = import ./prettier.nix {pkgs = final;};
  # The evaluated treefmt module rather than a plain derivation: the same
  # evaluation supplies `nix fmt` (build.wrapper), the `nix flake check`
  # gate (build.check) and the dev shell (build.devShell), so all three are
  # guaranteed to run the same formatters with the same options.
  blog-treefmt = treefmt-nix.lib.evalModule final ./formatter.nix;
  blog-site = import ./site.nix {
    pkgs = final;
    inherit self;
  };
  blog-serve = import ./serve.nix {pkgs = final;};

  # Regenerates gemset.nix from Gemfile.lock. A flake package rather than a
  # nixpkgs one because it is the fork that handles platform-dependent gems;
  # see the flake input.
  blog-bundix = bundix.packages.${final.stdenv.hostPlatform.system}.default;
}
