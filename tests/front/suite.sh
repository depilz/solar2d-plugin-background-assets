#!/bin/bash
# front: the Lua front (lua/) under Solar2D's Lua 5.1, against a fake backend that reports any iOS version, and loaded
# by require over the smallest backend. One row per case in cases.lua.
set -euo pipefail
W="$(cd "$(dirname "$0")" && pwd)"
source "$W/../lib.sh"

ids=$(lua51 "$W/cases.lua" "$BA_REPO" --list)
while IFS= read -r id; do
  run_test "$id" lua51 "$W/cases.lua" "$BA_REPO" "$id"
done <<<"$ids"
