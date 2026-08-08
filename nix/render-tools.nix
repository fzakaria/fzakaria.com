# The programs the Jekyll plugins shell out to while rendering a post.
#
# Shared by nix/site.nix and nix/dev-shells.nix so that `jekyll serve` in the
# shell draws a diagram with the same `dot` the deploy does. Named as a list
# here rather than reached through the shell's `inputsFrom`, because the site
# derivation also carries a Ruby -- envMinimal, without the development group
# -- and a shell inheriting that would end up with two gem environments on
# PATH, correct only as long as they happen to be ordered the right way.
{pkgs}: [
  # _plugins/images.rb shells out to `magick` to build the srcset
  # derivatives. Without it the build still succeeds, but ships the
  # full-size originals.
  pkgs.imagemagick
  # _plugins/graphviz.rb shells out to `dot` and friends to render
  # ```graphviz fences. Unlike imagemagick above this is required: a
  # missing engine fails the build rather than shipping a post whose
  # diagram is a wall of DOT.
  pkgs.graphviz
  # _plugins/plotnine.rb runs `python3` to render ```plotnine fences.
  # Required for the same reason graphviz is: a missing interpreter
  # would ship a post whose chart is a wall of Python.
  pkgs.blog-python
]
