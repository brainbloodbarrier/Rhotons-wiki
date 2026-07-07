#!/usr/bin/env bats
# lib/autoresearch-guard.sh — machine-readable output contracts.
# The post-commit hook and campaign tooling parse --format=json (.checks.*)
# and --format=tsv; the key set and field count are unwritten APIs.

load test_helper

@test "--format=json emits valid JSON on stdout, violations only on stderr" {
  make_sandbox vault-broken
  run_guard testwiki --format=json
  assert_status 1
  jq empty <<< "$output"
  assert_stderr_line "ERROR BROKEN_WIKILINK"
  # stdout must contain no violation lines
  ! grep -qE '^(ERROR|WARN) ' <<< "$output"
}

@test "json top-level key set is exactly the documented contract" {
  make_sandbox vault-clean
  run_guard testwiki --format=json
  assert_status 0
  jq -e 'keys == ["baseline","baseline_fail","checks","current_score","hard_errors","passed","quality","strict","wiki"]' \
    <<< "$output" > /dev/null
}

@test "json .checks has exactly the 11 documented counters" {
  make_sandbox vault-clean
  run_guard testwiki --format=json
  jq -e '.checks | keys == [
    "broken_cross_links","broken_cross_wiki_refs","broken_wikilinks",
    "cross_wiki_refs","frontmatter_errors","manifest_unanchored",
    "missing_breadcrumbs","orphan_pages","soft_field_warnings",
    "taxonomy_violations","vague_sources"]' <<< "$output" > /dev/null
}

@test "json passed is true iff no hard errors and no baseline failure" {
  make_sandbox vault-clean
  run_guard testwiki --format=json
  [ "$(jq -r '.passed' <<< "$output")" = "true" ]

  make_sandbox vault-broken
  run_guard testwiki --format=json
  [ "$(jq -r '.passed' <<< "$output")" = "false" ]
  [ "$(jq -r '.hard_errors' <<< "$output")" = "3" ]
}

@test "json strict/quality flags are reflected as booleans" {
  make_sandbox vault-clean
  run_guard testwiki --strict --quality --format=json
  [ "$(jq -r '.strict'  <<< "$output")" = "true" ]
  [ "$(jq -r '.quality' <<< "$output")" = "true" ]
}

@test "--strict adds warn counts into hard_errors" {
  make_sandbox vault-broken
  run_guard testwiki --format=json
  [ "$(jq -r '.hard_errors' <<< "$output")" = "3" ]
  # + 1 orphan + 1 taxonomy violation under --strict
  run_guard testwiki --strict --format=json
  [ "$(jq -r '.hard_errors' <<< "$output")" = "5" ]
}

@test "--format=tsv emits exactly one row with 15 tab-separated fields" {
  make_sandbox vault-broken
  run_guard testwiki --format=tsv
  assert_status 1
  [ "${#lines[@]}" -eq 1 ]
  [ "$(awk -F'\t' '{print NF}' <<< "$output")" = "15" ]
  [ "$(cut -f1 <<< "$output")" = "testwiki" ]
}

@test "text format keeps stdout empty and summarizes on stderr" {
  make_sandbox vault-clean
  run_guard testwiki
  assert_status 0
  [ -z "$output" ]
  assert_stderr_line "guard: testwiki"
}

@test "--help exits 0 and prints usage" {
  make_sandbox vault-clean
  run_guard --help
  assert_status 0
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown option exits 64" {
  make_sandbox vault-clean
  run_guard testwiki --frobnicate
  assert_status 64
}

@test "unexpected extra positional exits 64" {
  make_sandbox vault-clean
  run_guard testwiki extra-arg
  assert_status 64
}
