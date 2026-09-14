#!/usr/bin/env bash
# Cuts a dated readership data release: uploads every Parquet file whose bytes
# differ from what data-pins.json pins, with notes comparing against the
# previous release, then repoints the pins.
#
# The same shape as nixpkgs-multiverse's tools/cut-data-release.sh. Assets on a
# dated tag are never replaced: a second cut on the same day gets its own tag
# with a numeric suffix, so a pin written yesterday can never name bytes that
# changed underneath it. The narHash pins fail closed if that is ever violated.
# Uploading comes before the pins change, so a pin never names bytes that were
# not uploaded.
#
# Needs `gh` authenticated with repo scope, the host's `nix` for `nix hash
# path`, and the fetchers' output in data/readership.
#
# Usage:
#   nix run .#cut-readership-release               # tag readership-<today, UTC>
#   nix run .#cut-readership-release -- --dry-run  # write the notes, publish nothing
set -euo pipefail

ROOT="$PWD"
DATA="$ROOT/data/readership"
PINS="$ROOT/data-pins.json"
REPO="fzakaria/fzakaria.com"
BASE_URL="https://github.com/$REPO/releases/download"
SUMMARY_NAME="summary.json"
DAY="$(date -u +%Y%m%d)"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# nullglob rather than compgen: nixpkgs' non-interactive bash has no compgen.
shopt -s nullglob
PARQUET=("$DATA"/*.parquet)
shopt -u nullglob
if [ ${#PARQUET[@]} -eq 0 ]; then
  echo "cut-readership-release: no Parquet files in $DATA; run the fetchers first" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A field of data-pins.json, or empty when the file or the field is missing.
pin_field() {
  python3 - "$PINS" "$1" "$2" <<'PY'
import json, os, sys
pins_file, name, field = sys.argv[1:4]
if os.path.exists(pins_file):
    print(json.load(open(pins_file))["files"].get(name, {}).get(field, ""))
PY
}

# Only bytes that moved get uploaded: compare each file's narHash to its pin.
CHANGED=()
for f in "$DATA"/*.parquet; do
  current="$(nix hash path --sri --type sha256 "$f")"
  if [ "$current" != "$(pin_field "$(basename "$f")" narHash)" ]; then
    CHANGED+=("$f")
  fi
done

if [ ${#CHANGED[@]} -eq 0 ]; then
  echo "cut-readership-release: every file matches its pin; nothing to cut"
  exit 0
fi

# Today's tag, suffixed when an earlier cut already took it.
TAG="readership-$DAY"
suffix=1
while gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1; do
  suffix=$((suffix + 1))
  TAG="readership-$DAY.$suffix"
done
echo "cutting $TAG with ${#CHANGED[@]} changed file(s)"

# The previous release's summary, for the notes to compare against. A first
# release, or a summary that will not download, gets notes without changes.
PREVIOUS=()
previous_tag="$(pin_field "$SUMMARY_NAME" tag)"
if [ -n "$previous_tag" ] && curl -fsSL -o "$WORK/previous.json" "$BASE_URL/$previous_tag/$SUMMARY_NAME"; then
  PREVIOUS=(--previous-summary "$WORK/previous.json")
fi

NAMES=()
for f in "${CHANGED[@]}"; do
  NAMES+=("$(basename "$f")")
done
python3 -m readership release-notes \
  --data "$DATA" \
  --tag "$TAG" \
  "${PREVIOUS[@]}" \
  --notes-out "$WORK/notes.md" \
  --summary-out "$WORK/$SUMMARY_NAME" \
  --files "${NAMES[@]}"

if [ "$DRY_RUN" = true ]; then
  cat "$WORK/notes.md"
  exit 0
fi

gh release create "$TAG" \
  --repo "$REPO" \
  --title "Readership data, $(date -u +%Y-%m-%d)" \
  --notes-file "$WORK/notes.md" \
  "${CHANGED[@]}" "$WORK/$SUMMARY_NAME"

# Repoint the pins at the files just uploaded; files that did not change keep
# pointing at the release that first carried them.
HASHES="$WORK/hashes.tsv"
for f in "${CHANGED[@]}" "$WORK/$SUMMARY_NAME"; do
  printf '%s\t%s\n' "$(basename "$f")" "$(nix hash path --sri --type sha256 "$f")"
done > "$HASHES"
GENERATED_AT="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["generated_at"])' "$WORK/$SUMMARY_NAME")"

python3 - "$PINS" "$TAG" "$HASHES" "$BASE_URL" "$GENERATED_AT" <<'PY'
import json, os, sys

pins_file, tag, hashes, base_url, generated_at = sys.argv[1:6]
pins = {"version": 1, "baseUrl": base_url, "files": {}}
if os.path.exists(pins_file):
    pins = json.load(open(pins_file))

for line in open(hashes):
    name, nar_hash = line.rstrip("\n").split("\t")
    pins["files"][name] = {"tag": tag, "narHash": nar_hash}
pins["generatedAt"] = generated_at

with open(pins_file, "w") as out:
    json.dump(pins, out, indent=1, sort_keys=True)
    out.write("\n")
print(f"{pins_file}: {len(pins['files'])} pins, now at {tag}")
PY
