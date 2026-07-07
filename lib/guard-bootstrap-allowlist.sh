#!/usr/bin/env bash
# lib/guard-bootstrap-allowlist.sh — initialize .config/guard-allowlist.json
# from the current vault state.
#
# Usage:
#   lib/guard-bootstrap-allowlist.sh                # all wikis, baseline checks
#   lib/guard-bootstrap-allowlist.sh <wiki>         # one wiki
#   lib/guard-bootstrap-allowlist.sh --merge        # merge into existing
#   lib/guard-bootstrap-allowlist.sh --quality      # include --quality violations
#
# For each wiki, runs the guard with --no-allowlist in strict mode, parses
# stderr, and emits an allowlist entry that records every current violation.
# After bootstrap, `lib/autoresearch-guard.sh <wiki>` exits 0 on the current
# HEAD — Campaigns N1+ then shrink the allowlist by fixing entries.
#
# With --quality, also captures the three quality-tier warnings
# (vague_sources, missing_breadcrumbs, manifest_unanchored) and verifies
# that `guard --quality` passes post-bootstrap.
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
QUALITY=0
TARGET_WIKI=""
for arg in "$@"; do
  case "$arg" in
    --merge) MERGE=1 ;;
    --quality) QUALITY=1 ;;
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

# Guard args: always --strict --no-allowlist; add --quality when requested.
GUARD_ARGS=(--strict --no-allowlist)
if (( QUALITY )); then
  GUARD_ARGS+=(--quality)
fi

for wiki in "${WIKIS[@]}"; do
  if (( QUALITY )); then
    echo "bootstrap: $wiki (with --quality)" >&2
  else
    echo "bootstrap: $wiki" >&2
  fi
  # Capture stderr from the guard run (exit 0=clean, 1=violations; anything else is a crash).
  guard_exit=0
  err=$("$SCRIPT_DIR/autoresearch-guard.sh" "$wiki" "${GUARD_ARGS[@]}" 2>&1 >/dev/null) \
    || guard_exit=$?
  if (( guard_exit != 0 && guard_exit != 1 )); then
    echo "bootstrap: guard crashed with exit $guard_exit for wiki '$wiki'" >&2
    echo "bootstrap: guard output: $err" >&2
    exit 1
  fi

  # Baseline violation kinds (always captured).
  orphans=$(awk '/^WARN ORPHAN:/ {sub(/^WARN ORPHAN: /,""); print}' <<< "$err" | jq -R . | jq -s .)
  broken=$(awk '/^ERROR BROKEN_WIKILINK:/ {sub(/^ERROR BROKEN_WIKILINK: /,""); print}' <<< "$err" | jq -R . | jq -s .)
  taxonomy=$(awk '/^WARN UNKNOWN_TAG:/ {sub(/^WARN UNKNOWN_TAG: /,""); print}' <<< "$err" | jq -R . | jq -s .)
  fm=$(awk '/^ERROR MISSING_FRONTMATTER:/ {sub(/^ERROR MISSING_FRONTMATTER: /,""); print}' <<< "$err" | jq -R . | jq -s .)

  if (( QUALITY )); then
    # Quality-tier violation kinds (only when --quality is on).
    vague=$(awk '/^WARN VAGUE_SOURCES:/ {sub(/^WARN VAGUE_SOURCES: /,""); print}' <<< "$err" | jq -R . | jq -s .)
    breadcrumbs=$(awk '/^WARN MISSING_BREADCRUMB:/ {sub(/^WARN MISSING_BREADCRUMB: /,""); print}' <<< "$err" | jq -R . | jq -s .)
    unanchored=$(awk '/^WARN MANIFEST_UNANCHORED:/ {sub(/^WARN MANIFEST_UNANCHORED: /,""); print}' <<< "$err" | jq -R . | jq -s .)

    BASE=$(jq \
      --arg wiki "$wiki" \
      --argjson orphans "$orphans" \
      --argjson broken "$broken" \
      --argjson taxonomy "$taxonomy" \
      --argjson fm "$fm" \
      --argjson vague "$vague" \
      --argjson breadcrumbs "$breadcrumbs" \
      --argjson unanchored "$unanchored" \
      '.[$wiki] = {
         orphans:              $orphans,
         broken_wikilinks:     $broken,
         taxonomy_violations:  $taxonomy,
         missing_frontmatter:  $fm,
         vague_sources:        $vague,
         missing_breadcrumbs:  $breadcrumbs,
         manifest_unanchored:  $unanchored
       }' <<< "$BASE")
  else
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
  fi
done

mkdir -p "$(dirname "$ALLOWLIST")"
printf '%s\n' "$BASE" | jq . > "$ALLOWLIST"
echo "wrote: $ALLOWLIST" >&2

# Verify guard now passes under the new allowlist. Use --quality on verify
# only if we bootstrapped with --quality, so we check the right tier.
VERIFY_ARGS=(--format=json)
if (( QUALITY )); then
  VERIFY_ARGS+=(--quality)
fi

PASS=1
for wiki in "${WIKIS[@]}"; do
  # `|| true` keeps set -e from aborting here when the guard still fails —
  # the JSON on stdout is captured either way, and the FAILED branch below
  # is the intended reporting path for that case.
  result=$("$SCRIPT_DIR/autoresearch-guard.sh" "$wiki" "${VERIFY_ARGS[@]}" 2>/dev/null) || true
  passed=$(jq -r '.passed' <<< "$result")
  hard=$(jq -r '.hard_errors' <<< "$result")
  echo "verify: $wiki passed=$passed hard_errors=$hard" >&2
  [[ "$passed" == "true" ]] || PASS=0
done

if (( PASS )); then
  if (( QUALITY )); then
    echo "allowlist bootstrap: OK — all wikis pass with --quality under current allowlist" >&2
  else
    echo "allowlist bootstrap: OK — all wikis pass with current allowlist" >&2
  fi
  exit 0
fi
echo "allowlist bootstrap: FAILED — at least one wiki still has hard errors" >&2
exit 1
