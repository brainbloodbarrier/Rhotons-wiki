# tests/bats/test_helper.bash — shared harness for the lib/*.sh bats suite.
#
# Every test runs the scripts inside a hermetic sandbox repo built in
# $BATS_TEST_TMPDIR. This is required by design: guard/verify derive
# REPO_ROOT from their own script location, while resolve-wiki.sh walks up
# from $PWD looking for .config/wikis.json. Copying lib/ into the sandbox
# and cd-ing into it satisfies both, and side effects (.autoresearch/<wiki>
# creation) land in the tmpdir, never in the real repo.

# $stderr/$status/$output are assigned by bats' `run`, not by this file.
# shellcheck disable=SC2154

# run --separate-stderr needs bats >= 1.5.
bats_require_minimum_version 1.5.0

TESTS_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURES="$TESTS_REPO_ROOT/tests/fixtures"

# make_sandbox [fixture-vault] [wiki-name]
#   Builds $BATS_TEST_TMPDIR/repo with a copy of lib/, a .config/wikis.json
#   registering <wiki-name> (default: testwiki) at <wiki-name>-wiki/vault,
#   and optionally the given fixture vault copied in. Leaves PWD inside the
#   sandbox. Sets $SANDBOX and $WIKI.
make_sandbox() {
  local fixture="${1:-}"
  WIKI="${2:-testwiki}"
  SANDBOX="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$SANDBOX/.config" "$SANDBOX/$WIKI-wiki/vault"
  cp -R "$TESTS_REPO_ROOT/lib" "$SANDBOX/lib"
  if [[ -n "$fixture" ]]; then
    cp -R "$FIXTURES/$fixture/." "$SANDBOX/$WIKI-wiki/vault/"
  fi
  jq -n --arg w "$WIKI" --arg v "$WIKI-wiki/vault" \
    '{wikis: {($w): {vault: $v, domain: "test"}}, output_dir: ".autoresearch"}' \
    > "$SANDBOX/.config/wikis.json"
  cd "$SANDBOX" || return 1
}

# add_wiki <name> [fixture-vault]
#   Registers a second wiki in the sandbox registry (for allowlist-leak and
#   cross-wiki tests) and creates its vault, optionally from a fixture.
add_wiki() {
  local name="$1" fixture="${2:-}"
  mkdir -p "$SANDBOX/$name-wiki/vault"
  if [[ -n "$fixture" ]]; then
    cp -R "$FIXTURES/$fixture/." "$SANDBOX/$name-wiki/vault/"
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg w "$name" --arg v "$name-wiki/vault" \
    '.wikis[$w] = {vault: $v, domain: "test"}' \
    "$SANDBOX/.config/wikis.json" > "$tmp"
  mv "$tmp" "$SANDBOX/.config/wikis.json"
}

# make_page <vault-relative-path>   (content on stdin)
make_page() {
  local p="$SANDBOX/$WIKI-wiki/vault/$1"
  mkdir -p "$(dirname "$p")"
  cat > "$p"
}

# A page with full valid frontmatter (passes every guard check when its tag
# is in the taxonomy and something links to it). Body passed as $2.
make_valid_page() {
  local rel="$1" body="${2:-Plain body text.}"
  local title
  title=$(basename "$rel" .md)
  make_page "$rel" <<EOF
---
title: $title
category: anatomy
tags: [anatomy]
summary: Generated test page.
sources: ["Test source with digits 2026, pp. 1-2"]
created: 2026-01-01
updated: 2026-01-01
parent: somewhere
---

$body
EOF
}

run_guard()  { run --separate-stderr "$SANDBOX/lib/autoresearch-guard.sh" "$@"; }
run_verify() { run --separate-stderr "$SANDBOX/lib/autoresearch-verify.sh" "$@"; }

# assert_stderr_line <substring> — fail with a readable message when the
# guard's stderr does not contain the expected violation line.
assert_stderr_line() {
  local want="$1"
  if [[ "$stderr" != *"$want"* ]]; then
    echo "expected stderr to contain: $want" >&2
    echo "actual stderr:" >&2
    printf '%s\n' "$stderr" >&2
    return 1
  fi
}

refute_stderr_line() {
  local unwanted="$1"
  if [[ "$stderr" == *"$unwanted"* ]]; then
    echo "expected stderr NOT to contain: $unwanted" >&2
    echo "actual stderr:" >&2
    printf '%s\n' "$stderr" >&2
    return 1
  fi
}

assert_status() {
  local want="$1"
  if [[ "$status" -ne "$want" ]]; then
    echo "expected exit status $want, got $status" >&2
    echo "stdout: $output" >&2
    echo "stderr: ${stderr:-}" >&2
    return 1
  fi
}
