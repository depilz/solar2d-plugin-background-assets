#!/bin/bash
# One-time setup of a clone: points git at the tracked hooks in .githooks/ (the pre-push hook runs tests/run.sh).
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
git -C "$repo" config core.hooksPath .githooks
echo "setup.sh: core.hooksPath = $(git -C "$repo" config --get core.hooksPath)"
