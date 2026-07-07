#!/usr/bin/env bats
# lib/autoresearch-guard.sh — frontmatter checks (hard) and soft-field
# warnings. Exit 1 is what CLAUDE.md defines as campaign "failure", so the
# hard/soft split here is load-bearing for the autoresearch loop.

load test_helper

@test "clean vault exits 0 with no ERROR/WARN lines" {
  make_sandbox vault-clean
  run_guard testwiki
  assert_status 0
  ! grep -qE '^(ERROR|WARN) ' <<< "$stderr"
}

@test "clean vault passes --strict and --quality too" {
  make_sandbox vault-clean
  run_guard testwiki --strict --quality
  assert_status 0
  ! grep -qE '^(ERROR|WARN) ' <<< "$stderr"
}

@test "page without frontmatter is a hard error" {
  make_sandbox vault-broken
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR MISSING_FRONTMATTER: no-frontmatter.md"
}

@test "missing title field is a hard error" {
  make_sandbox vault-broken
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR MISSING_title: missing-title.md"
}

@test "missing category and tags fields are hard errors" {
  make_sandbox vault-clean
  make_page "anatomy/bare.md" <<'EOF'
---
title: Bare
summary: Only a title and summary.
sources: ["Test 2026, p. 1"]
created: 2026-01-01
updated: 2026-01-01
---

Body linking [[artery-one]].
EOF
  run_guard testwiki
  assert_status 1
  assert_stderr_line "ERROR MISSING_category: anatomy/bare.md"
  assert_stderr_line "ERROR MISSING_tags: anatomy/bare.md"
}

@test "missing soft fields (summary/sources/created/updated) warn but pass" {
  make_sandbox vault-clean
  make_page "anatomy/soft.md" <<'EOF'
---
title: Soft
category: anatomy
tags: [anatomy]
---

Body linking [[artery-one]].
EOF
  run_guard testwiki
  assert_status 0
  assert_stderr_line "WARN MISSING_summary: anatomy/soft.md"
  assert_stderr_line "WARN MISSING_sources: anatomy/soft.md"
  assert_stderr_line "WARN MISSING_created: anatomy/soft.md"
  assert_stderr_line "WARN MISSING_updated: anatomy/soft.md"
}

@test "page skipped by MISSING_FRONTMATTER gets no field-level errors" {
  make_sandbox vault-broken
  run_guard testwiki
  refute_stderr_line "MISSING_title: no-frontmatter.md"
  refute_stderr_line "MISSING_summary: no-frontmatter.md"
}

@test "index.md and log.md are exempt from all guard checks" {
  make_sandbox vault-clean
  make_page "index.md" <<'EOF'
No frontmatter here on purpose.
EOF
  make_page "log.md" <<'EOF'
No frontmatter here either.
EOF
  run_guard testwiki
  assert_status 0
  refute_stderr_line "index.md"
  refute_stderr_line "log.md"
}
