#!/usr/bin/env bash
# .claude/hooks/post-commit-quality-guard.sh
#
# PostToolUse hook fired after Bash `git commit`. If the HEAD commit is on
# an autoresearch/* branch, runs the quality guard in soft-warn mode and
# emits a one-line summary to stderr. Never blocks the loop — the warning
# is purely visibility-layer. The loop author is expected to react when
# warn counts rise iteration over iteration.
#
# Reads nothing from stdin. Exits 0 always (advisory).
#
# The wiki to check is inferred from the branch name pattern:
#   autoresearch/<wiki>-campaign-<N>  →  <wiki>
#
# Triggered by Claude Code hook config; safe to run manually too:
#   bash .claude/hooks/post-commit-quality-guard.sh

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"
case "$BRANCH" in
  autoresearch/*) ;;
  *) exit 0 ;;
esac

# Extract wiki name: strip prefix, strip trailing -campaign-N
WIKI="${BRANCH#autoresearch/}"
WIKI="${WIKI%-campaign-*}"

[[ -z "$WIKI" ]] && exit 0
[[ ! -x lib/autoresearch-guard.sh ]] && exit 0

OUT=$(mktemp -t guardXXXX.json)
trap 'rm -f "$OUT"' EXIT

if ! lib/autoresearch-guard.sh "$WIKI" --quality --format=json >"$OUT" 2>/dev/null; then
  echo "::post-commit-guard:: hard-fail on branch $BRANCH — inspect vault" >&2
  exit 0
fi

jq -r --arg b "$BRANCH" '
  .checks as $c |
  [
    "vague_sources=" + ($c.vague_sources|tostring),
    "missing_breadcrumbs=" + ($c.missing_breadcrumbs|tostring),
    "manifest_unanchored=" + ($c.manifest_unanchored|tostring)
  ] | "::post-commit-guard:: \($b) — " + join(" ")
' "$OUT" >&2 || true

exit 0
