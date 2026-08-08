{
  description = "Personal website of Farid Zakaria";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    ruby-nix.url = "github:inscapist/ruby-nix";
    # a fork that supports platform dependant gem
    bundix = {
      url = "github:inscapist/bundix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Wiring only. Everything this repository builds lives under nix/, reached
  # through the overlay nix/pkgs.nix applies -- so a derivation is
  # `pkgs.blog-site` or `pkgs.blog-treefmt` here, and its definition is one
  # file over there.
  outputs = {
    self,
    systems,
    nixpkgs,
    ruby-nix,
    bundix,
    treefmt-nix,
    ...
  }: let
    eachSystem = f:
      nixpkgs.lib.genAttrs (import systems) (
        system:
          f (import ./nix/pkgs.nix {
            inherit self nixpkgs system ruby-nix bundix treefmt-nix;
          })
      );
  in {
    formatter = eachSystem (pkgs: pkgs.blog-treefmt.config.build.wrapper);

    packages = eachSystem (pkgs: {default = pkgs.blog-site;});

    # `nix flake check` builds this but only evaluates `packages`, so CI runs
    # `nix build` as a separate step.
    checks = eachSystem (pkgs: {
      formatting = pkgs.blog-treefmt.config.build.check self;
    });

    apps = eachSystem (pkgs: import ./nix/apps.nix {inherit pkgs;});

    devShells = eachSystem (pkgs: import ./nix/dev-shells.nix {inherit pkgs;});
  };
}
