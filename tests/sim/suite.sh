#!/bin/bash
# run.sh: named-only
# sim: runs the Corona/ demo in an isolated copy of the Solar2D Simulator and checks that it requires
# plugin.backgroundAssets from SIM_HOME/Solar2DPlugins and runs its whole flow over the plugin's folder emulator, with
# the demo packs staged where the demo's packsDirectory points (../tools/demo/packs from the copied project). Then it
# runs the emulator's Simulator test project (tests/sim/emulator/) the same way and records one row per case it prints.
# The copy ($SOLAR2D_SIM_APP, default Solar2D 3733's, in SUITE_OUT/app) has its own bundle id and is re-signed ad hoc;
# it runs with HOME and CFFIXED_USER_HOME at SUITE_OUT/home and an empty plugins dir SUITE_OUT/plugins, so the
# Simulator itself fetches the mac-sim archive from SUITE_OUT/home/Solar2DPlugins. That dir is a symlink to
# $BA_SIM_SOLAR2D_PLUGINS when set (an existing Solar2DPlugins dir, e.g. one funbox's install filled), else it holds a
# copy of the repo's plugin/com.studycat/plugin.backgroundAssets/. Nothing is written to the user's Simulator plugins
# dir or ~/Solar2DPlugins (the copy's own preferences may land under ~/Library), and the suite fails if either changes
# while it runs.
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
SOLAR2D_SIM_APP=${SOLAR2D_SIM_APP:-/Applications/Corona-3733/Corona Simulator.app}
BUNDLE_ID=com.coronalabs.Corona_Simulator.bgassetstests
APP="$SUITE_OUT/app/Corona Simulator.app"
SIM_HOME=$SUITE_OUT/home
SOURCE_ARCHIVE=$SIM_HOME/Solar2DPlugins/com.studycat/plugin.backgroundAssets/mac-sim/data.tgz
PLUGINS=$SUITE_OUT/plugins
PROJECT=$SUITE_OUT/project
DEMO_PACKS=$SUITE_OUT/tools/demo/packs
LOG=$SUITE_OUT/logs/sim.stdout.log
DONE_LINE="[demo] done"
EMULATOR_PROJECT=$SUITE_OUT/emulator-project
EMULATOR_LOG=$SUITE_OUT/logs/sim-emulator.stdout.log
EMULATOR_DONE_LINE="[emulator] done"
TIMEOUT_S=120

# the real user's dirs, from the directory service: $HOME may point anywhere
USER_HOME=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | sed -n 's/^NFSHomeDirectory: //p')
[[ -d $USER_HOME ]] || { echo "sim: no home dir for $(id -un) in the directory service" >&2; exit 1; }
USER_PLUGINS="$USER_HOME/Library/Application Support/Corona/Simulator/Plugins"
USER_SOLAR2D="$USER_HOME/Solar2DPlugins/com.studycat"

# stat_entries path...: path, size and mtime of each path and of everything beneath it
stat_entries() { find "$@" -exec stat -f '%N %z %m' {} + 2>&1 || true; }

