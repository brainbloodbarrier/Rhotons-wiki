#!/usr/bin/env bats
# lib/crosswiki-migrate.sh — converts locally-unresolved [[basename]] links
# into markdown cross-links. This script WRITES INTO VAULTS under --apply,
# so dry-run purity, skip rules, and idempotence are the critical contracts.

load test_helper

# Sandbox: testwiki holds the links; "other" resolves remote-page uniquely;
# dup-page exists in BOTH other and third (ambiguous); ghost-page nowhere.
migrate_setup() {
  make_sandbox "" testwiki
  add_wiki other
  add_wiki third
  make_valid_page "local-two.md" "Links [[subject]]."
  WIKI=other make_valid_page "remote-page.md" "Remote body."
  WIKI=other make_valid_page "dup-page.md" "In other."
  WIKI=third make_valid_page "dup-page.md" "In third."
  "$SANDBOX/lib/crossmap-generate.sh" 2>/dev/null
}

subject_page() {  # body varies per test
  make_page "subject.md" <<EOF
---
title: subject
category: anatomy
tags: [anatomy]
summary: Migration subject page.
sources: ["Test 2026, p. 1"]
created: 2026-01-01
updated: 2026-01-01
parent: local-two
---

$1
EOF
}

vault_checksum() {
  find "$SANDBOX/testwiki-wiki/vault" -type f -print0 | sort -z \
    | xargs -0 md5sum | md5sum
}

@test "wiki argument and a mode are both required (exit 64)" {
  migrate_setup
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" --dry-run
  assert_status 64
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki
  assert_status 64
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --dry-run --bogus
  assert_status 64
}

@test "missing crossmap.json exits 66" {
  make_sandbox "" testwiki
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --dry-run
  assert_status 66
}

@test "dry-run emits a unified diff and leaves the vault untouched" {
  migrate_setup
  subject_page "See [[remote-page]] for details."
  local before
  before=$(vault_checksum)
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --dry-run
  assert_status 0
  [[ "$output" == *"-See [[remote-page]] for details."* ]]
  [[ "$output" == *"+See [remote-page](../other-wiki/vault/remote-page.md) for details."* ]]
  [ "$(vault_checksum)" = "$before" ]
}

@test "apply rewrites a uniquely-resolvable link to a markdown cross-link" {
  migrate_setup
  subject_page "See [[remote-page]] for details."
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply
  assert_status 0
  grep -qF "[remote-page](../other-wiki/vault/remote-page.md)" \
    "$SANDBOX/testwiki-wiki/vault/subject.md"
  ! grep -qF "[[remote-page]]" "$SANDBOX/testwiki-wiki/vault/subject.md"
}

@test "apply preserves aliases and anchors on rewritten links" {
  migrate_setup
  subject_page "Alias [[remote-page|Friendly Name]] and anchor [[remote-page#Branches]]."
  "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply 2>/dev/null
  grep -qF "[Friendly Name](../other-wiki/vault/remote-page.md)" \
    "$SANDBOX/testwiki-wiki/vault/subject.md"
  grep -qF "[remote-page](../other-wiki/vault/remote-page.md#Branches)" \
    "$SANDBOX/testwiki-wiki/vault/subject.md"
}

@test "locally-resolving links are left alone" {
  migrate_setup
  subject_page "Local [[local-two]] stays a wikilink."
  "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply 2>/dev/null
  grep -qF "[[local-two]]" "$SANDBOX/testwiki-wiki/vault/subject.md"
}

@test "ambiguous basenames (in >1 other wiki) are skipped and reported" {
  migrate_setup
  subject_page "Ambiguous [[dup-page]] link."
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply \
    --report "$BATS_TEST_TMPDIR/report.md"
  assert_status 0
  grep -qF "[[dup-page]]" "$SANDBOX/testwiki-wiki/vault/subject.md"
  assert_stderr_line "ambiguous skipped:  1 unique"
  grep -qF 'dup-page' "$BATS_TEST_TMPDIR/report.md"
}

@test "unresolvable basenames are skipped and reported" {
  migrate_setup
  subject_page "Ghost [[ghost-page]] link."
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply \
    --report "$BATS_TEST_TMPDIR/report.md"
  assert_status 0
  grep -qF "[[ghost-page]]" "$SANDBOX/testwiki-wiki/vault/subject.md"
  assert_stderr_line "unresolved skipped: 1 unique"
  grep -qF 'ghost-page' "$BATS_TEST_TMPDIR/report.md"
}

@test "skip rules: colon syntax, extensions, and spaced targets untouched" {
  migrate_setup
  subject_page "Keep [[other:remote-page]] and [[figure.png]] and [[Two Words]]."
  "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply 2>/dev/null
  grep -qF "[[other:remote-page]]" "$SANDBOX/testwiki-wiki/vault/subject.md"
  grep -qF "[[figure.png]]"        "$SANDBOX/testwiki-wiki/vault/subject.md"
  grep -qF "[[Two Words]]"         "$SANDBOX/testwiki-wiki/vault/subject.md"
}

@test "second apply run is a no-op (idempotent)" {
  migrate_setup
  subject_page "See [[remote-page]] for details."
  "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply 2>/dev/null
  local after_first
  after_first=$(vault_checksum)
  run --separate-stderr "$SANDBOX/lib/crosswiki-migrate.sh" testwiki --apply
  assert_status 0
  assert_stderr_line "files modified:     0"
  [ "$(vault_checksum)" = "$after_first" ]
}
