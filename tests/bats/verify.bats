#!/usr/bin/env bats
# Freeze lib/autoresearch-verify.sh. The v1 formula is documented as FROZEN
# (125+ baseline rows in .autoresearch/*/results.tsv depend on it) — these
# tests characterize its behavior EXACTLY as implemented, including quirks.
# If any of these fail after an edit to verify, the edit changed the score
# of every existing baseline. Do not "fix" the quirk; revert the edit.

load test_helper

@test "v1: vault-scored matches the frozen formula exactly" {
  make_sandbox vault-scored
  run_verify testwiki
  assert_status 0
  # pages: 3 (index.md and log.md are excluded)         -> 3*10 = 30
  # wikilink LINES: 3 — one per page; the two links on
  #   one line in page-a.md count ONCE (lines, not
  #   occurrences)                                       -> 3*2  =  6
  # words: 110 = 10 (index.md) + 10 (log.md) + 3*30     -> 110/100 = 1
  [ "$output" = "37" ]
}

@test "v1: counts wikilink LINES, not occurrences" {
  make_sandbox
  make_page "x.md" <<'EOF'
[[a]] [[b]]
EOF
  run_verify testwiki
  assert_status 0
  # pages 1 -> 10; ONE line containing links -> 2; words 2 -> 0
  [ "$output" = "12" ]
}

@test "v1: index.md and log.md count toward words but not pages" {
  make_sandbox
  printf 'w %.0s' {1..100} > "$SANDBOX/$WIKI-wiki/vault/index.md"
  printf 'w %.0s' {1..100} > "$SANDBOX/$WIKI-wiki/vault/log.md"
  run_verify testwiki
  assert_status 0
  # pages 0 -> 0; links 0 -> 0; words 200 -> 2
  [ "$output" = "2" ]
}

@test "v1: empty vault scores 0" {
  make_sandbox
  run_verify testwiki
  assert_status 0
  [ "$output" = "0" ]
}

@test "v1: output is a bare integer (the loop does arithmetic on it)" {
  make_sandbox vault-scored
  run_verify testwiki
  assert_status 0
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "v2: vault-scored scores unique targets instead of link lines" {
  make_sandbox vault-scored
  run_verify testwiki --v2
  assert_status 0
  # pages 3 -> 30; breadcrumbs 0; unique targets 4
  # (page-a: {page-b,page-c}, page-b: {page-a}, page-c: {page-a}) -> 8;
  # specific sources 0; words 110 -> 1
  [ "$output" = "39" ]
}

@test "v2: repeated [[X]] dedupes; embeds and attachment links are excluded" {
  make_sandbox
  make_page "x.md" <<'EOF'
[[target]] [[target]]
![[picture.png]]
[[diagram.pdf]]
EOF
  run_verify testwiki --v2
  assert_status 0
  # pages 1 -> 10; unique targets {target} -> 2; words 4 -> 0
  [ "$output" = "12" ]
}

@test "v2: typed breadcrumb in frontmatter adds 5" {
  make_sandbox
  make_page "a.md" <<'EOF'
---
title: A
parent: page-b
---

[[page-b]]
EOF
  run_verify testwiki --v2
  assert_status 0
  # pages 1 -> 10; breadcrumbs 1 -> 5; unique {page-b} -> 2; words 7 -> 0
  [ "$output" = "17" ]
}

@test "v2: source with a digit counts as specific citation (+3)" {
  make_sandbox
  make_page "s.md" <<'EOF'
---
title: S
sources: ["Rhoton 2023, Ch. 4"]
---

body
EOF
  run_verify testwiki --v2
  assert_status 0
  # pages 1 -> 10; specific sources 1 -> 3; words 10 -> 0
  [ "$output" = "13" ]
}

@test "v2: vague source (no digit, short) earns no citation points" {
  make_sandbox
  make_page "s.md" <<'EOF'
---
title: S
sources: [Rhoton]
---

body
EOF
  run_verify testwiki --v2
  assert_status 0
  # pages 1 -> 10; sources present but vague -> 0; words 8 -> 0
  [ "$output" = "10" ]
}

@test "unknown option exits 64" {
  make_sandbox
  run_verify testwiki --bogus
  assert_status 64
}

@test "missing wiki argument exits 64 (from resolve-wiki)" {
  make_sandbox
  run_verify
  assert_status 64
}
