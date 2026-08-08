# The fonts `dot` measures text with, for the same reason nix/python.nix is
# pinned: a diagram drawn on a laptop and a diagram drawn in the sandbox
# have to be the same diagram. Graphviz sizes every box from the metrics
# of whatever fontconfig hands it, and the sandbox has no fonts at all --
# so a graph built here and a graph built by `nix build` disagreed about
# how wide a label is.
#
# It matters twice over for a ```graphviz fence, because the SVG carries
# the font *name* and the reader's browser picks the face. A diagram that
# asks for "JetBrains Mono" is measured here with the same file
# assets/fonts/JetBrainsMono-Regular.woff2 serves to the page, so the text
# lands inside the box it was drawn for instead of spilling past it.
# Liberation is here so that the generic families older diagrams ask for
# still resolve to something with real metrics.
{pkgs}:
pkgs.makeFontsConf {
  fontDirectories = [pkgs.jetbrains-mono pkgs.liberation_ttf];
}
