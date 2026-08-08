# Prettier, taught to read Liquid.
#
# Its own package rather than something private to nix/formatter.nix, because
# `nix develop` needs the identical binary: a prettier from the shell that did
# not load the plugin would disagree with `nix fmt` on every template.
{pkgs}: let
  # Prettier cannot parse `_layouts/` and `_includes/`: they are HTML with
  # `{% %}` tags in them, which the stock HTML parser reads as text and
  # reflows into nonsense. This plugin adds the `liquid-html` parser that
  # understands them.
  #
  # Taken as the published npm tarball rather than built from a lockfile.
  # `standalone.js` is the plugin's prebuilt bundle with every dependency but
  # prettier itself already webpacked in, so this one fetch replaces the whole
  # node_modules tree -- and the npm toolchain that populated it -- that the
  # repo used to carry just to format its templates.
  version = "1.8.3";
  plugin =
    pkgs.runCommand "prettier-plugin-liquid-${version}" {
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@shopify/prettier-plugin-liquid/-/prettier-plugin-liquid-${version}.tgz";
        hash = "sha256-t9lc6GxlDrF897Imu4fpaS39/FOf5xQs2Dy5S0pIcFs=";
      };
    } ''
      mkdir -p $out/node_modules
      tar -xzf $src -C $out --strip-components=1 package/standalone.js
      # The bundle leaves `require("prettier")` external, and Node resolves it
      # by walking up from the file that asks -- which here is a store path
      # with nothing above it. Give the plugin the one dependency it kept.
      ln -s ${pkgs.prettier}/lib/node_modules/prettier $out/node_modules/prettier
    '';
in
  # Prettier resolves a plugin named on the command line the same way Node
  # resolves an import: by walking up from the working directory looking for a
  # node_modules. There is none, and treefmt runs formatters from the root of
  # the tree, so the plugin has to be named by absolute store path. Baking it
  # into a wrapper means no caller has to know that.
  pkgs.writeShellApplication {
    name = "prettier";
    text = ''
      exec ${pkgs.lib.getExe pkgs.prettier} --plugin ${plugin}/standalone.js "$@"
    '';
  }
