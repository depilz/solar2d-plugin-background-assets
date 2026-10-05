#!/bin/bash
# native: the committed iphone archive's library (nm, otool): its Lua entry point, the embedded Lua front, its iOS
# floor, and its Background Assets references, all weak and none to an iOS-27-only data symbol.
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
LIB="$SUITE_OUT/libplugin_backgroundAssets.a"
FRONT="$BA_REPO/lua/plugin_backgroundAssets.lua"
# the library's undefined Background Assets symbols: its C globals and its Objective-C classes
BA_SYMBOL=' _(OBJC_(META)?CLASS_\$_)?BA[A-Za-z]*$'

tar -xzf "$BA_REPO/plugin/com.studycat/plugin.backgroundAssets/iphone/data.tgz" -C "$SUITE_OUT" \
  libplugin_backgroundAssets.a
nm -m "$LIB" >"$SUITE_OUT/nm.txt"
otool -l "$LIB" >"$SUITE_OUT/otool.txt"

embeds_front() {
  python3 -c 'import sys; sys.exit(open(sys.argv[2], "rb").read() not in open(sys.argv[1], "rb").read())' "$LIB" "$FRONT"
}

# every LC_BUILD_VERSION in the library names platform iOS and minos 13.0
minos_13() {
  awk '/cmd LC_BUILD_VERSION/ { n++ } /^ *minos / { m[$2]++ } END { for (v in m) print "minos " v; exit !(n && m["13.0"] == n) }' \
    "$SUITE_OUT/otool.txt"
}

# at least one Background Assets reference, and every one weak
weak_ba() {
  grep -E "\(undefined\) .*$BA_SYMBOL" "$SUITE_OUT/nm.txt" && ! grep -E "\(undefined\) external$BA_SYMBOL" "$SUITE_OUT/nm.txt"
}

run_test "exports luaopen_plugin_backgroundAssets" grep -E ' \(__TEXT,__text\) external _luaopen_plugin_backgroundAssets$' \
  "$SUITE_OUT/nm.txt"
run_test "embeds the Lua front" embeds_front
run_test "LC_BUILD_VERSION minos 13.0" minos_13
run_test "Background Assets symbols weak" weak_ba
run_test "no BASuccessesErrorKey or BAFailuresErrorKey" bash -c '! grep -E " _BA(Successes|Failures)ErrorKey$" "$1"' _ \
  "$SUITE_OUT/nm.txt"
