#!/usr/bin/env bash
# lib/crossmap-generate.sh — regenerate `pages_index` in crossmap.json
# from the current filesystem state of every wiki registered in wikis.json.
#
# Purpose: enable cross-wiki wikilink resolution in lib/autoresearch-guard.sh.
# The guard (after PR-A2) consults `crossmap.json → pages_index` to accept
# wikilinks that target pages in other vaults.
#
# Usage:
#   lib/crossmap-generate.sh              # regenerate, write crossmap.json
#   lib/crossmap-generate.sh --dry-run    # print JSON to stdout, do not write
#
# What it does:
#   1. For every wiki in .config/wikis.json, walks its vault and enumerates
#      content pages (excludes .obsidian/, .smart-env/, index.md, log.md —
#      same exclusions as the guard).
#   2. Builds pages_index { normalized_basename: [{wiki, path}, ...] }.
#      Same basename across wikis produces a list (preserves both).
#   3. Preserves the existing `bridges` array intact.
#   4. Bumps `version` to "1.1" and updates `generated_at` (ISO-8601 UTC).
#
# Requires: jq, bash >= 4 (uses associative arrays via jq), find.
# Idempotent: run twice in a row → second run overwrites with same content
# (except for generated_at timestamp).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$REPO_ROOT/.config/wikis.json"
CROSSMAP="$REPO_ROOT/crossmap.json"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
elif [[ -n "${1:-}" ]]; then
  echo "crossmap-generate: unknown argument '$1'" >&2
  echo "usage: $0 [--dry-run]" >&2
  exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "crossmap-generate: jq is required" >&2
  exit 67
fi
if [[ ! -f "$CONFIG" ]]; then
  echo "crossmap-generate: registry not found at $CONFIG" >&2
  exit 66
fi

# Normalize a basename to its canonical key — shared with the guard and the
# cross-wiki migrator. Single source of truth: lib/constants.sh.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/constants.sh"

# Accumulate pages_index across all wikis.
PAGES_JSON="{}"
TOTAL_PAGES=0

while IFS= read -r wiki; do
  vault_rel=$(jq -r --arg w "$wiki" '.wikis[$w].vault' "$CONFIG")
  vault="$REPO_ROOT/$vault_rel"
  if [[ ! -d "$vault" ]]; then
    echo "crossmap-generate: wiki '$wiki' has no vault at $vault — skipping" >&2
    continue
  fi

  wiki_count=0
  while IFS= read -r rel; do
    base=$(basename "$rel" .md)
    key=$(normalize_target "$base")
    # Path relative to vault root (so consumers can reassemble absolute paths).
    path_rel="${rel#$vault/}"
    entry=$(jq -n --arg w "$wiki" --arg p "$path_rel" '{wiki: $w, path: $p}')
    PAGES_JSON=$(jq --arg k "$key" --argjson e "$entry" \
      '.[$k] = ((.[$k] // []) + [$e])' <<< "$PAGES_JSON")
    wiki_count=$((wiki_count + 1))
  done < <(find "$vault" -name "*.md" \
    -not -path "*/.obsidian/*" \
    -not -path "*/.smart-env/*" \
    -not -name "index.md" \
    -not -name "log.md" \
    -print)

  echo "crossmap-generate: $wiki → $wiki_count pages" >&2
  TOTAL_PAGES=$((TOTAL_PAGES + wiki_count))
done < <(jq -r '.wikis | keys[]' "$CONFIG")

# Preserve existing bridges (curated semantic relations — do not touch).
EXISTING_BRIDGES="[]"
if [[ -f "$CROSSMAP" ]]; then
  EXISTING_BRIDGES=$(jq '.bridges // []' "$CROSSMAP" 2>/dev/null || echo "[]")
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OUTPUT=$(jq -n \
  --arg ts "$TIMESTAMP" \
  --argjson bridges "$EXISTING_BRIDGES" \
  --argjson pages_index "$PAGES_JSON" \
  '{
    version: "1.1",
    generated_at: $ts,
    bridges: $bridges,
    pages_index: $pages_index
  }')

# Validate structure before writing.
jq empty <<< "$OUTPUT"

if (( DRY_RUN )); then
  printf '%s\n' "$OUTPUT"
  echo "crossmap-generate: dry-run — pages_index: $(jq '.pages_index | length' <<< "$OUTPUT") unique keys, $TOTAL_PAGES total page entries" >&2
else
  printf '%s\n' "$OUTPUT" > "$CROSSMAP"
  echo "crossmap-generate: wrote $CROSSMAP" >&2
  echo "crossmap-generate: pages_index: $(jq '.pages_index | length' "$CROSSMAP") unique keys, $TOTAL_PAGES total page entries" >&2
  echo "crossmap-generate: bridges preserved: $(jq '.bridges | length' "$CROSSMAP") entries" >&2
fi