# user_dirs: the state the run must not change, i.e. the user's plugin.backgroundAssets entries in the Simulator
# plugins dir, its catalog.json size and mtime, and the ~/Solar2DPlugins/com.studycat/ listing
user_dirs() {
  local entries=()
  if [[ -d $USER_PLUGINS ]]; then
    while IFS= read -r -d '' e; do entries+=("$e"); done < <(find "$USER_PLUGINS" -mindepth 1 -maxdepth 1 \
      \( -name 'plugin_backgroundAssets*' -o -name 'plugin.backgroundAssets*' \) -print0)
  fi
  if ((${#entries[@]})); then stat_entries "${entries[@]}"; fi
  stat -f 'catalog %z %m' "$USER_PLUGINS/catalog.json" 2>&1 || true
  stat_entries "$USER_SOLAR2D" -maxdepth 1
}

make_app() {
  mkdir -p "$SUITE_OUT/app" &&
    ditto "$SOLAR2D_SIM_APP" "$APP" &&
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist" &&
    codesign -d --entitlements - --xml "$SOLAR2D_SIM_APP" >"$SUITE_OUT/app/entitlements.plist" &&
    codesign -f -s - --entitlements "$SUITE_OUT/app/entitlements.plist" "$APP"
}

setup_home() {
  mkdir -p "$SIM_HOME" "$PLUGINS" || return
  if [[ -n ${BA_SIM_SOLAR2D_PLUGINS:-} ]]; then
    [[ -d $BA_SIM_SOLAR2D_PLUGINS ]] || { echo "sim: BA_SIM_SOLAR2D_PLUGINS $BA_SIM_SOLAR2D_PLUGINS is not a dir"; return 1; }
    ln -s "$BA_SIM_SOLAR2D_PLUGINS" "$SIM_HOME/Solar2DPlugins"
  else
    mkdir -p "$SIM_HOME/Solar2DPlugins/com.studycat" &&
      cp -R "$BA_REPO/plugin/com.studycat/plugin.backgroundAssets" "$SIM_HOME/Solar2DPlugins/com.studycat/"
  fi
}

# run_project project log done_line: launches the project, waits for its done line in its log, and stops it
run_project() {
  local project=$1 log=$2 done_line=$3 pid i=0
  : >"$log"
  HOME=$SIM_HOME CFFIXED_USER_HOME=$SIM_HOME DEBUG_BUILD_PROCESS=1 "$APP/Contents/MacOS/Corona Simulator" -no-console YES \
    -allowLuaExit YES -NSAppSleepDisabled YES -ApplePersistenceIgnoreState YES \
    -suppressUnsupportedOSWarning "$(sw_vers -productVersion)" -pluginsDirectory "$PLUGINS" \
    -project "$project/main.lua" </dev/null >"$log" 2>&1 &
  pid=$!
  until grep -qF "$done_line" "$log" || ! kill -0 "$pid" 2>/dev/null || ((i >= TIMEOUT_S * 5)); do
    sleep 0.2
    i=$((i + 1))
  done
  grep -qF "$done_line" "$log" || echo "sim: no done line in $log after $((i / 5)) s"
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

stage_projects() {
  cp -R "$BA_REPO/Corona" "$PROJECT" && mkdir -p "$(dirname "$DEMO_PACKS")" &&
    cp -R "$BA_REPO/tools/demo/packs" "$DEMO_PACKS" && cp -R "$W/emulator" "$EMULATOR_PROJECT"
}

# every_call: every call of the demo's flow logged a line, and none reported unsupported
every_call() {
  local call missing=0
  for call in getAllAssetPacks getManifest getAssetPack getStatusOfAssetPack getStatusRelativeToAssetPack \
    getLocalStatusOfAssetPack assetPackIsAvailableLocally ensureLocalAvailability pathForFile urlForPath contentsAtPath \
    fileForPath ensureLocalAvailabilityOfAssetPacks checkForUpdates getLocallyAvailableLanguages \
    reconcilePreferredLanguages getResolvedLanguage setResolvedLanguage removeAssetPack; do
    grep -qE "\[demo\] $call( [^:]*)?: " "$LOG" || { echo "no line for $call"; missing=1; }
  done
  if grep -F "error unsupported" "$LOG"; then missing=1; fi
  return $missing
}

# downloaded id local: pack id was local or not (local) before the demo's ensureLocalAvailability of it, and its
# download sent began, progress and finished, in that order, before that call's line gave the pack
downloaded() {
  local id=$1 call="ensureLocalAvailability $1"
  grep -qxF "[demo] assetPackIsAvailableLocally $id: $2" "$LOG" &&
    grep -E "^\[demo\] (download [a-z]+ $id( |$)|$call: )" "$LOG" | sed -E 's/^\[demo\] (download [a-z]+|[^:]*:).*/\1/' |
    uniq | paste -sd ' ' - | grep -xF "download began download progress download finished $call:" &&
    grep -F "[demo] $call: assetPack $id v1 " "$LOG"
}

# loaded: pathForFile's filename and base directory loaded both packs' image and sound
loaded() {
  local id file loader missing=0
  for id in demoondemand demoprefetch; do
    for file in image.png:display.newImage sound.wav:audio.loadSound; do
      loader=${file#*:} file=$id/${file%%:*}
      grep -qxF "[demo] pathForFile $file: plugin.backgroundAssets/emulator/files/Unlocalized/$file, $loader ok" "$LOG" ||
        { echo "no $loader ok for $file"; missing=1; }
    done
  done
  return $missing
}

# after_remove: the removed pack's path calls give assetPackNotAvailable with its id, fileNotFound without it
after_remove() {
  local prefix='\[demo\] pathForFile demoondemand/image\.png after remove'
  grep -E "$prefix: error assetPackNotAvailable \(plugin\.backgroundAssets 3\) pack demoondemand:" "$LOG" &&
    grep -E "$prefix, no assetPackId: error fileNotFound \(BAManagedErrorDomain 1\):" "$LOG" &&
    grep -F '[demo] assetPackIsAvailableLocally demoondemand after remove: false' "$LOG"
}

fetched() {
  cmp "$PLUGINS/plugin.backgroundAssets/data.tgz" "$SOURCE_ARCHIVE" &&
    [[ -f $PLUGINS/plugin_backgroundAssets.lua && -f $PLUGINS/plugin_backgroundAssets_backend.lua &&
      -f $PLUGINS/plugin_backgroundAssets_emulator.lua ]] &&
    python3 -c 'import json, sys; sys.exit("com.studycat/plugin.backgroundAssets" not in json.load(open(sys.argv[1])))' \
      "$PLUGINS/catalog.json"
}

# record_emulator_cases: one row "sim emulator: <case>" per ok or FAIL line of the emulator project; a case it never
# reached shows as MISSING against the manifest
record_emulator_cases() {
  local line
  [[ -f $EMULATOR_LOG ]] || return 0
  while IFS= read -r line; do
    case $line in
      "[emulator] ok "*) record PASS "sim emulator: ${line#"[emulator] ok "}" ;;
      "[emulator] FAIL "*) record FAIL "sim emulator: ${line#"[emulator] FAIL "}" ;;
    esac
  done <"$EMULATOR_LOG"
}

BEFORE=$(user_dirs)
if make_app && setup_home && stage_projects && run_project "$PROJECT" "$LOG" "$DONE_LINE" &&
  run_project "$EMULATOR_PROJECT" "$EMULATOR_LOG" "$EMULATOR_DONE_LINE"; then :; fi >"$SUITE_OUT/logs/launch.log" 2>&1

run_test "sim require ok" grep -E '\[demo\] require plugin\.backgroundAssets: ok$' "$LOG"
run_test "sim capabilities: the emulator on mac-sim" \
  grep -xF '[demo] getCapabilities: isSupported=true platform=mac-sim osVersion=nil hosting=apple' "$LOG"
run_test "sim every call logs a result, none unsupported" every_call
run_test "sim demoprefetch downloads at the first launch, with events" downloaded demoprefetch true
run_test "sim demoondemand downloads on ensureLocalAvailability, with events" downloaded demoondemand false
run_test "sim pathForFile: display.newImage and audio.loadSound load the packs' files" loaded
run_test "sim after remove: assetPackNotAvailable with the pack id, fileNotFound without" after_remove
run_test "sim flow runs to its done line, no runtime error" \
  bash -c 'grep -qE "\[demo\] done$" "$1" && ! grep -iF "runtime error" "$1"' _ "$LOG"
run_test "sim fetched from Solar2DPlugins" fetched
record_emulator_cases
run_test "sim emulator project runs every case to its done line, no runtime error" \
  bash -c 'grep -qE "^\[emulator\] done: [0-9]+ passed, 0 failed$" "$1" && ! grep -iF "runtime error" "$1"' _ "$EMULATOR_LOG"
run_test "sim user dirs unchanged" diff <(printf '%s\n' "$BEFORE") <(user_dirs)
