#!/bin/bash
# lib/autoresearch-verify.sh — compute the autoresearch score for a wiki.
#
# Usage: lib/autoresearch-verify.sh <wiki-name>
# Output: integer score on stdout.
# Exit: 0 on success, 64/65/66/67 from resolve-wiki.sh on config errors.
#
# Score formula: (pages * 10) + (lines_with_wikilinks * 2) + (words / 100)
# Note: wikilinks counts *lines* containing at least one [[, not individual links.
# Counted across all .md files except index.md, log.md, .obsidian/, .smart-env/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/resolve-wiki.sh" "${1:-}"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT="$REPO_ROOT/$WIKI_VAULT"

PAGES=$(find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -not -name "index.md" \
  -not -name "log.md" | wc -l | tr -d ' ')

LINKS=$(grep -r '\[\[' "$VAULT" --include="*.md" 2>/dev/null \
  | grep -v "/.obsidian/" \
  | grep -v "/.smart-env/" \
  | wc -l | tr -d ' ') || LINKS=0

WORDS=$(find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -exec cat {} \; 2>/dev/null | wc -w | tr -d ' ') || WORDS=0

SCORE=$(( (PAGES * 10) + (LINKS * 2) + (WORDS / 100) ))
echo "$SCORE"
