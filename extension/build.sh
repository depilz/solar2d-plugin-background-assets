#!/bin/bash
# Downloader extension tool: builds one flavour of the Background Assets downloader extension for an app, signs it with
# the extension's own provisioning profile and writes it into a Solar2D project's Extensions/ before the iOS build.
# usage: extension/build.sh --hosting apple|self --app-id <bundle id> --app-group <group id>
#          --profile <extension .mobileprovision> --version <CFBundleShortVersionString> --build <CFBundleVersion>
#          --project <Solar2D project dir> [--suffix <component>] [--identity <SHA-1>] [--display-name <name>]
#          [--work <dir>]
# The extension's bundle id is <app id>.<suffix> (suffix default BADownloader), its CFBundleDisplayName the display name
# (default: the suffix). The profile is an unexpired Development or App Store profile for <team>.<app id>.<suffix>
# carrying the app group. Signs with --identity, else with the first valid codesigning identity whose certificate the
# profile carries. --project (holding build.settings) and --work (default: a temporary dir, kept only when the build
# fails) lie outside this checkout, which the tool never writes into. Replaces <project>/Extensions/<suffix>.appex and
# checks it with codesign --verify --deep --strict.
# Toolchain, overridable by env: DEVELOPER_DIR (Xcode 27.0).
# Exit 0 = built, 1 = the build or signing failed, 2 = usage or precondition error.
set -euo pipefail

usage() { sed -n '4,7s/^# //p' "$0"; }
die() { echo "build.sh: $*" >&2; exit 2; }
fail() { echo "build.sh: $*" >&2; exit 1; }
value() { [[ -n "${2:-}" && "$2" != --* ]] || die "$1 needs a value"; }
# outside dir: dir (existing) does not lie inside the checkout
outside() { [[ "$(cd "$1" && pwd -P)/" != "$REPO/"* ]]; }
# profile key: the decoded profile's value at key (PlistBuddy path), failing when absent
profile() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }
has_group() { profile Entitlements:com.apple.security.application-groups | sed 's/^ *//' | grep -qxF "$APP_GROUP"; }
# keep a temporary work dir only when the build failed, for its logs
cleanup() { local code=$?; [[ $code == 1 ]] || rm -rf "$WORK"; }

# profile_identity: the SHA-1 of the first profile certificate that is a valid codesigning identity here; never a name,
# because two valid identities can share a certificate name
profile_identity() {
  local identities count i hash
  identities=$(security find-identity -v -p codesigning | grep -v CSSMERR_)
  count=$(plutil -extract DeveloperCertificates raw "$PLIST")
  for ((i = 0; i < count; i++)); do
    hash=$(plutil -extract "DeveloperCertificates.$i" raw "$PLIST" | base64 -D | shasum -a1 | cut -c1-40 | tr a-f A-F)
    if grep -qF " $hash " <<<"$identities"; then echo "$hash"; return; fi
  done
  return 1
}

write_entitlements() {
  local plist=$WORK/entitlements.plist
  rm -f "$plist"
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.application-groups array' \
    -c "Add :com.apple.security.application-groups:0 string $APP_GROUP" \
    -c "Add :application-identifier string $TEAM.$EXT_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM" "$plist" >/dev/null &&
    if [[ $KIND == development ]]; then /usr/libexec/PlistBuddy -c 'Add :get-task-allow bool true' "$plist"; fi
}

build_appex() {
  local src=$WORK/src
  rm -rf "$src" && mkdir -p "$src" &&
    cp -R "$HERE/Extension.xcodeproj" "$HERE/DownloaderExtension.swift" "$HERE/Info.plist" "$src/" &&
    plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$src/Info.plist" &&
    (cd "$src" && env -u SDKROOT "$DEVELOPER_DIR/usr/bin/xcodebuild" -project Extension.xcodeproj -scheme BADownloader \
      -configuration Release -sdk iphoneos -derivedDataPath "$WORK/dd" PRODUCT_NAME="$SUFFIX" \
      PRODUCT_BUNDLE_IDENTIFIER="$EXT_ID" CURRENT_PROJECT_VERSION="$BUILD" MARKETING_VERSION="$VERSION" \
      SWIFT_ACTIVE_COMPILATION_CONDITIONS="$CONDITIONS" CODE_SIGNING_ALLOWED=NO build) >"$WORK/xcodebuild.log" 2>&1 &&
    rm -rf "$APPEX" && cp -R "$WORK/dd/Build/Products/Release-iphoneos/$SUFFIX.appex" "$APPEX"
}

sign_appex() {
  write_entitlements && cp "$PROFILE" "$APPEX/embedded.mobileprovision" &&
    codesign --force --sign "$IDENTITY" --entitlements "$WORK/entitlements.plist" --generate-entitlement-der \
      --timestamp=none "$APPEX" >"$WORK/codesign.log" 2>&1
}

