#!/bin/bash
# Demo device build: builds a copy of Corona/ for an iOS device with CoronaBuilder, carrying the downloader extension.
# usage: tools/demo/ios-build.sh --profile <app .mobileprovision> --ext-profile <extension .mobileprovision> --out <dir>
#          [--hosting apple|self] [--manifest-url <https URL>] [--build-number <n>]
# The profiles lie outside the repo; <dir> (absent or empty) lies outside the repo, in an existing directory. The app id
# is the app profile's, and both profiles carry Corona/build.settings' app group. Copies Corona/ to <dir>/project, sets
# CFBundleVersion there to --build-number (default: build.settings'), and for --hosting self (which needs
# --manifest-url) switches it to self-hosting. Then extension/build.sh writes the extension into
# <dir>/project/Extensions/ and CoronaBuilder builds the copy: a Development profile gives <dir>/build/BADemo.app, an
# App Store one <dir>/build/BADemo.ipa. Writes <dir>/descriptor.lua and <dir>/build.log, then prints the owner's next
# command (install and launch, or upload). The plugin comes from ~/Solar2DPlugins, whose
# com.studycat/plugin.backgroundAssets/iphone/data.tgz must equal the repo's committed iphone archive (copy the repo's
# plugin/com.studycat/plugin.backgroundAssets/ there, as in the quickstart's Local copy).
# Toolchains, overridable by env: DEVELOPER_DIR (Xcode 27.0), CORONA (/Applications/Corona-3733).
# Exit 0 = BADemo built with the plugin and the extension, 1 = the build failed, 2 = usage or precondition error (<dir>
# left as it was found).
set -euo pipefail

usage() { sed -n '3,4s/^# //p' "$0"; }
die() { echo "ios-build.sh: $*" >&2; exit 2; }
fail() { echo "ios-build.sh: $*" >&2; exit 1; }
value() { [[ -n "${2:-}" && "$2" != --* ]] || die "$1 needs a value"; }
# physical path: path made absolute with symlinks resolved; when path is no directory, only its (existing) parent is
physical() {
  if [[ -d "$1" ]]; then (cd "$1" && pwd -P); else echo "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"; fi
}
# outside path: path (a directory, or absent with an existing parent) does not lie inside the repo
outside() { [[ "$(physical "$1")/" != "$REPO/"* ]]; }
# undo: on a refusal (exit 2), empties OUT and removes it when this run created it; a failed build keeps its logs
undo() {
  (( $? == 2 )) || return 0
  find "$OUT" -mindepth 1 -delete
  [[ -z "$CREATED" ]] || rmdir "$OUT"
}
# lua_string text: text as a single-quoted Lua string
lua_string() { printf "'%s'" "$(printf '%s' "$1" | sed "s/[\\\\']/\\\\&/g")"; }
# profile_path option path: path, an existing file outside the repo, made absolute
profile_path() {
  [[ -f "$2" ]] || die "$1 $2 is not a file"
  outside "$(dirname "$2")" || die "$1 $2 lies inside $REPO; keep signing material out of the repo"
  echo "$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
}
# settings_value key: settings.iphone.plist[key] of the staged build.settings
settings_value() {
  "$LUA" -e "dofile($(lua_string "$PROJECT/build.settings")) print(settings.iphone.plist.$1)"
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
PROFILE="" EXT_PROFILE="" OUT="" HOSTING=apple MANIFEST_URL="" BUILD_NUMBER=""
while (( $# )); do
  case $1 in
    --profile) value "$@"; PROFILE=$2; shift 2 ;;
    --ext-profile) value "$@"; EXT_PROFILE=$2; shift 2 ;;
    --out) value "$@"; OUT=$2; shift 2 ;;
    --hosting) value "$@"; HOSTING=$2; shift 2 ;;
    --manifest-url) value "$@"; MANIFEST_URL=$2; shift 2 ;;
    --build-number) value "$@"; BUILD_NUMBER=$2; shift 2 ;;
    *) die "unknown argument $1 (--help)" ;;
  esac
