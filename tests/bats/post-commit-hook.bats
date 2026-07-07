#!/usr/bin/env bats
# .claude/hooks/post-commit-quality-guard.sh — advisory PostToolUse hook.
# The load-bearing contract is that it NEVER blocks (exit 0 in every case)
# and only speaks up on autoresearch/* branches.

load test_helper

hook_setup() {  # $1 = fixture vault, $2 = branch name
  make_sandbox "$1"
  mkdir -p "$SANDBOX/.claude/hooks"
  cp "$TESTS_REPO_ROOT/.claude/hooks/post-commit-quality-guard.sh" \
     "$SANDBOX/.claude/hooks/"
  git -C "$SANDBOX" init -q -b "$2"
}

run_hook() {
  run --separate-stderr bash "$SANDBOX/.claude/hooks/post-commit-quality-guard.sh"
}

@test "non-autoresearch branch: silent exit 0" {
  hook_setup vault-clean main
  run_hook
  assert_status 0
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "autoresearch branch: emits quality summary, exit 0" {
  hook_setup vault-clean autoresearch/testwiki-campaign-3
  run_hook
  assert_status 0
  assert_stderr_line "::post-commit-guard:: autoresearch/testwiki-campaign-3 —"
  assert_stderr_line "vague_sources=0"
  assert_stderr_line "missing_breadcrumbs=0"
  assert_stderr_line "manifest_unanchored=0"
}

@test "wiki name is extracted from autoresearch/<wiki>-campaign-<N>" {
  hook_setup vault-clean autoresearch/testwiki-campaign-42
  run_hook
  assert_status 0
  refute_stderr_line "hard-fail"
}

@test "guard hard-failure still exits 0 with a hard-fail note" {
  hook_setup vault-broken autoresearch/testwiki-campaign-1
  run_hook
  assert_status 0
  assert_stderr_line "hard-fail on branch autoresearch/testwiki-campaign-1"
}

@test "unknown wiki in branch name still exits 0" {
  hook_setup vault-clean autoresearch/nope-campaign-1
  run_hook
  assert_status 0
  assert_stderr_line "hard-fail on branch"
}

@test "outside a git repository: silent exit 0" {
  make_sandbox vault-clean
  mkdir -p "$SANDBOX/.claude/hooks"
  cp "$TESTS_REPO_ROOT/.claude/hooks/post-commit-quality-guard.sh" \
     "$SANDBOX/.claude/hooks/"
  run_hook
  assert_status 0
  [ -z "$stderr" ]
}
