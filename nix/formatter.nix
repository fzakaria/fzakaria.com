# `nix fmt`, as a treefmt module. Every language in the tree gets a formatter
# here rather than only the Nix code: alejandra for the flake, prettier for the
# stylesheets, the YAML, and the Liquid templates.
#
# This is also the only place prettier is configured. There is no .prettierrc,
# no .prettierignore and no package.json -- the includes and options below are
# the whole story, and nix/dev-shells.nix hands the shell the same
# `pkgs.blog-prettier` named here.
{pkgs, ...}: {
  projectRootFile = "flake.nix";

  # _old_blog/ is 116 pages imported verbatim from a previous site. They are
  # kept as they were published, so nothing here rewrites them.
  settings.excludes = ["_old_blog/**"];

  settings.formatter.alejandra = {
    command = pkgs.alejandra;
    options = ["--quiet"];
    includes = ["*.nix"];
  };

  # Stylesheets and configuration. Markdown is deliberately absent: the posts
  # are hand-wrapped prose, and reflowing them would rewrite every paragraph
  # and make every future diff a whole-file diff.
  settings.formatter.prettier = {
    command = pkgs.blog-prettier;
    options = ["--write"];
    includes = [
      "*.scss"
      "*.css"
      "*.yml"
      "*.yaml"
    ];
  };

  # The templates, with the parser forced. Prettier picks its parser from the
  # file extension, and for `.html` that is the built-in HTML parser even when
  # the Liquid plugin is loaded, so asking for it by name is the only way to
  # actually get it.
  settings.formatter.prettier-liquid = {
    command = pkgs.blog-prettier;
    options = [
      "--write"
      "--parser"
      "liquid-html"
    ];
    includes = ["*.html"];
  };
}
