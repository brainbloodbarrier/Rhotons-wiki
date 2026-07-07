#!/usr/bin/env bats
# lib/autoresearch-guard.sh — wikilink resolution, orphan detection,
# taxonomy enforcement, and the --strict / --quality gates.

load test_helper

@test "dangling wikilink is a hard error with the exact parseable shape" {
  make_sandbox vault-broken
  run_guard testwiki
  assert_status 1
  # guard-bootstrap-allowlist.sh parses this exact "page -> [[target]]"
  # string; changing the format breaks allowlist round-tripping.
  assert_stderr_line "ERROR BROKEN_WIKILINK: dangler.md -> [[does-not-exist]]"
}

@test "resolution is case-insensitive and treats spaces as hyphens" {
  make_sandbox vault-broken
  run_guard testwiki
  # hub.md links [[case sensitive page]] -> "Case Sensitive Page.md"
  refute_stderr_line "[[case sensitive page]]"
}

@test "embeds ![[...]] are ignored even when the target does not exist" {
  make_sandbox vault-clean
  make_page "anatomy/embedder.md" <<'EOF'
---
title: Embedder
category: anatomy
tags: [anatomy]
summary: Embeds must not be treated as wikilinks.
sources: ["Test 2026, p. 9"]
created: 2026-01-01
updated: 2026-01-01
parent: artery-one
---

![[missing-figure.png]]
![[nonexistent-page]]
And a real link: [[artery-one]].
EOF
  run_guard testwiki
  assert_status 0
  refute_stderr_line "BROKEN_WIKILINK"
}

@test "targets with binary/file extensions are skipped" {
  make_sandbox vault-clean
  make_page "anatomy/attachments.md" <<'EOF'
---
title: Attachments
category: anatomy
tags: [anatomy]
summary: Attachment-style links are not page links.
sources: ["Test 2026, p. 10"]
created: 2026-01-01
updated: 2026-01-01
parent: artery-one
---

[[figure.png]] [[scan.pdf]] [[clip.mp4]] and [[artery-one]].
EOF
  run_guard testwiki
  assert_status 0
  refute_stderr_line "BROKEN_WIKILINK"
}

@test "aliases [[target|text]] and anchors [[target#section]] resolve on target" {
  make_sandbox vault-clean
  make_page "anatomy/fancy-links.md" <<'EOF'
---
title: Fancy Links
category: anatomy
tags: [anatomy]
summary: Alias and anchor syntax must resolve on the bare target.
sources: ["Test 2026, p. 11"]
created: 2026-01-01
updated: 2026-01-01
parent: artery-one
---

See [[artery-one|the first artery]] and [[artery-two#Branches]].
EOF
  run_guard testwiki
  assert_status 0
  refute_stderr_line "BROKEN_WIKILINK"
}

@test "orphan page warns by default (exit 0)" {
  make_sandbox vault-clean
  make_valid_page "anatomy/loner.md" "Links out to [[artery-one]] but nothing links here."
  run_guard testwiki
  assert_status 0
  assert_stderr_line "WARN ORPHAN: anatomy/loner.md"
}

@test "orphan page is a hard error under --strict" {
  make_sandbox vault-clean
  make_valid_page "anatomy/loner.md" "Links out to [[artery-one]] but nothing links here."
  run_guard testwiki --strict
  assert_status 1
}

@test "_meta pages are exempt from the orphan check" {
  make_sandbox vault-clean
  run_guard testwiki
  assert_status 0
  refute_stderr_line "ORPHAN: _meta/taxonomy.md"
}

@test "unknown tag warns by default, hard-fails under --strict" {
  make_sandbox vault-clean
  make_valid_page "anatomy/tagged.md" "Links out to [[artery-one]]."
  # Overwrite with a tag outside the taxonomy.
  make_page "anatomy/tagged.md" <<'EOF'
---
title: Tagged
category: anatomy
tags: [weird-tag]
summary: Tag not present in the taxonomy.
sources: ["Test 2026, p. 12"]
created: 2026-01-01
updated: 2026-01-01
parent: artery-one
---

Links out to [[artery-one]].
EOF
  run_guard testwiki
  assert_status 0
  assert_stderr_line "WARN UNKNOWN_TAG: anatomy/tagged.md -> weird-tag"

  run_guard testwiki --strict
  assert_status 1
}

@test "no taxonomy file disables the tag check entirely" {
  make_sandbox
  make_valid_page "a.md" "Links [[b]]."
  make_valid_page "b.md" "Links [[a]]."
  run_guard testwiki
  assert_status 0
  refute_stderr_line "UNKNOWN_TAG"
}

@test "--quality flags vague sources; without the flag it stays silent" {
  make_sandbox vault-broken
  run_guard testwiki --quality --format=json
  assert_status 1
  assert_stderr_line "WARN VAGUE_SOURCES: vague-source.md"
  [ "$(jq -r '.checks.vague_sources' <<< "$output")" = "1" ]

  run_guard testwiki --format=json
  refute_stderr_line "VAGUE_SOURCES"
  [ "$(jq -r '.checks.vague_sources' <<< "$output")" = "0" ]
}

@test "--quality flags pages without a typed breadcrumb; _meta is exempt" {
  make_sandbox vault-clean
  make_page "anatomy/no-crumb.md" <<'EOF'
---
title: No Crumb
category: anatomy
tags: [anatomy]
summary: Page without any typed relation field.
sources: ["Test 2026, p. 13"]
created: 2026-01-01
updated: 2026-01-01
---

Links out to [[artery-one]].
EOF
  run_guard testwiki --quality
  assert_status 0
  assert_stderr_line "WARN MISSING_BREADCRUMB: anatomy/no-crumb.md"
  refute_stderr_line "MISSING_BREADCRUMB: _meta/taxonomy.md"
}
