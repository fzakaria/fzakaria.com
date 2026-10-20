# The package set everything in this flake is built out of: nixpkgs with
# overlay.nix applied, so `pkgs.blog-site` and friends exist alongside
# `pkgs.graphviz`.
{
  self,
  nixpkgs,
  system,
  gemlock,
  treefmt-nix,
}:
import nixpkgs {
  inherit system;
  overlays = [
    (import ./overlay.nix {inherit self gemlock treefmt-nix;})
  ];
}
