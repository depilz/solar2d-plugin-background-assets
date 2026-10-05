#!/bin/bash
# extension: static checks of the downloader extension, extension/build.sh, tools/demo/ios-build.sh, the demo's
# build.settings, tools/demo/packs.sh and the demo pack sources that need no Xcode, profile or signing (the
# extension-sign suite builds and signs).
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
EXT="$BA_REPO/extension"
TOOL="$EXT/build.sh"
DEMO="$BA_REPO/tools/demo/ios-build.sh"
PACKS="$BA_REPO/tools/demo/packs.sh"
ARGS="--hosting apple --app-id com.example.app --app-group group.com.example.app --version 1.0 --build 1"
PROJECT="$SUITE_OUT/project"
PROFILE="$SUITE_OUT/fake.mobileprovision"
mkdir -p "$PROJECT" "$SUITE_OUT/no-settings"
touch "$PROJECT/build.settings" "$PROFILE"

# exits code text command...: the command exits with code, and its stderr holds text
exits() {
  local code=$1 text=$2 status=0
  shift 2
  "$@" 2>"$SUITE_OUT/stderr" || status=$?
  cat "$SUITE_OUT/stderr"
  [[ $status == "$code" ]] && grep -qF -- "$text" "$SUITE_OUT/stderr"
}

help_prints_usage() { "$TOOL" --help | grep -F 'usage: extension/build.sh --hosting apple|self'; }

work_inside_checkout() {
  exits 2 "must lie outside" "$TOOL" $ARGS --profile "$PROFILE" --project "$PROJECT" \
    --work "$BA_REPO/.extension-work" &&
    [[ ! -e "$BA_REPO/.extension-work" ]]
}

info_plist() {
  [[ "$(plutil -extract EXAppExtensionAttributes.EXExtensionPointIdentifier raw "$EXT/Info.plist")" == \
    com.apple.background-asset-downloader-extension ]] && plutil -extract CFBundleDisplayName raw "$EXT/Info.plist"
}

swift_flavours() {
  local swift="$EXT/DownloaderExtension.swift"
  grep -qx '#if SELF_HOSTED' "$swift" && grep -q ': ManagedDownloaderExtension' "$swift" &&
    grep -q ': StoreDownloaderExtension' "$swift" && ! grep -F '[S1]' "$swift"
}

# demo_refused_before_out: refused at the installed-archive check (HOME has no Solar2DPlugins), an absent --out stays
# absent
demo_refused_before_out() {
  exits 2 "is missing; install the plugin" env HOME="$SUITE_OUT/no-plugins" "$DEMO" --profile "$PROFILE" \
    --ext-profile "$PROFILE" --out "$SUITE_OUT/refused" &&
    [[ ! -e "$SUITE_OUT/refused" ]]
}

# demo_refused_after_out: refused at the app profile, past the checks before --out is made (a HOME holding the committed
# iphone archive, any DEVELOPER_DIR): an absent --out is removed again, an existing empty one is left empty
demo_refused_after_out() {
  local home="$SUITE_OUT/home" plugin=Solar2DPlugins/com.studycat/plugin.backgroundAssets/iphone
  mkdir -p "$home/$plugin" "$SUITE_OUT/empty" &&
    cp "$BA_REPO/plugin/com.studycat/plugin.backgroundAssets/iphone/data.tgz" "$home/$plugin/" &&
    exits 2 "is not a provisioning profile" env HOME="$home" DEVELOPER_DIR="$SUITE_OUT" "$DEMO" --profile "$PROFILE" \
      --ext-profile "$PROFILE" --out "$SUITE_OUT/absent" &&
    [[ ! -e "$SUITE_OUT/absent" ]] &&
    exits 2 "is not a provisioning profile" env HOME="$home" DEVELOPER_DIR="$SUITE_OUT" "$DEMO" --profile "$PROFILE" \
      --ext-profile "$PROFILE" --out "$SUITE_OUT/empty" &&
    [[ -d "$SUITE_OUT/empty" && -z "$(ls -A "$SUITE_OUT/empty")" ]]
}

