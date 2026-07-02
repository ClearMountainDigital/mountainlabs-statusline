#!/usr/bin/env bash
# ============================================================================
# MountainLabs statusline — lint  (issue #0002)
#
# Runs shellcheck over every shell script in the repo. Run it locally before a
# commit; CI (#0003) runs the same command.
#
#   tests/lint.sh
# ============================================================================
set -u

SELF="${BASH_SOURCE[0]:-$0}"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint: shellcheck not found — install it (brew install shellcheck)" >&2
  exit 127
fi

shellcheck \
  "$ROOT/statusline.sh" \
  "$ROOT/install.sh" \
  "$ROOT/tests/run.sh" \
  "$ROOT/tests/lint.sh"