done
[[ -n "$PROFILE" && -n "$EXT_PROFILE" && -n "$OUT" ]] || die "--profile, --ext-profile and --out are required"
case $HOSTING in
  apple) [[ -z "$MANIFEST_URL" ]] || die "--manifest-url is for --hosting self only" ;;
  self) [[ "$MANIFEST_URL" =~ ^https://[^/:?#]+ ]] || die "--hosting self needs --manifest-url <https URL>" ;;
  *) die "--hosting must be apple or self, not $HOSTING" ;;
esac
[[ -z "$BUILD_NUMBER" || "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] ||
  die "--build-number $BUILD_NUMBER is not a CFBundleVersion (n, n.n or n.n.n)"
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
SUFFIX=BADownloader

PROFILE=$(profile_path --profile "$PROFILE")
EXT_PROFILE=$(profile_path --ext-profile "$EXT_PROFILE")

[[ -d "$(dirname "$OUT")" ]] && outside "$(dirname "$OUT")" || die "--out $OUT must lie outside $REPO, in an existing directory"
[[ ! -e "$OUT" || ( -d "$OUT" && -z "$(ls -A "$OUT")" ) ]] || die "--out $OUT is not an empty directory"
outside "$OUT" || die "--out $OUT lies inside $REPO"
OUT=$(physical "$OUT")

INSTALLED=$HOME/Solar2DPlugins/com.studycat/plugin.backgroundAssets/iphone/data.tgz
COMMITTED=$REPO/plugin/com.studycat/plugin.backgroundAssets/iphone/data.tgz
INSTALL_HINT="copy $REPO/plugin/com.studycat/plugin.backgroundAssets/ into ~/Solar2DPlugins/com.studycat/"
[[ -f "$INSTALLED" ]] || die "$INSTALLED is missing; $INSTALL_HINT"
cmp -s "$INSTALLED" "$COMMITTED" ||
  die "$INSTALLED differs from the repo's $COMMITTED; $INSTALL_HINT"

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
CORONA=${CORONA:-/Applications/Corona-3733}
BUILDER=$CORONA/Native/Corona/mac/bin/CoronaBuilder.app/Contents/MacOS/CoronaBuilder
LUA=$CORONA/Native/Corona/mac/bin/lua
[[ -d "$DEVELOPER_DIR" ]] || die "no Xcode at DEVELOPER_DIR $DEVELOPER_DIR"
[[ -x "$BUILDER" && -x "$LUA" ]] || die "no CoronaBuilder and lua in CORONA $CORONA"

# --out is made only now, after the checks that need no output dir; a later refusal leaves it as it was found
CREATED=""
[[ -d "$OUT" ]] || { mkdir "$OUT" && CREATED=$OUT; } || die "cannot create --out $OUT"
trap undo EXIT

# the build works on a copy: extension/build.sh writes into the project, and never into the repo
PROJECT=$OUT/project
cp -R "$REPO/Corona" "$PROJECT"
{
  echo
  echo '-- tools/demo/ios-build.sh'
  echo 'settings.iphone = settings.iphone or {}'
  echo 'settings.iphone.plist = settings.iphone.plist or {}'
  [[ -z "$BUILD_NUMBER" ]] || echo "settings.iphone.plist.CFBundleVersion = $(lua_string "$BUILD_NUMBER")"
  if [[ $HOSTING == self ]]; then
    HOST=${MANIFEST_URL#https://}
    HOST=${HOST%%[/:?#]*}
    echo 'settings.iphone.plist.BAUsesAppleHosting = false'
    echo "settings.iphone.plist.BAManifestURL = $(lua_string "$MANIFEST_URL")"
    # without it, iOS kills a self-hosting app at launch
    echo 'settings.iphone.plist.BAInitialDownloadRestrictions = { BADownloadAllowance = 1048576,'
    echo "  BAEssentialDownloadAllowance = 1048576, BADownloadDomainAllowList = { $(lua_string "$HOST") } }"
    echo "settings.iphone.plist.NSLocalNetworkUsageDescription = 'Downloads asset packs from a server on this network.'"
  fi
} >>"$PROJECT/build.settings"
VERSION=$(settings_value CFBundleShortVersionString) && BUILD=$(settings_value CFBundleVersion) &&
  APP_GROUP=$(settings_value BAAppGroupID) || die "cannot read $PROJECT/build.settings"

# extension/build.sh checks the extension profile; the app profile must carry the same app group
security cms -D -i "$PROFILE" -o "$OUT/profile.plist" 2>/dev/null || die "--profile $PROFILE is not a provisioning profile"
/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' "$OUT/profile.plist" 2>/dev/null |
  sed 's/^ *//' | grep -qxF "$APP_GROUP" || die "--profile $PROFILE does not carry the app group $APP_GROUP"
TEAM=$(plutil -extract TeamIdentifier.0 raw "$OUT/profile.plist") || die "--profile $PROFILE has no TeamIdentifier"
APP_ID=$(plutil -extract Entitlements.application-identifier raw "$OUT/profile.plist") ||
  die "--profile $PROFILE has no application-identifier"
APP_ID=${APP_ID#"$TEAM".}

"$REPO/extension/build.sh" --hosting "$HOSTING" --app-id "$APP_ID" --suffix "$SUFFIX" --app-group "$APP_GROUP" \
  --profile "$EXT_PROFILE" --version "$VERSION" --build "$BUILD" --project "$PROJECT" --work "$OUT/extension"

mkdir -p "$OUT/build"
cat >"$OUT/descriptor.lua" <<EOF
local params = {
    platform='ios',
    appName='BADemo',
    appVersion=$(lua_string "$VERSION"),
    dstPath=$(lua_string "$OUT/build"),
    certificatePath=$(lua_string "$PROFILE"),
    projectPath=$(lua_string "$PROJECT"),
}
return params
EOF

echo "ios-build.sh: building (log in $OUT/build.log)"
"$BUILDER" build --lua "$OUT/descriptor.lua" >"$OUT/build.log" 2>&1 || fail "CoronaBuilder failed, see $OUT/build.log"
# a declared plugin whose archive is missing is skipped silently, so the build log must name it
grep -q 'Found native plugin: .*/\.build/plugin\.backgroundAssets[[:space:]]*$' "$OUT/build.log" ||
  fail "the build did not package plugin.backgroundAssets (no 'Found native plugin' line in $OUT/build.log)"
# an App Store profile (no ProvisionedDevices) leaves only the .ipa
if plutil -extract ProvisionedDevices xml1 -o /dev/null "$OUT/profile.plist" 2>/dev/null; then
  APP=$OUT/build/BADemo.app
  [[ -d "$APP" ]] || fail "no $APP after the build, see $OUT/build.log"
else
  IPA=$OUT/build/BADemo.ipa
  [[ -f "$IPA" ]] || fail "no $IPA after the build, see $OUT/build.log"
  ditto -x -k "$IPA" "$OUT/ipa" || fail "cannot unpack $IPA"
  APP=$OUT/ipa/Payload/BADemo.app
  [[ -d "$APP" ]] || fail "$IPA holds no Payload/BADemo.app"
fi
[[ -d "$APP/Extensions/$SUFFIX.appex" ]] || fail "$APP has no Extensions/$SUFFIX.appex"
codesign --verify --deep --strict "$APP" || fail "$APP does not pass codesign --verify --deep --strict"
BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")

if [[ -n "${IPA:-}" ]]; then
  echo "ios-build.sh: built $IPA ($BUNDLE_ID $VERSION ($BUILD), $HOSTING hosting). Upload it to TestFlight with:"
  echo "  xcrun altool --upload-app -f \"$IPA\" -t ios --apiKey <key id> --apiIssuer <issuer id>"
else
  echo "ios-build.sh: built $APP ($BUNDLE_ID $VERSION ($BUILD), $HOSTING hosting). Install and launch it on a device with:"
  echo "  xcrun devicectl device install app --device <device> \"$APP\""
  echo "  xcrun devicectl device process launch --device <device> --terminate-existing --console $BUNDLE_ID"
fi
