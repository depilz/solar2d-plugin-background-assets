#!/bin/bash
# Release builder: builds the plugin.backgroundAssets data.tgz archives from a clean checkout of the released commit.
# usage: <checkout>/tools/release/build.sh --out DIR [--commit REV] [platform...]
# Platforms: iphone mac-sim win32-sim (the default set).
# The checkout holding this script (a plain clone or a worktree) must have no modified, untracked or ignored file, and
# its HEAD^{tree} must equal REV^{tree} (REV defaults to HEAD). DIR (absent or empty) lies outside the checkout.
# Writes DIR/plugin.backgroundAssets/<platform>/data.tgz, each packed by pack.sh with a fixed epoch,
# DIR/pack.log (commit, tree, epoch, xcodebuild -version, the Solar2D build, sha256 of every
# archive), DIR/logs/ and DIR/work/. iphone: xcodebuild of ios/Plugin.xcodeproj, then libplugin_backgroundAssets.a
# and ios/metadata.lua (as metadata.lua) packed flat; mac-sim and win32-sim: lua/plugin_backgroundAssets.lua (the
# front), lua/plugin_backgroundAssets_backend.lua (the emulator backend) and lua/plugin_backgroundAssets_emulator.lua
# (the emulator module) packed flat. Never writes into the checkout, and fails when the build left a file or a new empty
# directory in it.
# Toolchains, overridable by env: DEVELOPER_DIR (Xcode 27.0), CORONA (/Applications/Corona-3733).
# Exit 0 = every archive written, 1 = a build step failed, 2 = usage or precondition error.
set -euo pipefail

PLATFORMS="iphone mac-sim win32-sim"

usage() { sed -n '3,4s/^# //p' "$0"; }
die() { echo "build.sh: $*" >&2; exit 2; }
fail() { echo "build.sh: $*" >&2; exit 1; }
value() { [[ -n "${2:-}" ]] || die "$1 needs a value"; }
clean() { [[ -z "$(git -C "$REPO" status --porcelain --ignored --untracked-files=all)" ]]; }
# empty_dirs: the checkout's empty directories outside .git, which git status does not show
empty_dirs() { find "$REPO" -path "$REPO/.git" -prune -o -type d -empty -print | sort; }
# outside dir: dir (existing) does not lie inside the checkout
outside() { [[ "$(cd "$1" && pwd -P)/" != "$REPO/"* ]]; }
note() { printf '%s\n' "$*" >>"$OUT/pack.log"; }
# pack platform tree [member...]: OUT/plugin.backgroundAssets/<platform>/data.tgz from tree
pack() {
  mkdir -p "$PKG/$1"
  "$REPO/tools/release/pack.sh" --mtime "$EPOCH" "$2" "$PKG/$1/data.tgz" "${@:3}"
}

build_iphone() {
  local t=$WORK/iphone src=$WORK/src
  # xcodebuild leaves an empty swiftpm tree inside the project it builds, so it builds a copy of the checkout's tree
  mkdir -p "$src" && git -C "$REPO" archive HEAD | tar -x -C "$src"
  (cd "$src" && env -u SDKROOT ZERO_AR_DATE=1 "$DEVELOPER_DIR/usr/bin/xcodebuild" -project ios/Plugin.xcodeproj \
    -scheme plugin_library -configuration Release -sdk iphoneos -derivedDataPath "$WORK/dd-ios" \
    CORONA_ROOT="$CORONA/Native" build) >"$LOGS/iphone.log" 2>&1 || fail "iphone: xcodebuild failed (log $LOGS/iphone.log)"
  mkdir -p "$t"
  cp "$WORK/dd-ios/Build/Products/Release-iphoneos/libplugin_backgroundAssets.a" "$t/"
  cp "$REPO/ios/metadata.lua" "$t/metadata.lua"
  pack iphone "$t"
}
pack_sim() {
  pack "$1" "$REPO/lua" plugin_backgroundAssets.lua plugin_backgroundAssets_backend.lua plugin_backgroundAssets_emulator.lua
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
COMMIT=HEAD OUT=""
while (( $# )); do
  case $1 in
    --commit) value "$@"; COMMIT=$2; shift 2 ;;
    --out) value "$@"; OUT=$2; shift 2 ;;
    -*) die "unknown option $1 (--help)" ;;
    *) break ;;
  esac
done
for plat in "$@"; do [[ " $PLATFORMS " == *" $plat "* ]] || die "unknown platform '$plat' (one of: $PLATFORMS)"; done
(( $# )) || set -- $PLATFORMS
WANT=" $* "
[[ -n "$OUT" ]] || die "--out is required"

# the checkout: clean, and at the released tree
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
[[ "$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" -ef "$REPO" ]] || die "$REPO is not a git checkout"
clean || die "$REPO is not clean"
EMPTY=$(empty_dirs)
TREE=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
[[ "$TREE" == "$(git -C "$REPO" rev-parse --verify -q "$COMMIT^{tree}")" ]] || die "HEAD^{tree} of $REPO is not $COMMIT^{tree}"
EPOCH=1767225600  # 2026-01-01T00:00:00Z, fixed: any commit of the same tree packs byte-identical archives, squash merges too

# OUT: absent or empty, outside the checkout; its parent must exist so nothing is created inside the checkout
[[ -d "$(dirname "$OUT")" ]] && outside "$(dirname "$OUT")" || die "--out $OUT must lie outside $REPO, in an existing directory"
[[ ! -e "$OUT" || ( -d "$OUT" && -z "$(ls -A "$OUT")" ) ]] || die "--out $OUT is not an empty directory"
mkdir -p "$OUT" && outside "$OUT" || die "--out $OUT lies inside $REPO"
OUT=$(cd "$OUT" && pwd -P)

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
CORONA=${CORONA:-/Applications/Corona-3733}
[[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || die "no xcodebuild in DEVELOPER_DIR $DEVELOPER_DIR"
[[ -d "$CORONA/Native" && -f "$CORONA/Corona Simulator.app/Contents/Info.plist" ]] || die "no Solar2D install in CORONA $CORONA"
PKG=$OUT/plugin.backgroundAssets WORK=$OUT/work LOGS=$OUT/logs
mkdir -p "$WORK" "$LOGS"
note "commit $(git -C "$REPO" rev-parse "$COMMIT^{commit}") tree $TREE"
note "epoch $EPOCH"
note "xcode $DEVELOPER_DIR: $(env -u SDKROOT "$DEVELOPER_DIR/usr/bin/xcodebuild" -version | paste -sd ' ' -)"
note "solar2d $CORONA: $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$CORONA/Corona Simulator.app/Contents/Info.plist")"

# a failing command anywhere in a platform's build ends the run with exit 1
set -E
trap 'fail "$plat failed (logs in $LOGS)"' ERR
for plat in $PLATFORMS; do
  [[ "$WANT" == *" $plat "* ]] || continue
  echo "build.sh: $plat"
  case $plat in
    iphone) build_iphone ;;
    mac-sim | win32-sim) pack_sim "$plat" ;;
  esac
done
trap - ERR

clean || fail "the build wrote into $REPO: $(git -C "$REPO" status --porcelain --ignored --untracked-files=all | head -3)"
NEW_EMPTY=$(comm -13 <(printf '%s\n' "$EMPTY") <(empty_dirs))
[[ -z "$NEW_EMPTY" ]] || fail "the build left empty directories in $REPO: $(head -3 <<<"$NEW_EMPTY")"
(cd "$OUT" && find plugin.backgroundAssets -name data.tgz | sort | xargs shasum -a 256) >>"$OUT/pack.log"
echo "build.sh: $PKG"
