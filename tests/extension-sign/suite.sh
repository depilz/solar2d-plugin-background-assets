#!/bin/bash
# run.sh: named-only
# extension-sign: builds and signs both flavours of the downloader extension with extension/build.sh for each of two
# extension profiles, BA_EXT_DEV_PROFILE (Development) and BA_EXT_STORE_PROFILE (App Store), both required (there is
# no skip). The app id, suffix and app group come from each profile's application-identifier and first app group.
# Every build goes into SUITE_OUT, over a stale appex it must replace; the tool's toolchain is DEVELOPER_DIR. With the
# Development profile it also builds with --display-name and with --identity (the SHA-1 of the identity the profile
# matches), and runs a malformed --identity that must exit 2 and write nothing.
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
TOOL="$BA_REPO/extension/build.sh"

checkout_state() { git -C "$BA_REPO" status --porcelain --ignored --untracked-files=all; }
# entry plist key: the value at key (PlistBuddy path) in plist
entry() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

# build kind flavour profile [tool args...]: runs the tool for the profile's extension id into
# SUITE_OUT/<kind>-<flavour>/project, passing it the extra args
build() {
  local dir="$SUITE_OUT/$1-$2" ext_id stale
  [[ -f "${3:-}" ]] ||
    { echo "extension-sign: no $1 profile; set BA_EXT_DEV_PROFILE and BA_EXT_STORE_PROFILE"; return 1; }
  mkdir -p "$dir" && security cms -D -i "$3" -o "$dir/profile.plist" &&
    ext_id=$(entry "$dir/profile.plist" Entitlements:application-identifier) || return
  ext_id=${ext_id#*.}
  stale="$dir/project/Extensions/${ext_id##*.}.appex/stale"
  mkdir -p "$(dirname "$stale")" && touch "$stale" "$dir/project/build.settings" &&
    "$TOOL" --hosting "$2" --app-id "${ext_id%.*}" --suffix "${ext_id##*.}" \
      --app-group "$(entry "$dir/profile.plist" Entitlements:com.apple.security.application-groups:0)" --profile "$3" \
      --version 1.0.0 --build 1 --project "$dir/project" --work "$dir/work" "${@:4}" &&
    [[ ! -e "$stale" ]]
}

# appex kind flavour: the appex the build wrote
appex() { ls -d "$SUITE_OUT/$1-$2/project/Extensions/"*.appex; }

verifies() { codesign --verify --deep --strict --verbose=2 "$(appex "$1" "$2")"; }

# entitlements kind flavour: the app group, application and team ids, and get-task-allow only for Development
entitlements() {
  local dir="$SUITE_OUT/$1-$2" signed="$SUITE_OUT/$1-$2/signed.plist" team
  codesign -d --entitlements - --xml "$(appex "$1" "$2")" >"$signed" 2>/dev/null && plutil -p "$signed" &&
    team=$(entry "$dir/profile.plist" TeamIdentifier:0) &&
    [[ "$(entry "$signed" application-identifier)" == \
      "$(entry "$dir/profile.plist" Entitlements:application-identifier)" ]] &&
    [[ "$(entry "$signed" com.apple.developer.team-identifier)" == "$team" ]] &&
    [[ "$(entry "$signed" com.apple.security.application-groups:0)" == \
      "$(entry "$dir/profile.plist" Entitlements:com.apple.security.application-groups:0)" ]] &&
    if [[ $1 == development ]]; then [[ "$(entry "$signed" get-task-allow)" == true ]]
    else ! entry "$signed" get-task-allow; fi
}

# display_name kind flavour name: the appex's CFBundleDisplayName is name
display_name() { [[ "$(entry "$(appex "$1" "$2")/Info.plist" CFBundleDisplayName)" == "$3" ]]; }

# profile_identity profile: the SHA-1 of the first valid codesigning identity whose certificate the profile carries, as
# security find-identity -v -p codesigning prints it
profile_identity() {
  local plist="$SUITE_OUT/identity-profile.plist" identities count i hash
  security cms -D -i "$1" -o "$plist" && identities=$(security find-identity -v -p codesigning | grep -v CSSMERR_) &&
    count=$(plutil -extract DeveloperCertificates raw "$plist") || return
  for ((i = 0; i < count; i++)); do
    hash=$(plutil -extract "DeveloperCertificates.$i" raw "$plist" | base64 -D | shasum -a1 | cut -c1-40 | tr a-f A-F)
    if grep -qF " $hash " <<<"$identities"; then echo "$hash"; return; fi
  done
  return 1
}

# signed_by kind flavour sha1: the appex's signing certificate has that SHA-1
signed_by() {
  local prefix="$SUITE_OUT/$1-$2/cert"
  codesign -d --extract-certificates="$prefix" "$(appex "$1" "$2")" &&
    [[ "$(shasum -a1 "${prefix}0" | cut -c1-40 | tr a-f A-F)" == "$3" ]]
}

# malformed_identity profile: a non-SHA-1 --identity exits 2 on the identity check and leaves the project and work dirs
# as they were
malformed_identity() {
  local dir="$SUITE_OUT/malformed-identity" stderr="$SUITE_OUT/malformed-identity.stderr" before code=0
  mkdir -p "$dir/project" && touch "$dir/project/build.settings" && before=$(find "$dir" | sort) || return
  "$TOOL" --hosting apple --app-id com.example.app --app-group group.com.example.app --profile "$1" --version 1.0.0 \
    --build 1 --project "$dir/project" --work "$dir/work" --identity not-a-sha1 2>"$stderr" || code=$?
  cat "$stderr" && echo "exit $code" && [[ $code == 2 ]] && grep -q 'is not a certificate SHA-1' "$stderr" &&
    diff <(printf '%s' "$before") <(printf '%s' "$(find "$dir" | sort)")
}

# flavour kind flavour: only the apple flavour links StoreKit
flavour() {
  local appex_dir links="$SUITE_OUT/$1-$2/otool.txt"
  appex_dir=$(appex "$1" "$2") && otool -L "$appex_dir/$(basename "$appex_dir" .appex)" >"$links" &&
    cat "$links" || return
  if [[ $2 == apple ]]; then grep -q StoreKit.framework "$links"; else ! grep -q StoreKit.framework "$links"; fi
}

BEFORE=$(checkout_state)
for kind in development app-store; do
  if [[ $kind == development ]]; then profile=${BA_EXT_DEV_PROFILE:-}; else profile=${BA_EXT_STORE_PROFILE:-}; fi
  for hosting in apple self; do
    run_test "$kind $hosting built, stale appex replaced" build "$kind" "$hosting" "$profile"
    run_test "$kind $hosting codesign verify --deep --strict" verifies "$kind" "$hosting"
    run_test "$kind $hosting entitlements" entitlements "$kind" "$hosting"
    run_test "$kind $hosting flavour links StoreKit only for apple" flavour "$kind" "$hosting"
  done
done
DISPLAY_NAME="BA Suite Downloader"
run_test "display name: built with --display-name" build display-name apple "${BA_EXT_DEV_PROFILE:-}" \
  --display-name "$DISPLAY_NAME"
run_test "display name: appex CFBundleDisplayName is the --display-name" display_name display-name apple "$DISPLAY_NAME"
IDENTITY=$(profile_identity "${BA_EXT_DEV_PROFILE:-}" 2>/dev/null) || IDENTITY=""
run_test "identity: built with the SHA-1 of the Development profile's identity" build identity apple \
  "${BA_EXT_DEV_PROFILE:-}" --identity "$IDENTITY"
run_test "identity: codesign verify --deep --strict" verifies identity apple
run_test "identity: signed by that identity" signed_by identity apple "$IDENTITY"
run_test "malformed identity exits 2 and writes nothing" malformed_identity "${BA_EXT_DEV_PROFILE:-}"
run_test "checkout unchanged" diff <(printf '%s' "$BEFORE") <(printf '%s' "$(checkout_state)")
