#!/usr/bin/env bats
# lib/resolve-wiki.sh — registry resolution and documented exit codes
# (64 usage / 65 unknown wiki / 66 missing config or vault). The script is
# meant to be sourced, so each test sources it inside a bash -c subshell.

load test_helper

source_resolve() {
  # $1 = extra shell to run after sourcing succeeds; $2 = wiki arg
  run --separate-stderr bash -c \
    "cd '$SANDBOX' && source lib/resolve-wiki.sh ${2-} && ${1:-true}"
}

@test "resolves a registered wiki and exports WIKI_* variables" {
  make_sandbox vault-clean
  source_resolve 'printf "%s|%s|%s|%s\n" "$WIKI_NAME" "$WIKI_VAULT" "$WIKI_DOMAIN" "$WIKI_OUTPUT"' testwiki
  assert_status 0
  [ "$output" = "testwiki|testwiki-wiki/vault|test|.autoresearch/testwiki" ]
}

@test "fields absent from the registry export as empty strings" {
  make_sandbox vault-clean
  source_resolve 'printf "[%s][%s][%s]\n" "$WIKI_SOURCES" "$WIKI_RAW_SOURCE" "$WIKI_EXTRACTIONS"' testwiki
  assert_status 0
  [ "$output" = "[][][]" ]
}

@test "creates the .autoresearch/<wiki> output directory" {
  make_sandbox vault-clean
  source_resolve true testwiki
  assert_status 0
  [ -d "$SANDBOX/.autoresearch/testwiki" ]
}

@test "resolves from a nested working directory (walks up to repo root)" {
  make_sandbox vault-clean
  run --separate-stderr bash -c \
    "cd '$SANDBOX/testwiki-wiki/vault' && source ../../lib/resolve-wiki.sh testwiki && echo \"\$WIKI_VAULT\""
  assert_status 0
  [ "$output" = "testwiki-wiki/vault" ]
}

@test "missing wiki name exits 64" {
  make_sandbox vault-clean
  source_resolve true ""
  assert_status 64
}

@test "unknown wiki exits 65 and lists available wikis" {
  make_sandbox vault-clean
  source_resolve true nope
  assert_status 65
  assert_stderr_line "unknown wiki 'nope'"
  assert_stderr_line "available: testwiki"
}

@test "no .config/wikis.json anywhere up the tree exits 66" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"
  cp -R "$TESTS_REPO_ROOT/lib" "$BATS_TEST_TMPDIR/bare/lib"
  run --separate-stderr bash -c \
    "cd '$BATS_TEST_TMPDIR/bare' && source lib/resolve-wiki.sh testwiki"
  assert_status 66
}

@test "invalid JSON in wikis.json exits 66" {
  make_sandbox vault-clean
  echo "{ not json" > "$SANDBOX/.config/wikis.json"
  source_resolve true testwiki
  assert_status 66
  assert_stderr_line "not valid JSON"
}

@test "registered wiki whose vault directory is missing exits 66" {
  make_sandbox vault-clean
  rm -rf "$SANDBOX/testwiki-wiki"
  source_resolve true testwiki
  assert_status 66
  assert_stderr_line "does not exist"
}
