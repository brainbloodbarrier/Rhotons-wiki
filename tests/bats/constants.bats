#!/usr/bin/env bats
# lib/constants.sh — normalize_target is the single source of truth for
# wikilink target resolution across guard, crossmap generator, and the
# cross-wiki migrator. Its mapping must stay identical for all three.

load test_helper

setup() {
  # Sourced directly from the real lib — pure function, no repo state.
  source "$TESTS_REPO_ROOT/lib/constants.sh"
}

@test "normalize_target lowercases" {
  [ "$(normalize_target 'UPPER')" = "upper" ]
  [ "$(normalize_target 'MiXeD-Case')" = "mixed-case" ]
}

@test "normalize_target maps spaces to hyphens" {
  [ "$(normalize_target 'foo bar baz')" = "foo-bar-baz" ]
  [ "$(normalize_target 'Case Sensitive Page')" = "case-sensitive-page" ]
}

@test "normalize_target strips a trailing backslash" {
  [ "$(normalize_target 'foo\')" = "foo" ]
}

@test "normalize_target leaves canonical keys unchanged" {
  [ "$(normalize_target 'already-canonical-key')" = "already-canonical-key" ]
}

@test "BREADCRUMB_RE matches all six typed relation pairs" {
  source "$TESTS_REPO_ROOT/lib/constants.sh"
  for key in parent child branch-of branches innervates innervated-by \
             traverses traversed-by approach-to approached-via \
             drains-to drained-by; do
    grep -qE "$BREADCRUMB_RE" <<< "$key: something" || {
      echo "BREADCRUMB_RE failed to match '$key:'" >&2
      return 1
    }
  done
  # And must not match arbitrary frontmatter keys.
  ! grep -qE "$BREADCRUMB_RE" <<< "title: something"
}
