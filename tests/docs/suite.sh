#!/bin/bash
# run.sh: named-only
# docs: builds docs/ with Sphinx under -W and fails on a non-zero exit or any WARNING in the output, and checks that
# the reference pages have an entry for every public function and emulator option of lua/, every error name of the
# front and every download phase the iOS backend sends. Each function of the library has its own page,
# docs/api/<name>.rst, titled <name>().
# sphinx-build is $SPHINX_BUILD when set, else one from a venv made in SUITE_OUT from docs/requirements.txt (that
# needs python3 and network access to PyPI; there is no skip).
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"
DOCS="$BA_REPO/docs"
VENV="$SUITE_OUT/venv"
FRONT="$BA_REPO/lua/plugin_backgroundAssets.lua"
EMULATOR="$BA_REPO/lua/plugin_backgroundAssets_emulator.lua"
BACKEND="$BA_REPO/ios/Plugin/PluginBackgroundAssets.m"

# sphinx_build: prints the sphinx-build to use, making the venv when SPHINX_BUILD is unset
sphinx_build() {
  if [[ -n ${SPHINX_BUILD:-} ]]; then echo "$SPHINX_BUILD"; return; fi
  python3 -m venv "$VENV" >&2 && "$VENV/bin/pip" install -q -r "$DOCS/requirements.txt" >&2 &&
    echo "$VENV/bin/sphinx-build"
}

clean_build() {
  local sphinx out="$SUITE_OUT/build"
  sphinx=$(sphinx_build) &&
    "$sphinx" -W --keep-going -E -q -b html -d "$out/doctrees" "$DOCS" "$out/html" 2>&1 | tee "$out.log" &&
    ! grep -q WARNING "$out.log"
}

# lua_functions owner file: the public names file defines as `function <owner><name>`, e.g. owner 'lib\.'
lua_functions() { sed -n "s/^function $1\([A-Za-z][A-Za-z0-9_]*\).*/\1/p" "$2"; }

emulator_options() {
  sed -n '/^local OPTIONS = {$/,/^}$/s/^[[:space:]][[:space:]]*\([A-Za-z][A-Za-z0-9_]*\) = .*/\1/p' "$EMULATOR"
}

# error_names: the names in the front's PLUGIN_CODES and ERROR_NAMES tables
error_names() {
  sed -n -e '/^local PLUGIN_CODES = {/p' -e '/^local ERROR_NAMES = {$/,/^}$/p' "$FRONT" |
    grep -oE '[A-Za-z]+ = [0-9]+|"[A-Za-z]+"' | sed -E 's/ = [0-9]+$//; s/"//g' | sort -u
}

# download_phases: the phases the iOS backend sends, from its SendDownload( "<phase>", ... ) calls
download_phases() { sed -n 's/.*SendDownload( "\([A-Za-z]*\)".*/\1/p' "$BACKEND"; }

# options_cells: the first cells of the list-table under emulator.rst's "Options" heading, up to the next heading
options_cells() {
  awk '/^Options$/ { inside = 1 } inside && /^(-+|~+|=+)$/ && prev != "Options" { exit }
    inside && /^   \* - / { print } { prev = $0 }' "$DOCS/emulator.rst"
}

# has_terms doc prefix names...: prints each name with no term line ``<prefix><name>(...)``; no name at all fails
has_terms() {
  local doc=$1 prefix=$2 name missing=0
  shift 2
  (($# > 0)) || { echo "no names to check in ${doc##*/}"; return 1; }
  for name in "$@"; do
    grep -q "^\`\`$prefix$name(.*)\`\`\$" "$doc" ||
      { echo "missing in ${doc##*/}: \`\`$prefix$name(...)\`\`"; missing=1; }
  done
  return $missing
}

has_option_cells() {
  local cells key missing=0
  (($# > 0)) || { echo "no emulator options to check"; return 1; }
  cells=$(options_cells)
  for key in "$@"; do
    grep -qF "\`\`$key\`\`" <<<"$cells" || { echo "missing in emulator.rst Options: \`\`$key\`\`"; missing=1; }
  done
  return $missing
}

# has_pages names...: prints each name with no page api/<name>.rst whose first line is <name>(); no name at all fails
has_pages() {
  local name missing=0
  (($# > 0)) || { echo "no library functions to check"; return 1; }
  for name in "$@"; do
    [[ -f "$DOCS/api/$name.rst" && "$(head -n 1 "$DOCS/api/$name.rst")" == "$name()" ]] ||
      { echo "missing page: api/$name.rst titled $name()"; missing=1; }
  done
  return $missing
}
# has_error_rows names...: prints each name with no ``name`` cell in api/errors.rst's table; no name at all fails
has_error_rows() {
  local name missing=0
  (($# > 0)) || { echo "no error names to check"; return 1; }
  for name in "$@"; do
    grep -q "^     - \`\`$name\`\`\$" "$DOCS/api/errors.rst" ||
      { echo "missing in api/errors.rst: \`\`$name\`\`"; missing=1; }
  done
  return $missing
}

# has_phases phases...: prints each phase missing from api/events.rst's ``phase`` line; no phase at all fails
has_phases() {
  local line phase missing=0
  (($# > 0)) || { echo "no download phases to check"; return 1; }
  line=$(grep '^- ``phase``:' "$DOCS/api/events.rst") || { echo "no \`\`phase\`\` line in api/events.rst"; return 1; }
  for phase in "$@"; do
    grep -qF "\`\`\"$phase\"\`\`" <<<"$line" ||
      { echo "missing in api/events.rst phase line: \`\`\"$phase\"\`\`"; missing=1; }
  done
  return $missing
}

coverage() {
  local missing=0
  has_pages $(lua_functions 'lib\.' "$FRONT") || missing=1
  has_terms "$DOCS/api/manifest.rst" "manifest:" $(lua_functions 'Manifest:' "$FRONT") || missing=1
  has_terms "$DOCS/emulator.rst" "" $(lua_functions 'emulator\.' "$EMULATOR") || missing=1
  has_option_cells $(emulator_options) || missing=1
  has_error_rows $(error_names) || missing=1
  has_phases $(download_phases) || missing=1
  return $missing
}

run_test "docs build: exit 0, no warning" clean_build
run_test "docs coverage: every public function, emulator option, error name and download phase has a reference entry" \
  coverage
