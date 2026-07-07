#!/usr/bin/env bats
# lib/campaign-status.sh — per-subdir campaign dashboard. The TSV shape and
# the target_met rule (>=1 manifest-anchored page with a breadcrumb and >=5
# unique wikilinks) are what campaign tooling reads.

load test_helper

# Registers a sources dir for the sandbox wiki and builds:
#   sources/chapter-one: 2 PDFs, 1 ingested -> artery-one (2 wikilinks: target no)
#   sources/chapter-two: 1 PDF, 1 ingested -> rich.md (5 wikilinks: target yes)
status_setup() {
  make_sandbox vault-clean
  local tmp
  tmp=$(mktemp "$BATS_TEST_TMPDIR/wikis.XXXXXX")
  jq '.wikis.testwiki.sources = "sources"' "$SANDBOX/.config/wikis.json" > "$tmp"
  mv "$tmp" "$SANDBOX/.config/wikis.json"

  mkdir -p "$SANDBOX/sources/chapter-one" "$SANDBOX/sources/chapter-two"
  touch "$SANDBOX/sources/chapter-one/a.pdf" "$SANDBOX/sources/chapter-one/b.pdf"
  touch "$SANDBOX/sources/chapter-two/c.pdf"

  make_page "anatomy/rich.md" <<'EOF'
---
title: Rich
category: anatomy
tags: [anatomy]
summary: Meets the per-subdir target.
sources: ["Test 2026, p. 2"]
created: 2026-01-01
updated: 2026-01-01
parent: artery-one
---

[[l-one]] [[l-two]] [[l-three]] [[l-four]] [[l-five]]
EOF

  jq -n '{sources: {
    "chapter-one/a.pdf": {wiki_page: "anatomy/artery-one.md"},
    "chapter-two/c.pdf": {wiki_page: "anatomy/rich.md"}
  }}' > "$SANDBOX/testwiki-wiki/vault/.manifest.json"
}

run_status() { run --separate-stderr "$SANDBOX/lib/campaign-status.sh" "$@"; }

@test "missing sources dir exits 66" {
  make_sandbox vault-clean   # registry has no sources field
  run_status testwiki
  assert_status 66
  assert_stderr_line "WIKI_SOURCES not a directory"
}

@test "emits comment header and TSV column header" {
  status_setup
  run_status testwiki campaign-7
  assert_status 0
  [[ "${lines[0]}" == "# campaign-status: wiki=testwiki campaign=campaign-7"* ]]
  [ "${lines[1]}" = "$(printf 'subdir\tpdfs_source\tpdfs_ingested\tpages_in_vault\tavg_breadcrumbs\ttarget_met')" ]
}

@test "subdir below target: counts PDFs/ingested/pages, target_met no" {
  status_setup
  run_status testwiki
  assert_status 0
  # artery-one has a breadcrumb but only 2 unique wikilinks (< 5)
  [[ "$output" == *"$(printf 'chapter-one\t2\t1\t1\t1.00\tno')"* ]]
}

@test "subdir at target: breadcrumb + >=5 unique wikilinks flips target_met" {
  status_setup
  run_status testwiki
  assert_status 0
  [[ "$output" == *"$(printf 'chapter-two\t1\t1\t1\t1.00\tyes')"* ]]
}

@test "manifest page missing from vault counts as ingested but not in vault" {
  status_setup
  rm "$SANDBOX/testwiki-wiki/vault/anatomy/rich.md"
  run_status testwiki
  assert_status 0
  [[ "$output" == *"$(printf 'chapter-two\t1\t1\t0\t0.0\tno')"* ]]
}

@test "malformed manifest exits 66 with a parse error" {
  status_setup
  echo "{ not json" > "$SANDBOX/testwiki-wiki/vault/.manifest.json"
  run_status testwiki
  assert_status 66
  assert_stderr_line "manifest parse error"
}
