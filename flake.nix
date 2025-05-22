{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    systems.url = "github:nix-systems/default";
    ruby-nix.url = "github:inscapist/ruby-nix";
    # a fork that supports platform dependant gem
    bundix = {
      url = "github:inscapist/bundix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wordword = {
      url = "git+https://codeberg.org/mtlynch/wordword";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    systems,
    nixpkgs,
    ruby-nix,
    bundix,
    wordword,
    ...
  }: let
    eachSystem = f:
      nixpkgs.lib.genAttrs (import systems) (system:
        f {
          pkgs = nixpkgs.legacyPackages.${system};
          inherit system;
        });
  in rec {
    formatter = eachSystem ({pkgs, ...}: pkgs.alejandra);

    gemsets = eachSystem (
      {pkgs, ...}: let
        ruby = pkgs.ruby_3_4;
        rubyNix = ruby-nix.lib pkgs;
        gemset =
          if builtins.pathExists ./gemset.nix
          then import ./gemset.nix
          else {};
        # If you want to override gem build config, see
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/ruby-modules/gem-config/default.nix
        gemConfig = {};
      in (rubyNix
        {
          name = "fzakaria.com-gemset";
          inherit gemset ruby;
          gemConfig = pkgs.defaultGemConfig // gemConfig;
        })
    );

    packages = eachSystem ({
      pkgs,
      system,
    }: let
      fs = pkgs.lib.fileset;
    in {
      default = pkgs.stdenv.mkDerivation {
        name = "fzakaria.com";
        version = "0.1.0";
        src = fs.toSource {
          root = ./.;
          fileset = fs.unions [
            ./.prettierignore
            ./.prettierrc
            ./Gemfile
            ./Gemfile.lock
            ./index.md
            ./keybase.txt
            ./old_blog.md
            ./publickey.txt
            ./_config.yml
            ./_sass
            ./assets
            ./_posts
            ./_old_blog
            ./_layouts
            ./_includes
            ./_plugins
            ./package.json
            ./package-lock.json
          ];
        };
        env = {
          JEKYLL_ENV = "production";
          PAGES_ENV = "production";
          PAGES_REPO_NWO = "fzakaria/fzakaria.com";
          JEKYLL_BUILD_REVISION = self.rev or self.dirtyRev or "dirty";
        };

        npmDeps = pkgs.importNpmLock.buildNodeModules {
          npmRoot = ./.;
          nodejs = pkgs.nodejs_22;
        };

        buildInputs = [
          gemsets.${system}.envMinimal
          gemsets.${system}.ruby
        ];

        nativeBuildInputs = [
          wordword.packages.${system}.default
          pkgs.importNpmLock.hooks.linkNodeModulesHook
          pkgs.nodejs_22
        ];

        buildPhase = ''
          jekyll build
        '';
        installPhase = ''
          mkdir -p $out
          cp -r _site/* $out
        '';

        doCheck = true;
        checkPhase = ''
          npm run prettier-check
          # TODO: maybe move these to individual flake checks instead
          # check for duplicate words
          wordword _posts/
        '';
      };
    });

    apps = eachSystem ({
      system,
      pkgs,
    }: let
      config = pkgs.writeText "nginx.conf" ''
        daemon off;
        error_log stderr info;
        pid /tmp/nginx.pid;
        events {}
        http {
          access_log /dev/stdout;
          server {
            listen 8080;
            server_name localhost;
            root ${packages.${system}.default};
            location / {
              try_files $uri $uri.html =404;
            }
          }
        }
      '';
      server = pkgs.writeShellScriptBin "server" ''
        echo "🌍 Nginx serving at http://127.0.0.1:8080";
        ${pkgs.nginx}/bin/nginx -c ${config} -e /tmp/nginx_error.log
      '';
    in {
      default = {
        type = "app";
        program = "${server}/bin/server";
        meta = {
          description = "Personal website of Farid Zakaria";
        };
      };
    });

    devShells = eachSystem ({
      pkgs,
      system,
    }: {
      default = with pkgs;
        mkShell {
          buildInputs = [
            bundix.packages.${system}.default
            gemsets.${system}.env
            nodejs_22
            wordword.packages.${system}.default
          ];
          inputsFrom = [
          ];
        };
    });
  };
}
