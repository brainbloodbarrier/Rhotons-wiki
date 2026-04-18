#!/bin/bash
# lib/autoresearch-verify.sh — compute the autoresearch score for a wiki.
#
# Usage: lib/autoresearch-verify.sh <wiki-name> [--v2]
# Output: integer score on stdout.
# Exit: 0 on success, 64/65/66/67 from resolve-wiki.sh on config errors.
#
# Score v1 (default, historic — do not change; 125+ rows of baseline depend on it):
#   (pages * 10) + (lines_with_wikilinks * 2) + (words / 100)
#
# Score v2 (opt-in, --v2):
#   (pages * 10)
#   + (typed_breadcrumbs * 5)         # frontmatter relation fields
#   + (unique_wikilink_targets * 2)   # no inflation by repeated [[X]]
#   + (specific_source_citations * 3) # sources value with digits or >=40 chars
#   + (words / 100)
#
# Counted across all .md files except index.md, log.md, .obsidian/, .smart-env/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VERSION=1
WIKI_ARG=""
for arg in "$@"; do
  case "$arg" in
    --v2) VERSION=2 ;;
    --v1) VERSION=1 ;;
    -*) echo "verify: unknown option '$arg'" >&2; exit 64 ;;
    *) [[ -z "$WIKI_ARG" ]] && WIKI_ARG="$arg" ;;
  esac
done

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-wiki.sh" "$WIKI_ARG"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT="$REPO_ROOT/$WIKI_VAULT"

PAGES=$(find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -not -name "index.md" \
  -not -name "log.md" | wc -l | tr -d ' ')

WORDS=$(find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -exec cat {} + 2>/dev/null | wc -w | tr -d ' ') || WORDS=0

if (( VERSION == 1 )); then
  LINKS=$(grep -r '\[\[' "$VAULT" --include="*.md" 2>/dev/null \
    | grep -v "/.obsidian/" \
    | grep -v "/.smart-env/" \
    | wc -l | tr -d ' ') || LINKS=0
  SCORE=$(( (PAGES * 10) + (LINKS * 2) + (WORDS / 100) ))
  echo "$SCORE"
  exit 0
fi

# --- Score v2 -----------------------------------------------------------
# shellcheck disable=SC1091
source "$SCRIPT_DIR/constants.sh"

BREADCRUMBS=0
UNIQUE_LINKS=0
SPECIFIC_SOURCES=0

while IFS= read -r f; do
  # Frontmatter slice: lines between the first and second `---`.
  FM=$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {exit} fm {print}' "$f" 2>/dev/null || true)

  BC=$(grep -cE "$BREADCRUMB_RE" <<< "$FM" || true)
  BREADCRUMBS=$(( BREADCRUMBS + BC ))

  # Specific source = sources field exists AND at least one listed value has
  # a digit OR is >=40 chars long (i.e. not just an author/domain).
  SOURCES_VALUE=$(awk '
    /^sources:/ {
      v=$0; sub(/^sources:[[:space:]]*/,"",v)
      if (v ~ /^\[/) { gsub(/[\[\],"'\'']/," ",v); print v; next }
      in_list=1; next
    }
    in_list {
      if (/^[^[:space:]]/) { in_list=0; next }
      if (/^[[:space:]]*-[[:space:]]+/) {
        s=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",s)
        gsub(/["'\'']/,"",s); print s
      }
    }
  ' <<< "$FM" 2>/dev/null || true)
  if [[ -n "$SOURCES_VALUE" ]]; then
    while IFS= read -r srcline; do
      [[ -z "$srcline" ]] && continue
      if [[ "$srcline" =~ [0-9] ]] || (( ${#srcline} >= 40 )); then
        SPECIFIC_SOURCES=$(( SPECIFIC_SOURCES + 1 ))
        break
      fi
    done <<< "$SOURCES_VALUE"
  fi

  # Unique wikilink targets in body (exclude embeds + attachments).
  UT=$(awk '
    {
      line = $0
      while (match(line, /\[\[[^]]+\]\]/)) {
        before = (RSTART > 1) ? substr(line, RSTART-1, 1) : ""
        inner  = substr(line, RSTART+2, RLENGTH-4)
        if (before != "!") {
          sub(/\|.*/, "", inner); sub(/#.*/, "", inner)
          if (inner !~ /\.(jpg|jpeg|png|gif|svg|pdf|webp|mp4|mov|canvas)$/) {
            targets[tolower(inner)] = 1
          }
        }
        line = substr(line, RSTART+RLENGTH)
      }
    }
    END { n=0; for (k in targets) n++; print n }
  ' "$f")
  UNIQUE_LINKS=$(( UNIQUE_LINKS + UT ))
done < <(find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -not -name "index.md" \
  -not -name "log.md")

SCORE=$(( (PAGES * 10) + (BREADCRUMBS * 5) + (UNIQUE_LINKS * 2) + (SPECIFIC_SOURCES * 3) + (WORDS / 100) ))
echo "$SCORE"
