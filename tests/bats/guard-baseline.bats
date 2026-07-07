#!/usr/bin/env bats
# lib/autoresearch-guard.sh — --baseline score-regression detection.
# The autoresearch loop branches on exit code: 2 = regression, 1 = hard
# errors. Precedence and the strict less-than comparison are contracts.
#
# Pass-path tests use vault-clean (no hard errors) with the score computed
# live, so fixture edits cannot silently break the baseline arithmetic.

load test_helper

clean_score() {
  SCORE="$("$SANDBOX/lib/autoresearch-verify.sh" testwiki)"
}

@test "score below baseline exits 2 with SCORE REGRESSION on stderr" {
  make_sandbox vault-clean
  clean_score
  run_guard testwiki --baseline "$(( SCORE + 1 ))"
  assert_status 2
  assert_stderr_line "SCORE REGRESSION"
}

@test "score equal to baseline passes (strict less-than)" {
  make_sandbox vault-clean
  clean_score
  run_guard testwiki --baseline "$SCORE"
  assert_status 0
  refute_stderr_line "SCORE REGRESSION"
}

@test "score above baseline passes" {
  make_sandbox vault-clean
  clean_score
  run_guard testwiki --baseline "$(( SCORE - 1 ))"
  assert_status 0
}

@test "--baseline=N form is equivalent to --baseline N" {
  make_sandbox vault-clean
  clean_score
  run_guard testwiki "--baseline=$(( SCORE + 1 ))"
  assert_status 2
}

@test "baseline failure takes precedence over hard errors (exit 2, not 1)" {
  make_sandbox vault-broken
  run_guard testwiki --baseline 9999999
  assert_status 2
}

@test "json carries numeric baseline/current_score and boolean baseline_fail" {
  make_sandbox vault-clean
  clean_score
  run_guard testwiki --baseline "$(( SCORE + 1 ))" --format=json
  assert_status 2
  [ "$(jq -r '.baseline'      <<< "$output")" = "$(( SCORE + 1 ))" ]
  [ "$(jq -r '.current_score' <<< "$output")" = "$SCORE" ]
  [ "$(jq -r '.baseline_fail' <<< "$output")" = "true" ]
  [ "$(jq -r '.passed'        <<< "$output")" = "false" ]
}

@test "without --baseline, json baseline fields are null" {
  make_sandbox vault-clean
  run_guard testwiki --format=json
  assert_status 0
  [ "$(jq -r '.baseline'      <<< "$output")" = "null" ]
  [ "$(jq -r '.current_score' <<< "$output")" = "null" ]
  [ "$(jq -r '.baseline_fail' <<< "$output")" = "false" ]
}
