#!/usr/bin/env bats
# lib/crossmap-generate.sh — regenerates pages_index in crossmap.json.
# The guard's cross-wiki resolution and crosswiki-migrate.sh both consume
# this output, so key normalization and structure are contracts.

load test_helper

crossmap_setup() {
  make_sandbox "" testwiki
  add_wiki other
  make_valid_page "anatomy/Alpha Page.md" "Links [[beta-page]]."
  make_valid_page "anatomy/beta-page.md"  "Links [[alpha page]]."
  make_page "index.md" <<< "index words, excluded from the pages index"
  make_page "log.md"   <<< "log words, excluded from the pages index"
  WIKI=other make_valid_page "gamma.md" "Remote page."
  WIKI=other make_valid_page "beta-page.md" "Same basename as testwiki's."
}

@test "--dry-run prints valid JSON to stdout and writes nothing" {
  crossmap_setup
  run --separate-stderr "$SANDBOX/lib/crossmap-generate.sh" --dry-run
  assert_status 0
  jq empty <<< "$output"
  [ ! -f "$SANDBOX/crossmap.json" ]
}

@test "writes crossmap.json with version 1.1 and normalized basename keys" {
  crossmap_setup
  run --separate-stderr "$SANDBOX/lib/crossmap-generate.sh"
  assert_status 0
  [ -f "$SANDBOX/crossmap.json" ]
  [ "$(jq -r '.version' "$SANDBOX/crossmap.json")" = "1.1" ]
  # "Alpha Page.md" is indexed under its normalized key.
  jq -e '.pages_index["alpha-page"]' "$SANDBOX/crossmap.json" > /dev/null
  jq -e '.pages_index | has("Alpha Page") | not' "$SANDBOX/crossmap.json" > /dev/null
}

@test "same basename across wikis produces a two-entry list" {
  crossmap_setup
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
  [ "$(jq '.pages_index["beta-page"] | length' "$SANDBOX/crossmap.json")" = "2" ]
  jq -e '[.pages_index["beta-page"][].wiki] | sort == ["other","testwiki"]' \
    "$SANDBOX/crossmap.json" > /dev/null
}

@test "entries carry the vault-relative path" {
  crossmap_setup
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
  [ "$(jq -r '.pages_index["alpha-page"][0].path' "$SANDBOX/crossmap.json")" = "anatomy/Alpha Page.md" ]
}

@test "index.md and log.md are excluded from the pages index" {
  crossmap_setup
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
  jq -e '.pages_index | has("index") | not' "$SANDBOX/crossmap.json" > /dev/null
  jq -e '.pages_index | has("log")   | not' "$SANDBOX/crossmap.json" > /dev/null
}

@test "preserves an existing bridges array" {
  crossmap_setup
  jq -n '{version: "1.0", bridges: [{from: "a", to: "b", relation: "related"}], pages_index: {}}' \
    > "$SANDBOX/crossmap.json"
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
  [ "$(jq '.bridges | length' "$SANDBOX/crossmap.json")" = "1" ]
  [ "$(jq -r '.bridges[0].from' "$SANDBOX/crossmap.json")" = "a" ]
}

@test "idempotent: second run identical modulo generated_at" {
  crossmap_setup
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
  jq 'del(.generated_at)' "$SANDBOX/crossmap.json" > "$BATS_TEST_TMPDIR/first.json"
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
  jq 'del(.generated_at)' "$SANDBOX/crossmap.json" > "$BATS_TEST_TMPDIR/second.json"
  diff "$BATS_TEST_TMPDIR/first.json" "$BATS_TEST_TMPDIR/second.json"
}

@test "unknown argument exits 64" {
  crossmap_setup
  run --separate-stderr "$SANDBOX/lib/crossmap-generate.sh" --bogus
  assert_status 64
}

@test "missing registry exits 66" {
  crossmap_setup
  rm "$SANDBOX/.config/wikis.json"
  run --separate-stderr "$SANDBOX/lib/crossmap-generate.sh" --dry-run
  assert_status 66
}
