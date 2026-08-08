# `nix run` -- the built site, served locally.
{pkgs}: {
  default = {
    type = "app";
    program = "${pkgs.blog-serve}/bin/server";
    meta = {
      description = "Personal website of Farid Zakaria";
    };
  };
}
