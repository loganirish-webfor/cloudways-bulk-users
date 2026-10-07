#!/usr/bin/env bash
# Runs inside the sandbox container: build fixtures once, then each tests/t_*.sh.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/tests/lib/fixtures.sh"

fixtures_build
shopt -s nullglob
for t in "$ROOT"/tests/t_*"${1:-}"*.sh; do
  echo "== $(basename "$t")"
  . "$t"
done
assert_summary
