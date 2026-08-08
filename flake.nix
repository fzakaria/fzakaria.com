{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    ruby-nix.url = "github:inscapist/ruby-nix";
    # a fork that supports platform dependant gem
    bundix = {
      url = "github:inscapist/bundix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    systems,
    nixpkgs,
    ruby-nix,
    bundix,
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

    # _plugins/plotnine.rb renders ```plotnine fences by shelling out to this
    # interpreter. Pinned here rather than left to the ambient python3 so that
    # a chart drawn on a laptop and a chart drawn in CI are the same chart.
    pythonEnv = eachSystem (
      {pkgs, ...}:
        pkgs.python3.withPackages (ps: [ps.plotnine])
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
            ./styleguide.md
            ./talks.md
            ./_config.yml
            ./_data
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
          # The sandbox has no /etc/zoneinfo, so the `timezone:` in _config.yml
          # (which just sets TZ) silently resolves to UTC and every post whose
          # local time is late enough gets its permalink bumped a day forward.
          TZDIR = "${pkgs.tzdata}/share/zoneinfo";
          # Same shape of problem as TZDIR: the sandbox has no locale, so Ruby
          # falls back to US-ASCII and tags anything it reads from a
          # subprocess with it -- correct UTF-8 bytes under a wrong label, and
          # the first regex to meet a `→` raises. The plugins name their own
          # encodings and do not depend on this; it is here so that the next
          # thing to shell out does not have to learn the lesson again.
          # C.UTF-8 is built into glibc, so this costs no locale archive.
          LANG = "C.UTF-8";
          JEKYLL_ENV = "production";
          PAGES_ENV = "production";
          PAGES_REPO_NWO = "fzakaria/fzakaria.com";
          JEKYLL_BUILD_REVISION = self.rev or self.dirtyRev or "dirty";
          JEKYLL_STORE_PATH = placeholder "out";
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
          pkgs.importNpmLock.hooks.linkNodeModulesHook
          pkgs.nodejs_22
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
          pythonEnv.${system}
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
          # Without this nginx labels everything text/plain, and browsers
          # refuse to apply a stylesheet served under the wrong type.
          include ${pkgs.nginx}/conf/mime.types;
          default_type application/octet-stream;
          access_log /dev/stdout;
          server {
            listen 8080;
            server_name localhost;
            root ${packages.${system}.default};

            location / {
              try_files $uri $uri.html $uri/index.html =404;
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
            imagemagick
            graphviz
            pythonEnv.${system}
          ];
          inputsFrom = [
          ];
        };
    });
  };
}
