# Sourced by tests/<suite>/suite.sh. tests/run.sh runs every selected tests/<suite>/suite.sh with /bin/bash (a line
# "# run.sh: named-only" keeps a suite out of the default run) and exports BA_REPO (the repo root), BA_TEST_OUT, TMPDIR
# (inside BA_TEST_OUT) and, per suite, BA_SUITE, SUITE_OUT (a fresh dir for its files, logs in SUITE_OUT/logs) and
# SUITE_RESULTS. A suite records one row per test id (no tabs) with record or run_test and exits 0 once it has run; a
# non-zero exit or no rows fails it as test _harness. Every id a suite records is listed in tests/manifest/default.tsv,
# and its expected failures in tests/xfail/default.tsv.

# record PASS|FAIL id
record() { printf '%s\t%s\t%s\n' "$BA_SUITE" "$1" "$2" >>"$SUITE_RESULTS"; }

# run_test id command...: PASS when the command exits 0, with its output in SUITE_OUT/logs/<id>.log. A shell function
# run here runs without errexit, so it chains its steps with &&.
run_test() {
  local id=$1 log
  shift
  log="$SUITE_OUT/logs/$(printf '%s' "$id" | tr '/ ' '__').log"
  if "$@" >"$log" 2>&1; then record PASS "$id"; else record FAIL "$id"; fi
}

LUA51=${LUA51:-${CORONA:-/Applications/Corona-3733}/Native/Corona/mac/bin/lua}

# lua51 args...: runs $LUA51, failing unless it is a Lua 5.1 interpreter (Solar2D's Lua)
lua51() {
  "$LUA51" -v 2>&1 | grep '^Lua 5\.1' >/dev/null || { echo "lib.sh: $LUA51 is not a Lua 5.1 interpreter" >&2; return 1; }
  "$LUA51" "$@"
}
