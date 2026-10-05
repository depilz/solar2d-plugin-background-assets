#!/bin/bash
# Demo packs: builds the demo's asset packs with xcrun ba-package, one per manifest in tools/demo/packs/.
# usage: tools/demo/packs.sh --out <dir> [--download-base-url <https URL>]
# <dir> (absent or empty) lies outside the repo, in an existing directory. Each tools/demo/packs/<id>.json is a
# ba-package manifest whose assetPackID is <id> and whose files are tools/demo/packs/<id>/*, so each pack holds its files
# under <id>/ in the packs' shared file namespace (Corona/main.lua's paths). Writes <dir>/<id>.aar, the archive to
# upload or to serve with ba-serve. With --download-base-url, also writes a self-hosting server root <dir>/www/: each
# pack under its id and download-manifest.json, whose download URLs are the base URL plus the id.
# Toolchain, overridable by env: DEVELOPER_DIR (Xcode 27.0).
# Exit 0 = every pack built, 1 = ba-package failed, 2 = usage or precondition error.
set -euo pipefail

usage() { sed -n '3s/^# //p' "$0"; }
die() { echo "packs.sh: $*" >&2; exit 2; }
fail() { echo "packs.sh: $*" >&2; exit 1; }
value() { [[ -n "${2:-}" && "$2" != --* ]] || die "$1 needs a value"; }
# physical path: path made absolute with symlinks resolved; when path is no directory, only its (existing) parent is
physical() {
  if [[ -d "$1" ]]; then (cd "$1" && pwd -P); else echo "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"; fi
}
# outside path: path (a directory, or absent with an existing parent) does not lie inside the repo
outside() { [[ "$(physical "$1")/" != "$REPO/"* ]]; }

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
OUT="" BASE_URL=""
while (( $# )); do
  case $1 in
    --out) value "$@"; OUT=$2; shift 2 ;;
    --download-base-url) value "$@"; BASE_URL=$2; shift 2 ;;
    *) die "unknown argument $1 (--help)" ;;
  esac
done
[[ -n "$OUT" ]] || die "--out is required"
[[ -z "$BASE_URL" || "$BASE_URL" =~ ^https://[^/:?#]+ ]] || die "--download-base-url $BASE_URL is not an https URL"
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
PACKS=$REPO/tools/demo/packs

[[ -d "$(dirname "$OUT")" ]] && outside "$(dirname "$OUT")" || die "--out $OUT must lie outside $REPO, in an existing directory"
[[ ! -e "$OUT" || ( -d "$OUT" && -z "$(ls -A "$OUT")" ) ]] || die "--out $OUT is not an empty directory"
outside "$OUT" || die "--out $OUT lies inside $REPO"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
[[ -d "$DEVELOPER_DIR" ]] || die "no Xcode at DEVELOPER_DIR $DEVELOPER_DIR"
mkdir -p "$OUT"
OUT=$(physical "$OUT")

AARS=()
for manifest in "$PACKS"/*.json; do
  id=$(basename "$manifest" .json)
  # ba-package resolves the manifest's file paths against the working directory
  (cd "$PACKS" && xcrun ba-package package "$manifest" --output-path "$OUT/$id.aar" --quiet) ||
    fail "ba-package failed for $manifest"
  AARS+=("$OUT/$id.aar")
  echo "packs.sh: built $OUT/$id.aar"
done

if [[ -n "$BASE_URL" ]]; then
  mkdir "$OUT/www"
  for aar in "${AARS[@]}"; do cp "$aar" "$OUT/www/$(basename "$aar" .aar)"; done
  xcrun ba-package download-manifest create "${AARS[@]}" --ios --download-base-url "$BASE_URL" \
    --output-path "$OUT/www/download-manifest.json" --quiet || fail "ba-package could not write the download manifest"
  echo "packs.sh: wrote the server root $OUT/www (download manifest for $BASE_URL)"
fi
