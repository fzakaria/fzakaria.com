{ pkgs ? import <nixpkgs> { } }:
with pkgs;
with stdenv;
let
  gems = bundlerEnv {
    name = "fzakaria.com";
    inherit ruby;
    gemdir = ./.;
  };
in mkShell {
  name = "blog-shell";
  buildInputs = [gems ruby bundix];
}