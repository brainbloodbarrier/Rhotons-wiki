#!/usr/bin/env bash
# tests/run-bats.sh — run the bats suite against lib/*.sh.
#
# Requires bats-core >= 1.5 (for `run --separate-stderr`) plus jq and awk,
# which the scripts under test already require.
#   Ubuntu/Debian: apt-get install -y bats jq
#   macOS:         brew install bats-core jq
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v bats >/dev/null 2>&1; then
  echo "run-bats: bats not found — install bats-core (apt-get install bats / brew install bats-core)" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "run-bats: jq not found — the guard scripts and tests require it" >&2
  exit 1
fi

exec bats "${@:-tests/bats}"
