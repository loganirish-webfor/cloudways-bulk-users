#!/usr/bin/env bash
# Run the sandbox suite in Docker. Usage: tests/run.sh [name-fragment]
# e.g. tests/run.sh add   -> only tests/t_*add*.sh
set -eu
cd "$(dirname "$0")/.."
trap 'docker compose -f tests/docker/compose.yml down >/dev/null 2>&1 || true' EXIT
docker compose -f tests/docker/compose.yml run --rm --build runner bash tests/suite.sh "$@"
