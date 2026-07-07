#!/usr/bin/env bats
# lib/guard-bootstrap-allowlist.sh — initializes .config/guard-allowlist.json
# from current violations. The critical property is the ROUND-TRIP: after
# bootstrapping, the plain guard must exit 0 on the same vault, because
# campaigns start from a bootstrapped HEAD and shrink the list over time.

load test_helper

# vault-broken minus its one non-allowlistable violation (missing-title.md:
# field-level MISSING_* errors have no allowlist kind, so a vault containing
# one can never round-trip to green). Removing the page turns hub.md's
# [[missing-title]] link into a second broken wikilink — also allowlistable.
allowlistable_vault() {
  make_sandbox vault-broken
  rm "$SANDBOX/testwiki-wiki/vault/missing-title.md"
}

@test "round-trip: bootstrap makes the plain guard pass on the same HEAD" {
  allowlistable_vault
  run_guard testwiki
  assert_status 1

  run --separate-stderr "$SANDBOX/lib/guard-bootstrap-allowlist.sh" testwiki
  assert_status 0
  assert_stderr_line "allowlist bootstrap: OK"

  run_guard testwiki
  assert_status 0
}

@test "bootstrap fails (exit 1) when a non-allowlistable error remains" {
  make_sandbox vault-broken   # contains missing-title.md
  run --separate-stderr "$SANDBOX/lib/guard-bootstrap-allowlist.sh" testwiki
  assert_status 1
  assert_stderr_line "allowlist bootstrap: FAILED"
}

@test "captured entries use the guard's exact violation strings" {
  allowlistable_vault
  "$SANDBOX/lib/guard-bootstrap-allowlist.sh" testwiki 2>/dev/null
  local al="$SANDBOX/.config/guard-allowlist.json"
  jq -e '.testwiki.broken_wikilinks | index("dangler.md -> [[does-not-exist]]")' "$al" > /dev/null
  jq -e '.testwiki.missing_frontmatter | index("no-frontmatter.md")' "$al" > /dev/null
  jq -e '.testwiki.orphans | index("orphan.md")' "$al" > /dev/null
  jq -e '.testwiki.taxonomy_violations | index("bad-tag.md -> nonexistent-tag")' "$al" > /dev/null
}

@test "--merge preserves entries for other wikis" {
  allowlistable_vault
  jq -n '{legacywiki: {orphans: ["keep-me.md"]}}' > "$SANDBOX/.config/guard-allowlist.json"
  "$SANDBOX/lib/guard-bootstrap-allowlist.sh" --merge testwiki 2>/dev/null
  local al="$SANDBOX/.config/guard-allowlist.json"
  jq -e '.legacywiki.orphans | index("keep-me.md")' "$al" > /dev/null
  jq -e '.testwiki.broken_wikilinks | index("dangler.md -> [[does-not-exist]]")' "$al" > /dev/null
}

@test "without --merge, bootstrap starts from a fresh allowlist" {
  allowlistable_vault
  jq -n '{legacywiki: {orphans: ["keep-me.md"]}}' > "$SANDBOX/.config/guard-allowlist.json"
  "$SANDBOX/lib/guard-bootstrap-allowlist.sh" testwiki 2>/dev/null
  jq -e 'has("legacywiki") | not' "$SANDBOX/.config/guard-allowlist.json" > /dev/null
}

@test "--quality captures quality-tier warnings and passes guard --quality" {
  allowlistable_vault
  run --separate-stderr "$SANDBOX/lib/guard-bootstrap-allowlist.sh" --quality testwiki
  assert_status 0
  jq -e '.testwiki.vague_sources | index("vague-source.md")' \
    "$SANDBOX/.config/guard-allowlist.json" > /dev/null
  run_guard testwiki --quality --strict
  assert_status 0
}

@test "unknown flag exits 64" {
  allowlistable_vault
  run --separate-stderr "$SANDBOX/lib/guard-bootstrap-allowlist.sh" --frobnicate
  assert_status 64
}

@test "clean vault bootstraps to an all-empty allowlist and still passes" {
  make_sandbox vault-clean
  run --separate-stderr "$SANDBOX/lib/guard-bootstrap-allowlist.sh" testwiki
  assert_status 0
  jq -e '.testwiki | [.orphans, .broken_wikilinks, .taxonomy_violations, .missing_frontmatter] | all(length == 0)' \
    "$SANDBOX/.config/guard-allowlist.json" > /dev/null
}
