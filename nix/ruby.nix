# The Ruby that runs Jekyll, and the gems from Gemfile.lock, read by
# gemlock.nix: the lock's CHECKSUMS section is the only hash source, so there
# is no gemset.nix to regenerate.
#
# `env` carries the development group too -- ruby-lsp and what it pulls in --
# and is what `nix develop` gets. `envMinimal` leaves it out and is what
# nix/site.nix builds against: the site does not depend on a language server,
# so its build closure should not either. The env exports BUNDLE_WITHOUT for
# the missing group itself, which Jekyll's own `Bundler.setup` needs.
# `shell` is gemlock's dev shell: the wrapped Ruby, the gems and a `bundle`
# whose install, add, remove and update only touch the lock. `lock` is
# `nix run .#lock`.
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
