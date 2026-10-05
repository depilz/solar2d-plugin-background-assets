#!/bin/bash
# run.sh: named-only
# native-harness: the real ios/Plugin/PluginBackgroundAssets.m built off-device as a macOS bundle (clang -bundle
# -undefined dynamic_lookup -framework Foundation, macOS SDK of DEVELOPER_DIR), with a stand-in for its generated front
# header whose chunk returns the backend table, and loaded through package.loadlib by Solar2D's mac lua. harness.m,
# its own bundle loaded first, stubs Corona's symbols and swizzles in fakes for Background Assets' manager and the user
# defaults. One row for the build, then one per case in cases.lua: the file handle, the 513 policy, the links and the
# removed-pack record.
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
CORONA_INCLUDE=${CORONA:-/Applications/Corona-3733}/Native/Corona/shared/include
BUILD="$SUITE_OUT/build"

# bundle out sources... [flags...]: a macOS bundle whose undefined symbols the lua process resolves at load
bundle() {
  local out=$1
  shift
  xcrun --sdk macosx clang -bundle -undefined dynamic_lookup -framework Foundation -mmacosx-version-min=27.0 \
    -I"$CORONA_INCLUDE/Corona" -I"$CORONA_INCLUDE/lua" -o "$out" "$@"
}

# the front header the Embed Lua front build phase would generate, for the chunk "return ..."
stand_in_front() {
  mkdir -p "$BUILD/include" &&
    { echo 'static const unsigned char kFront[] = {' && printf 'return ...' | xxd -i && echo '};'; } \
      >"$BUILD/include/PluginBackgroundAssetsFront.h"
}

build() {
  stand_in_front &&
    bundle "$BUILD/plugin.so" -I"$BUILD/include" "$BA_REPO/ios/Plugin/PluginBackgroundAssets.m" &&
    bundle "$BUILD/harness.so" -framework BackgroundAssets "$W/harness.m"
}

run_test "builds PluginBackgroundAssets.m as a macOS bundle" build
ids=$(lua51 "$W/cases.lua" "$BUILD" --list)
while IFS= read -r id; do
  run_test "$id" lua51 "$W/cases.lua" "$BUILD" "$id"
done <<<"$ids"