# demo_packs: each tools/demo/packs/<id>.json is the manifest of pack <id>, an id without underscore, holding the PNG,
# WAV and text file under <id>/; one pack is onDemand and one prefetch
demo_packs() {
  python3 - "$BA_REPO/tools/demo/packs" <<'PY'
import glob, json, os, sys
root = sys.argv[1]
policies = []
for path in sorted(glob.glob(os.path.join(root, "*.json"))):
    pack_id = os.path.basename(path)[:-5]
    manifest = json.load(open(path))
    assert manifest["assetPackID"] == pack_id and "_" not in pack_id and "spike" not in pack_id, pack_id
    files = [selector["file"] for selector in manifest["fileSelectors"]]
    assert files == [pack_id + "/image.png", pack_id + "/sound.wav", pack_id + "/text.txt"], files
    heads = [open(os.path.join(root, f), "rb").read(12) for f in files]
    assert heads[0][:8] == b"\x89PNG\r\n\x1a\n" and heads[1][:4] == b"RIFF" and heads[1][8:] == b"WAVE", pack_id
    policies += list(manifest["downloadPolicy"])
assert sorted(policies) == ["onDemand", "prefetch"], policies
PY
}

# demo_settings: Corona/build.settings loads under Lua 5.1 and carries C-3's Apple-hosting keys and entitlements
demo_settings() {
  lua51 -e "dofile('$BA_REPO/Corona/build.settings')
    local p, e = settings.iphone.plist, settings.iphone.entitlements
    local groups = e['com.apple.security.application-groups']
    assert(p.BAAppGroupID == 'group.net.studycat.funlanguages' and p.BAHasManagedAssetPacks == true and
      p.BAUsesAppleHosting == true and p.MinimumOSVersion == '26.0', 'plist keys')
    assert(#groups == 1 and groups[1] == p.BAAppGroupID and
      e['com.apple.developer.team-identifier'] == 'SEY52S4BJ9', 'entitlements')"
}

run_test "build.sh bash 3.2 syntax" /bin/bash -n "$TOOL"
run_test "build.sh --help" help_prints_usage
run_test "build.sh no arguments: exit 2" exits 2 "are required" "$TOOL"
run_test "build.sh missing profile: exit 2" exits 2 "is not a file" "$TOOL" $ARGS --profile "$SUITE_OUT/missing" \
  --project "$PROJECT"
run_test "build.sh project without build.settings: exit 2" exits 2 "not a directory holding build.settings" "$TOOL" \
  $ARGS --profile "$PROFILE" --project "$SUITE_OUT/no-settings"
run_test "build.sh work inside checkout: exit 2" work_inside_checkout
run_test "build.sh project inside checkout: exit 2" exits 2 "lies inside" "$TOOL" $ARGS --profile "$PROFILE" \
  --project "$BA_REPO/Corona"
run_test "build.sh flag given as a value: exit 2" exits 2 "--profile needs a value" "$TOOL" $ARGS --profile \
  --project "$PROJECT"
run_test "Info.plist extension point and display name" info_plist
run_test "Swift source has both flavours, no [S1]" swift_flavours
run_test "ios-build.sh bash 3.2 syntax" /bin/bash -n "$DEMO"
run_test "ios-build.sh self without --manifest-url: exit 2" exits 2 "needs --manifest-url" "$DEMO" --profile "$PROFILE" \
  --ext-profile "$PROFILE" --out "$SUITE_OUT/demo" --hosting self
run_test "ios-build.sh --manifest-url with apple: exit 2" exits 2 "for --hosting self only" "$DEMO" --profile "$PROFILE" \
  --ext-profile "$PROFILE" --out "$SUITE_OUT/demo" --manifest-url https://example.invalid/manifest.json
run_test "ios-build.sh refused before --out is made: no --out left" demo_refused_before_out
run_test "ios-build.sh refused after --out is made: --out as found" demo_refused_after_out
run_test "Corona/build.settings carries C-3 (Lua 5.1)" demo_settings
run_test "packs.sh bash 3.2 syntax" /bin/bash -n "$PACKS"
run_test "packs.sh --out inside checkout: exit 2" exits 2 "must lie outside" "$PACKS" --out "$BA_REPO/tools/out"
run_test "packs.sh http base URL: exit 2" exits 2 "is not an https URL" "$PACKS" --out "$SUITE_OUT/packs" \
  --download-base-url http://example.com/
run_test "demo packs: ids without underscore, onDemand and prefetch, PNG, WAV and text each" demo_packs