[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }
HOSTING="" APP_ID="" SUFFIX=BADownloader APP_GROUP="" PROFILE="" VERSION="" BUILD="" PROJECT="" IDENTITY=""
DISPLAY_NAME="" WORK=""
while (( $# )); do
  case $1 in
    --hosting) value "$@"; HOSTING=$2; shift 2 ;;
    --app-id) value "$@"; APP_ID=$2; shift 2 ;;
    --suffix) value "$@"; SUFFIX=$2; shift 2 ;;
    --app-group) value "$@"; APP_GROUP=$2; shift 2 ;;
    --profile) value "$@"; PROFILE=$2; shift 2 ;;
    --version) value "$@"; VERSION=$2; shift 2 ;;
    --build) value "$@"; BUILD=$2; shift 2 ;;
    --project) value "$@"; PROJECT=$2; shift 2 ;;
    --identity) value "$@"; IDENTITY=$2; shift 2 ;;
    --display-name) value "$@"; DISPLAY_NAME=$2; shift 2 ;;
    --work) value "$@"; WORK=$2; shift 2 ;;
    *) die "unknown argument $1 (--help)" ;;
  esac
done
[[ -n "$HOSTING" && -n "$APP_ID" && -n "$APP_GROUP" && -n "$PROFILE" && -n "$VERSION" && -n "$BUILD" &&
  -n "$PROJECT" ]] ||
  die "--hosting, --app-id, --app-group, --profile, --version, --build and --project are required (--help)"
case $HOSTING in
  apple) CONDITIONS="" ;;
  self) CONDITIONS=SELF_HOSTED ;;
  *) die "--hosting must be apple or self, not $HOSTING" ;;
esac
[[ "$SUFFIX" =~ ^[A-Za-z0-9-]+$ ]] || die "--suffix $SUFFIX is not one bundle id component"
[[ -z "$IDENTITY" || "$IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] || die "--identity $IDENTITY is not a certificate SHA-1"
DISPLAY_NAME=${DISPLAY_NAME:-$SUFFIX}
EXT_ID=$APP_ID.$SUFFIX
HERE=$(cd "$(dirname "$0")" && pwd -P)
REPO=$(dirname "$HERE")

[[ -d "$PROJECT" && -f "$PROJECT/build.settings" ]] ||
  die "--project $PROJECT is not a directory holding build.settings"
outside "$PROJECT" || die "--project $PROJECT lies inside $REPO; build a copy of the project outside it"
PROJECT=$(cd "$PROJECT" && pwd -P)
[[ -f "$PROFILE" ]] || die "--profile $PROFILE is not a file"
PROFILE="$(cd "$(dirname "$PROFILE")" && pwd -P)/$(basename "$PROFILE")"

if [[ -n "$WORK" ]]; then
  [[ -d "$(dirname "$WORK")" ]] && outside "$(dirname "$WORK")" ||
    die "--work $WORK must lie outside $REPO, in an existing directory"
  mkdir -p "$WORK" && outside "$WORK" || die "--work $WORK lies inside $REPO"
  WORK=$(cd "$WORK" && pwd -P)
else
  outside "${TMPDIR:-/tmp}" || die "TMPDIR ${TMPDIR:-/tmp} lies inside $REPO; pass --work"
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/ba-extension.XXXXXX") || die "cannot create a work dir"
  trap cleanup EXIT
fi
PLIST=$WORK/profile.plist
APPEX=$WORK/$SUFFIX.appex

security cms -D -i "$PROFILE" -o "$PLIST" 2>/dev/null || die "--profile $PROFILE is not a provisioning profile"
[[ "$(plutil -extract ExpirationDate raw "$PLIST")" > "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]] ||
  die "--profile $PROFILE has expired"
TEAM=$(plutil -extract TeamIdentifier.0 raw "$PLIST") || die "--profile $PROFILE has no TeamIdentifier"
[[ "$(profile Entitlements:application-identifier)" == "$TEAM.$EXT_ID" ]] ||
  die "--profile $PROFILE is not for $TEAM.$EXT_ID (it is for $(profile Entitlements:application-identifier || true))"
has_group || die "--profile $PROFILE does not carry the app group $APP_GROUP"
if [[ "$(profile Entitlements:get-task-allow)" == true ]]; then
  KIND=development
elif ! profile ProvisionedDevices >/dev/null; then
  KIND=app-store
else
  die "--profile $PROFILE is an ad hoc profile; pass a Development or App Store one"
fi

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
[[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || die "no xcodebuild in DEVELOPER_DIR $DEVELOPER_DIR"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(profile_identity) || die "no valid codesigning identity here holds a certificate of $PROFILE"
fi

echo "build.sh: building the $HOSTING-hosting extension $EXT_ID ($VERSION, $BUILD) with $DEVELOPER_DIR"
build_appex || fail "the build failed, see $WORK/xcodebuild.log"
# the Solar2D packager's rsync drops dotfiles and dereferences symlinks, and its copypng pass rewrites PNGs: any of
# them in the appex would break its seal inside the app
UNSAFE=$(find "$APPEX" -mindepth 1 \( -name '.*' -o -type l -o -iname '*.png' \) -print)
[[ -z "$UNSAFE" ]] || fail "$APPEX holds a dotfile, symlink or PNG the Solar2D packager would alter: $UNSAFE"
sign_appex || fail "signing with $IDENTITY failed, see $WORK/codesign.log"

DEST=$PROJECT/Extensions/$SUFFIX.appex
mkdir -p "$PROJECT/Extensions" && rm -rf "$DEST" && cp -R "$APPEX" "$DEST" || fail "cannot write $DEST"
codesign --verify --deep --strict "$DEST" || fail "$DEST does not pass codesign --verify --deep --strict"
echo "build.sh: wrote $DEST ($KIND profile, identity $IDENTITY)"
