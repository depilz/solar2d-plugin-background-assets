#!/bin/bash
# stub: the committed archives against their sources, and pack.sh's determinism.
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
ARCHIVES="$BA_REPO/plugin/com.studycat/plugin.backgroundAssets"
FRONT=plugin_backgroundAssets.lua
BACKEND=plugin_backgroundAssets_backend.lua
EMULATOR=plugin_backgroundAssets_emulator.lua

# extract platform member...: checks the archive's members, then unpacks it into SUITE_OUT/platform
extract() {
  local archive="$ARCHIVES/$1/data.tgz" dir="$SUITE_OUT/$1"
  python3 "$W/members.py" "$archive" "${@:2}" && mkdir -p "$dir" && tar -xzf "$archive" -C "$dir"
}

iphone_archive() {
  local dir="$SUITE_OUT/iphone"
  extract iphone libplugin_backgroundAssets.a metadata.lua &&
    cmp "$dir/metadata.lua" "$BA_REPO/ios/metadata.lua" &&
    lua51 "$W/tables.lua" "$dir/metadata.lua"
}

sim_archive() {
  local dir="$SUITE_OUT/$1"
  extract "$1" "$FRONT" "$BACKEND" "$EMULATOR" &&
    cmp "$dir/$FRONT" "$BA_REPO/lua/$FRONT" &&
    cmp "$dir/$BACKEND" "$BA_REPO/lua/$BACKEND" &&
    cmp "$dir/$EMULATOR" "$BA_REPO/lua/$EMULATOR"
}

# the second pack sees other file mtimes, which the epoch overrides
packs_identically() {
  local tree="$SUITE_OUT/fixture" pack="$BA_REPO/tools/release/pack.sh"
  mkdir -p "$tree/sub" && printf 'a\n' >"$tree/a.lua" && printf 'b\n' >"$tree/sub/b.txt" &&
    "$pack" --mtime 1700000000 "$tree" "$SUITE_OUT/first.tgz" &&
    touch -t 200001010000 "$tree/a.lua" "$tree/sub/b.txt" &&
    "$pack" --mtime 1700000000 "$tree" "$SUITE_OUT/second.tgz" &&
    cmp "$SUITE_OUT/first.tgz" "$SUITE_OUT/second.tgz"
}

run_test "archive iphone" iphone_archive
run_test "archive mac-sim" sim_archive mac-sim
run_test "archive win32-sim" sim_archive win32-sim
run_test "pack.sh deterministic" packs_identically
