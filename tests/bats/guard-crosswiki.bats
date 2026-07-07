#!/usr/bin/env bats
# lib/autoresearch-guard.sh — cross-wiki reference validation:
# [[wiki:basename]] syntax (validated against crossmap.json pages_index)
# and markdown cross-links ../<wiki>-wiki/vault/<path>.md (validated
# against the registry and the filesystem).

load test_helper

crosswiki_setup() {
  make_sandbox "" testwiki
  add_wiki other
  make_valid_page "home.md" "Links [[peer]]."
  make_valid_page "peer.md" "Links [[home]]."
  WIKI=other make_valid_page "remote-page.md" "Remote body."
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
}

@test "valid [[wiki:basename]] is a WARN, not an error (exit 0)" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [[other:remote-page]]."
  run_guard testwiki
  assert_status 0
  assert_stderr_line "WARN CROSS_WIKI_REF: refs.md -> [[other:remote-page]]"
}

@test "[[wiki:basename]] with unregistered wiki is a hard error" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [[bogus:remote-page]]."
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR BROKEN_CROSS_WIKI_REF: refs.md -> [[bogus:remote-page]] (wiki 'bogus' not in registry)"
}

@test "[[wiki:basename]] whose basename is missing from that wiki is a hard error" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [[other:no-such-page]]."
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR BROKEN_CROSS_WIKI_REF: refs.md -> [[other:no-such-page]] (basename not in wiki 'other')"
}

@test "valid markdown cross-link to a sibling vault passes silently" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [see](../other-wiki/vault/remote-page.md)."
  run_guard testwiki
  assert_status 0
  refute_stderr_line "BROKEN_CROSS_LINK"
}

@test "markdown cross-link to a missing file is a hard error" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [see](../other-wiki/vault/nope.md)."
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR BROKEN_CROSS_LINK: refs.md -> ../other-wiki/vault/nope.md (file not found)"
}

@test "markdown cross-link to an unregistered wiki is a hard error" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [see](../ghost-wiki/vault/x.md)."
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR BROKEN_CROSS_LINK: refs.md -> ../ghost-wiki/vault/x.md (wiki 'ghost' not in registry)"
}

@test "cross-wiki counters appear in the JSON checks block" {
  crosswiki_setup
  make_valid_page "refs.md" "Links [[home]] and [[other:remote-page]] and [[other:no-such-page]]."
  run_guard testwiki --format=json
  assert_status 1
  [ "$(jq -r '.checks.cross_wiki_refs'        <<< "$output")" = "1" ]
  [ "$(jq -r '.checks.broken_cross_wiki_refs' <<< "$output")" = "1" ]
}
