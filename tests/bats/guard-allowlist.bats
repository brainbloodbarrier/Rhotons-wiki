#!/usr/bin/env bats
# lib/autoresearch-guard.sh — allowlist suppression. The allowlist is what
# lets campaigns pass the guard on HEAD despite historical debt; a bug here
# either masks real violations or bricks the loop.

load test_helper

@test "allowlisted broken wikilink flips exit 1 to 0" {
  make_sandbox vault-clean
  make_valid_page "dangler.md" "Broken [[nope]] link, plus [[artery-one]]."
  run_guard testwiki
  assert_status 1

  jq -n '{testwiki: {broken_wikilinks: ["dangler.md -> [[nope]]"], orphans: ["dangler.md"]}}' \
    > "$SANDBOX/.config/guard-allowlist.json"
  run_guard testwiki
  assert_status 0
  refute_stderr_line "BROKEN_WIKILINK"
}

@test "fixture allowlist suppresses each kind; non-allowlistable errors remain" {
  make_sandbox vault-broken
  cp "$FIXTURES/allowlist.json" "$SANDBOX/.config/guard-allowlist.json"
  run_guard testwiki --format=json
  # missing-title.md is NOT allowlistable (field-level errors have no
  # allowlist kind) so the guard still hard-fails...
  assert_status 1
  assert_stderr_line "ERROR MISSING_title: missing-title.md"
  # ...but every allowlisted violation is gone from counts and stderr.
  [ "$(jq -r '.checks.frontmatter_errors' <<< "$output")" = "1" ]
  [ "$(jq -r '.checks.broken_wikilinks'  <<< "$output")" = "0" ]
  [ "$(jq -r '.checks.orphan_pages'      <<< "$output")" = "0" ]
  [ "$(jq -r '.checks.taxonomy_violations' <<< "$output")" = "0" ]
  refute_stderr_line "MISSING_FRONTMATTER: no-frontmatter.md"
  refute_stderr_line "BROKEN_WIKILINK"
  refute_stderr_line "ORPHAN"
  refute_stderr_line "UNKNOWN_TAG"
}

@test "--no-allowlist restores raw counts" {
  make_sandbox vault-broken
  cp "$FIXTURES/allowlist.json" "$SANDBOX/.config/guard-allowlist.json"
  run_guard testwiki --no-allowlist --format=json
  assert_status 1
  [ "$(jq -r '.checks.frontmatter_errors' <<< "$output")" = "2" ]
  [ "$(jq -r '.checks.broken_wikilinks'  <<< "$output")" = "1" ]
  [ "$(jq -r '.checks.orphan_pages'      <<< "$output")" = "1" ]
  [ "$(jq -r '.checks.taxonomy_violations' <<< "$output")" = "1" ]
}

@test "--allowlist <path> overrides the default location" {
  make_sandbox vault-broken
  cp "$FIXTURES/allowlist.json" "$SANDBOX/custom-allowlist.json"
  run_guard testwiki --allowlist "$SANDBOX/custom-allowlist.json" --format=json
  assert_status 1
  [ "$(jq -r '.checks.broken_wikilinks' <<< "$output")" = "0" ]
}

@test "malformed allowlist degrades to raw counts with a parse note, no crash" {
  make_sandbox vault-broken
  echo "this is not json" > "$SANDBOX/.config/guard-allowlist.json"
  run_guard testwiki --format=json
  # A crash here (under set -e) would kill the autoresearch loop.
  assert_status 1
  assert_stderr_line "allowlist parse error"
  [ "$(jq -r '.checks.broken_wikilinks' <<< "$output")" = "1" ]
}

@test "allowlist entries for wiki A do not suppress violations in wiki B" {
  make_sandbox "" testwiki
  add_wiki other vault-broken
  # Allowlist keyed under testwiki, but we lint wiki "other".
  cp "$FIXTURES/allowlist.json" "$SANDBOX/.config/guard-allowlist.json"
  run --separate-stderr "$SANDBOX/lib/autoresearch-guard.sh" other --format=json
  [ "$status" -eq 1 ]
  [ "$(jq -r '.checks.broken_wikilinks' <<< "$output")" = "1" ]
}
