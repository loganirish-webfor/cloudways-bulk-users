#!/usr/bin/env bash
# Generates docs/example-report.md from the Docker sandbox. Markdown goes to
# stdout; fixture-build noise goes to stderr. Run it from the project root with:
#   docker compose -f tests/docker/compose.yml build --quiet runner
#   docker compose -f tests/docker/compose.yml run --rm -T runner \
#     bash tests/example_report.sh > docs/example-report.md 2>/dev/null
#   docker compose -f tests/docker/compose.yml down
# Build the image in its own step: with `run --build`, Docker's build log goes to
# stdout and ends up inside the report.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/tests/lib/fixtures.sh"
fixtures_build
fixtures_reset

block() { # title, then run the tool and print its output in a fence
  local title="$1"; shift
  run_tool "$@"
  # Drop the "[n/N] folder" progress lines (they go to stderr in real use).
  printf '### %s\n\n```text\n%s\n```\n\n' "$title" "$(printf '%s\n' "$OUT" | grep -v -E '^\[[0-9]+/[0-9]+\] ')"
}

echo "# Example output"
echo
echo "Generated from the Docker sandbox by \`tests/example_report.sh\`. Site names are"
echo "fixtures (\`app_a\`, \`https://app_a.test\`, and so on), the server label is \`testsrv\`, and the"
echo "log paths are sandbox paths. The \`[n/N] folder\` progress lines the tool prints to"
echo "stderr are left out. Each block is one run of the tool; blocks 2 to 6 follow on from"
echo "each other, starting from the same fresh fixtures as block 1."
echo
block "1. Add: dry run on every application" "${ADD[@]}" --all
block "2. Add: create on two sites" "${ADD[@]}" --sites app_a,app_b --execute
block "3. Add again: duplicate protection" "${ADD[@]}" --sites app_a,app_b --execute
block "4. Disable: dry run" "${DIS[@]}" --all
block "5. Disable: live on the two sites" "${DIS[@]}" --sites app_a,app_b --execute
block "6. Restore: live" "${RST[@]}" --sites app_a,app_b --execute
