let
 sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs { };
in
with pkgs;
with stdenv;
let
  jekyll_env = bundlerEnv {
    name = "fzakaria.com";
    inherit ruby;
    gemdir = ./.;
  };
in mkShell {
  name = "blog-shell";
  buildInputs = [jekyll_env bundix ruby niv];
  
  # https://github.com/nix-community/bundix/issues/88
  BUNDLE_FORCE_RUBY_PLATFORM = "true";
}