# The /readership page's JSON, built from the Parquet files data-pins.json pins.
#
# The data is not in the repository. tools/cut-readership-release.sh uploads it
# to dated GitHub releases and records {tag, narHash} per file in
# data-pins.json; each file is fetched here as a fixed-output derivation, so a
# release asset that was replaced fails the hash and the build stops.
#
# fetchurl rather than fetchTree keeps evaluation offline: nothing downloads
# until something builds the site. recursiveHash because the pins record what
# `nix hash path` prints, the NAR hash of the file.
#
# Null when there are no pins yet, so the site still builds and the page shows
# its empty states.
{pkgs}: let
  pinsFile = ../data-pins.json;
in
  if !builtins.pathExists pinsFile
  then null
  else let
    pins = builtins.fromJSON (builtins.readFile pinsFile);

    # summary.json is pinned for the next release's notes; the page needs only
    # the Parquet files.
    parquet = pkgs.lib.filterAttrs (name: _pin: pkgs.lib.hasSuffix ".parquet" name) pins.files;

    fetched = builtins.mapAttrs (name: pin:
      pkgs.fetchurl {
        url = "${pins.baseUrl}/${pin.tag}/${name}";
        hash = pin.narHash;
        recursiveHash = true;
      })
    parquet;

    data = pkgs.linkFarm "readership-data" fetched;
  in
    # The generation time comes from the pins, not the clock, so the same pins
    # always build the same JSON.
    pkgs.runCommand "readership.json" {nativeBuildInputs = [pkgs.blog-tools.python];} ''
      PYTHONPATH=${../tools} python3 -m readership page-data \
        --data ${data} \
        --out $out \
        --generated-at ${pins.generatedAt}
    ''
