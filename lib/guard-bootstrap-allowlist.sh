#!/usr/bin/env bash
# lib/guard-bootstrap-allowlist.sh — initialize .config/guard-allowlist.json
# from the current vault state.
#
# Usage:
#   lib/guard-bootstrap-allowlist.sh                # all wikis
#   lib/guard-bootstrap-allowlist.sh <wiki>         # one wiki
#   lib/guard-bootstrap-allowlist.sh --merge        # merge into existing
#
# For each wiki, runs the guard with --no-allowlist in strict mode, parses
# stderr, and emits an allowlist entry that records every current violation.
# After bootstrap, `lib/autoresearch-guard.sh <wiki>` exits 0 on the current
# HEAD — Campaigns N1+ then shrink the allowlist by fixing entries.
#
# Requires jq >= 1.6.

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "bootstrap: requires bash >= 4 (brew install bash)" >&2
  exit 67
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOWLIST="$REPO_ROOT/.config/guard-allowlist.json"

MERGE=0
TARGET_WIKI=""
for arg in "$@"; do
  case "$arg" in
    --merge) MERGE=1 ;;
    --*) echo "unknown flag: $arg" >&2; exit 64 ;;
    *) TARGET_WIKI="$arg" ;;
  esac
done

# Which wikis to process?
if [[ -n "$TARGET_WIKI" ]]; then
  WIKIS=("$TARGET_WIKI")
else
  mapfile -t WIKIS < <(jq -r '.wikis | keys[]' "$REPO_ROOT/.config/wikis.json")
fi

# Base JSON (merge with existing if requested, else start fresh).
if (( MERGE )) && [[ -f "$ALLOWLIST" ]]; then
  BASE=$(cat "$ALLOWLIST")
else
  BASE='{}'
fi

for wiki in "${WIKIS[@]}"; do
  echo "bootstrap: $wiki" >&2
  # Capture stderr from a strict guard run (exit 0=clean, 1=violations; anything else is a crash).
  guard_exit=0
  err=$("$SCRIPT_DIR/autoresearch-guard.sh" "$wiki" --strict --no-allowlist 2>&1 >/dev/null) \
    || guard_exit=$?
  if (( guard_exit != 0 && guard_exit != 1 )); then
    echo "bootstrap: guard crashed with exit $guard_exit for wiki '$wiki'" >&2
    echo "bootstrap: guard output: $err" >&2
    exit 1
  fi

  orphans=$(awk '/^WARN ORPHAN:/ {sub(/^WARN ORPHAN: /,""); print}' <<< "$err" | jq -R . | jq -s .)
  broken=$(awk '/^ERROR BROKEN_WIKILINK:/ {sub(/^ERROR BROKEN_WIKILINK: /,""); print}' <<< "$err" | jq -R . | jq -s .)
  taxonomy=$(awk '/^WARN UNKNOWN_TAG:/ {sub(/^WARN UNKNOWN_TAG: /,""); print}' <<< "$err" | jq -R . | jq -s .)
  fm=$(awk '/^ERROR MISSING_FRONTMATTER:/ {sub(/^ERROR MISSING_FRONTMATTER: /,""); print}' <<< "$err" | jq -R . | jq -s .)

  BASE=$(jq \
    --arg wiki "$wiki" \
    --argjson orphans "$orphans" \
    --argjson broken "$broken" \
    --argjson taxonomy "$taxonomy" \
    --argjson fm "$fm" \
    '.[$wiki] = {
       orphans:              $orphans,
       broken_wikilinks:     $broken,
       taxonomy_violations:  $taxonomy,
       missing_frontmatter:  $fm
     }' <<< "$BASE")
done

mkdir -p "$(dirname "$ALLOWLIST")"
printf '%s\n' "$BASE" | jq . > "$ALLOWLIST"
echo "wrote: $ALLOWLIST" >&2

# Verify guard now passes under the new allowlist.
PASS=1
for wiki in "${WIKIS[@]}"; do
  result=$("$SCRIPT_DIR/autoresearch-guard.sh" "$wiki" --format=json 2>/dev/null)
  passed=$(jq -r '.passed' <<< "$result")
  hard=$(jq -r '.hard_errors' <<< "$result")
  echo "verify: $wiki passed=$passed hard_errors=$hard" >&2
  [[ "$passed" == "true" ]] || PASS=0
done

if (( PASS )); then
  echo "allowlist bootstrap: OK — all wikis pass with current allowlist" >&2
  exit 0
fi
echo "allowlist bootstrap: FAILED — at least one wiki still has hard errors" >&2
exit 1
