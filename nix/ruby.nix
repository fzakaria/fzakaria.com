# The Ruby that runs Jekyll, and the gems from Gemfile.lock.
#
# `env` carries the development group too -- rake, webrick, ruby-lsp -- and is
# what `nix develop` gets. `envMinimal` is the same gems without it, and is
# what nix/site.nix builds against, so a change to a language server does not
# rebuild the site.
{
  pkgs,
  ruby-nix,
}: let
  ruby = pkgs.ruby_3_4;
  rubyNix = ruby-nix.lib pkgs;
  gemset =
    if builtins.pathExists ../gemset.nix
    then import ../gemset.nix
    else {};
  # If you want to override gem build config, see
  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/ruby-modules/gem-config/default.nix
  gemConfig = {};
in
  rubyNix {
    name = "fzakaria.com-gemset";
    inherit gemset ruby;
    gemConfig = pkgs.defaultGemConfig // gemConfig;
  }
