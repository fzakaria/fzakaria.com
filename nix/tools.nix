# The programs in tools/, as things a caller can run.
#
# Three pieces come out of here: the description each tool's app surfaces
# through `nix flake show`, the wrapper that makes `nix run .#<tool>` run it,
# and the test run `nix flake check` gates on.
#
# The readership fetchers are one Python package, tools/readership, with a
# subcommand per data source. Each app is a wrapper naming its subcommand, so
# the scheduled workflow reads as one step per source and a single source can
# be re-run by hand without the others.
{pkgs}: let
  # What tools/readership imports. Everything else it needs is the standard
  # library.
  libs = ps: [
    # Writes the Parquet files, and runs the queries the page build
    # aggregates them with.
    ps.duckdb
    # Application default credentials for Search Console and GA4: a user
    # login on a laptop, workload identity in the workflow.
    ps.google-auth
    # ISO 3166 country codes: GA4 reports two-letter codes, and the world map
    # on the page is keyed by numeric ones.
    ps.pycountry
    ps.requests
  ];

  python = pkgs.python3.withPackages libs;

  # The same interpreter with the test runner added, so the tests import
  # exactly the library versions the tools run with.
  testPython = pkgs.python3.withPackages (ps: libs ps ++ [ps.pytest]);

  # The wrapper interpolates ../tools, so `nix run` executes a store snapshot
  # of the package taken when the flake was evaluated. The fetchers write only
  # to the directory named by --out, so they do not need to run from a
  # checkout.
  wrapSubcommand = name: tool:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [python];
      text = ''
        export PYTHONPATH="${../tools}''${PYTHONPATH:+:$PYTHONPATH}"
        exec python3 -m readership ${tool.subcommand} "$@"
      '';
    };

  # Scripts rewrite files in the checkout (data-pins.json), so the wrapper
  # refuses to run anywhere else. `nix` is deliberately not a runtime input:
  # `nix hash path` should be the caller's own nix, as in nixpkgs-multiverse.
  wrapScript = name: tool:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [python pkgs.gh pkgs.curl pkgs.coreutils];
      text = ''
        if [ ! -f "$PWD/_config.yml" ]; then
          echo "${name}: run this from a fzakaria.com checkout (no _config.yml in $PWD)" >&2
          exit 1
        fi
        export PYTHONPATH="${../tools}''${PYTHONPATH:+:$PYTHONPATH}"
        exec bash ${../tools}/${tool.script} "$@"
      '';
    };

  wrap = name: tool:
    if tool ? script
    then wrapScript name tool
    else wrapSubcommand name tool;

  tools = {
    fetch-gsc = {
      subcommand = "gsc";
      description = "Fetch Search Console performance data into Parquet";
    };
    fetch-ga4 = {
      subcommand = "ga4";
      description = "Fetch Google Analytics 4 reports into Parquet";
    };
    fetch-hn = {
      subcommand = "hn";
      description = "Fetch Hacker News submissions and front-page rank history into Parquet";
    };
    fetch-lobsters = {
      subcommand = "lobsters";
      description = "Fetch Lobsters submissions into Parquet";
    };
    fetch-reddit = {
      subcommand = "reddit";
      description = "Fetch Reddit posts linking the site, via the Arctic Shift archive, into Parquet";
    };
    build-readership-data = {
      subcommand = "page-data";
      description = "Aggregate the fetched Parquet into _data/readership.json for the page";
    };
    cut-readership-release = {
      script = "cut-readership-release.sh";
      description = "Publish changed readership data as a dated GitHub release and repoint data-pins.json";
    };
  };
in {
  inherit python;

  descriptions = builtins.mapAttrs (_name: tool: tool.description) tools;

  # { <tool> = <wrapped executable>; } for every tool above.
  wrappers = builtins.mapAttrs wrap tools;

  # tests/readership against tools/readership. The tests work on plain data
  # and stubbed transports, so they run inside the sandbox with no network.
  tests =
    pkgs.runCommand "test-tools" {
      nativeBuildInputs = [testPython];
      # The copied sources are read-only store files.
      PYTHONDONTWRITEBYTECODE = "1";
    } ''
      cp -r ${../tools} tools
      cp -r ${../tests} tests
      PYTHONPATH=tools python3 -m pytest -p no:cacheprovider -q tests/readership
      touch $out
    '';
}
