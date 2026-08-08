# The Ruby that runs Jekyll, and the gems from Gemfile.lock, read by
# gemlock.nix: the lock's CHECKSUMS section is the only hash source, so there
# is no gemset.nix to regenerate.
#
# `env` carries the development group too -- ruby-lsp and what it pulls in --
# and is what `nix develop` gets. `envMinimal` leaves it out and is what
# nix/site.nix builds against: the site does not depend on a language server,
# so its build closure should not either.
{
  pkgs,
  gemlock,
}: let
  ruby = pkgs.ruby_3_4;
  load = groups:
    gemlock.lib.loadBundle {
      inherit pkgs ruby groups;
      src = ../.;
      name = "fzakaria.com";
    };
  full = load null;
  minimal = load ["default" "jekyll_plugins"];
in {
  inherit ruby;
  inherit (full) env lock;
  shell = full.shell {};
  envMinimal = minimal.env;
}
