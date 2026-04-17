#!/bin/bash
# lib/autoresearch-guard.sh — validate structural integrity of a wiki.
#
# Usage: lib/autoresearch-guard.sh <wiki-name>
# Exit: 0 on pass, 1 on any violation, 64/65/66/67 from resolve-wiki.sh.
# Violations printed to stderr. Exit code is clamped to 0/1 (not violation
# count) to avoid POSIX mod-256 wrap-around when violations exceed 255.
#
# Current checks (Phase 3 baseline — Phase 6 expands with wikilink
# integrity, orphan detection, taxonomy compliance, and no-regression):
#   - frontmatter block opens with `---` as line 1
#   - frontmatter contains `title:`, `category:`, `tags:` keys

set -eu
# pipefail intentionally NOT set: `sed | head -30` causes SIGPIPE (141)
# when head closes the pipe early, which pipefail would surface as a
# spurious failure.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/resolve-wiki.sh" "${1:-}"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT="$REPO_ROOT/$WIKI_VAULT"

ERRORS=0

while IFS= read -r f; do
  HEAD=$(head -1 "$f" 2>/dev/null || true)
  if [[ "$HEAD" != "---" ]]; then
    echo "MISSING FRONTMATTER: $f" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi
  FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$f" | head -30)
  for field in title category tags; do
    if ! grep -q "^${field}:" <<< "$FRONTMATTER"; then
      echo "MISSING $field: $f" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done
done < <(find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -not -name "index.md" \
  -not -name "log.md")

if (( ERRORS > 0 )); then
  echo "GUARD FAILED: $ERRORS error(s)" >&2
  exit 1
fi
exit 0
