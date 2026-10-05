#!/bin/bash
# Runs the test suites, then verdicts their rows against tests/xfail/default.tsv and tests/manifest/default.tsv.
# usage: tests/run.sh [--list | --help | suite...]
# With no suite named, runs every tests/<suite>/suite.sh that has no "# run.sh: named-only" line.
# Output goes to $BA_TEST_OUT (default: a new mktemp dir), which must be outside the repo and ~/Library.
# Exits 0 when every row passes, 1 on a failed verdict, 2 on a usage or setup error.
set -euo pipefail

TESTS_DIR=$(cd -P "$(dirname "$0")" && pwd)
BA_REPO=$(dirname "$TESTS_DIR")
LINE=default
XFAIL="$TESTS_DIR/xfail/$LINE.tsv"
MANIFEST="$TESTS_DIR/manifest/$LINE.tsv"

die() { echo "run.sh: $*" >&2; exit 2; }
usage() { sed -n '3,6s/^# //p' "$0"; }

suites() {
  local s
  for s in "$TESTS_DIR"/*/suite.sh; do
    if [[ -f $s ]]; then basename "$(dirname "$s")"; fi
  done
}

default_suites() {
  local s
  for s in $(suites); do
    grep -qx '# run.sh: named-only' "$TESTS_DIR/$s/suite.sh" || echo "$s"
  done
}

# physical_path path: the path with symlinks resolved, also when its tail does not exist yet
physical_path() {
  local dir=$1 rest="" base
  [[ $dir == /* ]] || dir="$PWD/$dir"
  until [[ -d $dir ]]; do
    rest="/$(basename "$dir")$rest"
    dir=$(dirname "$dir")
  done
  [[ "$rest/" != */../* && "$rest/" != */./* ]] || die "$1: '.' or '..' in a part that does not exist yet"
  base=$(cd -P "$dir" && pwd)
  echo "${base%/}$rest"
}

under() { [[ $1 == "$2" || $1 == "$2"/* ]]; }

resolve_test_out() {
  local out library
  if [[ -z ${BA_TEST_OUT:-} ]]; then
    BA_TEST_OUT=$(mktemp -d "${TMPDIR:-/tmp}/ba-tests.XXXXXX") || die "cannot create an output dir"
  fi
  out=$(physical_path "$BA_TEST_OUT")
  library=$(physical_path "$HOME/Library")
  if under "$out" "$BA_REPO"; then die "BA_TEST_OUT $out is inside the repo; choose a directory outside it"; fi
  if under "$out" "$library"; then die "BA_TEST_OUT $out is under ~/Library; choose a directory outside it"; fi
  mkdir -p "$out/tmp" || die "cannot create $out/tmp"
  export BA_REPO BA_TEST_OUT=$out TMPDIR=$out/tmp
}

# verdict [ran results]: validates the xfail and manifest lists (exit 2 when bad); given the suites that ran and their
# rows, prints one verdict per row and per unreported id, and exits 1 when any verdict fails
verdict() {
  awk -F'\t' -v registered="$(suites | tr '\n' ' ')" -v ran="${1:-}" -v line="$LINE" '
    BEGIN {
      split(registered, names, " "); for (i in names) isreg[names[i]] = 1
      split(ran, names, " "); for (i in names) didrun[names[i]] = 1
    }
    FILENAME != ARGV[3] && (/^#/ || /^[ \t]*$/) { next }
    FILENAME == ARGV[1] && $0 == "suite\ttest\tkey\tkind\tnote" { next }
    FILENAME == ARGV[2] && $0 == "suite\ttest" { next }
    FILENAME == ARGV[1] {
      id = $1 "\t" $2
      if (NF < 4 || $2 == "" || $3 == "" || ($4 != "defect" && $4 != "pending-api") || !($1 in isreg) || (id in xfail))
        bad = bad "\n  " FILENAME ":" FNR ": " $0
      xfail[id] = 1
      next
    }
    FILENAME == ARGV[2] {
      id = $1 "\t" $2
      if (NF != 2 || $2 == "" || !($1 in isreg) || (id in listed))
        bad = bad "\n  " FILENAME ":" FNR ": " $0
      listed[id] = 1; order[++n] = id
      next
    }
    $3 == "_harness" { print "FAIL " $1 ": " $3; failed++; next }
    {
      id = $1 "\t" $3; rows[$1]++; reported[id] = 1
      if (!(id in listed)) word = "UNLISTED"
      else if ($2 == "PASS") word = (id in xfail) ? "XPASS" : "PASS"
      else if ($2 == "FAIL" && (id in xfail)) word = "XFAIL"
      else word = "FAIL"
      if (word == "PASS") passed++; else if (word == "XFAIL") xfailed++; else failed++
      print word " " $1 ": " $3
    }
    END {
      for (id in xfail) if (!(id in listed)) bad = bad "\n  xfail id not in the manifest: " id
      if (bad != "") { print "run.sh: bad xfail or manifest list:" bad > "/dev/stderr"; exit 2 }
      if (ARGC < 4) exit 0
      for (i = 1; i <= n; i++) {
        split(order[i], p, "\t")
        if (!(p[1] in didrun) || (order[i] in reported)) continue
        print ((order[i] in xfail) ? "STALE " : "MISSING ") p[1] ": " p[2]; failed++
      }
      for (s in didrun) if (!rows[s]) { print "EMPTY " s; failed++ }
      print line ": " passed + 0 " passed, " xfailed + 0 " xfail, " failed + 0 " failed"
      exit (failed > 0)
    }
  ' "$XFAIL" "$MANIFEST" ${2:+"$2"}
}

run_suite() {
  local suite=$1 out="$BA_TEST_OUT/$1"
  rm -rf "$out"
  mkdir -p "$out/logs"
  echo "== $suite ($out)"
  if ! BA_SUITE=$suite SUITE_OUT=$out SUITE_RESULTS=$out/results.tsv \
      /bin/bash "$TESTS_DIR/$suite/suite.sh" >"$out/suite.log" 2>&1 </dev/null || [[ ! -s $out/results.tsv ]]; then
    printf '%s\tFAIL\t_harness\n' "$suite" >>"$out/results.tsv"
  fi
}

main() {
  case "${1:-}" in
    --list) suites; return ;;
    -h | --help) usage; return ;;
    -*) usage >&2; exit 2 ;;
  esac
  local registered s selected
  registered=$(suites)
  for s in "$@"; do
    grep -qx -- "$s" <<<"$registered" || die "unknown suite '$s' (tests/run.sh --list names them)"
  done
  if (($#)); then selected=("$@"); else selected=($(default_suites)); fi
  ((${#selected[@]})) || die "no suite to run"
  [[ -f $XFAIL ]] || die "missing $XFAIL"
  [[ -f $MANIFEST ]] || die "missing $MANIFEST"
  verdict
  resolve_test_out
  : >"$BA_TEST_OUT/results.tsv"
  for s in "${selected[@]}"; do
    run_suite "$s"
    cat "$BA_TEST_OUT/$s/results.tsv" >>"$BA_TEST_OUT/results.tsv"
  done
  verdict "${selected[*]}" "$BA_TEST_OUT/results.tsv"
}

main "$@"
