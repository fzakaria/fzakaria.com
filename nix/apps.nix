# `nix run` -- the built site, served locally -- and `nix run .#<tool>` for
# every program in tools/:
#   nix run .#fetch-hn -- --out data/readership
{pkgs}:
builtins.mapAttrs (name: description: {
  type = "app";
  program = "${pkgs.blog-tools.wrappers.${name}}/bin/${name}";
  meta = {inherit description;};
})
pkgs.blog-tools.descriptions
// {
  default = {
    type = "app";
    program = "${pkgs.blog-serve}/bin/server";
    meta = {
      description = "Personal website of Farid Zakaria";
    };
  };
}
