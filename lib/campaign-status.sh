#!/usr/bin/env bash
# lib/campaign-status.sh — per-subdir progress dashboard for a wiki campaign.
#
# Usage: lib/campaign-status.sh <wiki-name> [campaign-id]
#   <wiki-name>   required. Matches a key in .config/wikis.json.
#   [campaign-id] optional. Currently informational only (printed in header).
#
# Output (stdout, TSV with header):
#   subdir  pdfs_source  pdfs_ingested  pages_in_vault  avg_breadcrumbs  target_met
#
# Target per subdir = at least ONE vault page that is (a) anchored in
# .manifest.json, (b) has >=1 typed breadcrumb, (c) has >=5 distinct wikilinks.
#
# Breadcrumb relations recognized:
#   parent, child, branch-of, branches, innervates, innervated-by,
#   traverses, traversed-by, approach-to, approached-via, drains-to, drained-by.
#
# Exit: 0 on success; 64/65/66/67 propagated from resolve-wiki.sh.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-wiki.sh" "${1:-}"
CAMPAIGN_ID="${2:-}"

VAULT="$REPO_ROOT/$WIKI_VAULT"
MANIFEST="$VAULT/.manifest.json"
SOURCES="${WIKI_SOURCES:-}"

if [[ -z "$SOURCES" || ! -d "$SOURCES" ]]; then
  echo "campaign-status: WIKI_SOURCES not a directory: '$SOURCES'" >&2
  exit 66
fi

BREADCRUMB_RE='^(parent|child|branch-of|branches|innervates|innervated-by|traverses|traversed-by|approach-to|approached-via|drains-to|drained-by):'

# Relation-frontmatter detection for one page. Prints 1 if >=1 typed breadcrumb
# present, else 0.
page_has_breadcrumb() {
  awk -v re="$BREADCRUMB_RE" '
    NR==1 && /^---$/ { fm=1; next }
    fm && /^---$/ { exit }
    fm && $0 ~ re { found=1 }
    END { print (found ? 1 : 0) }
  ' "$1"
}

# Count distinct wikilink targets on a page (excluding ![[embeds]] and attachments).
page_unique_wikilinks() {
  awk '
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
  ' "$1"
}

# Does this page appear as a value of .sources[*].wiki_page in the manifest?
page_in_manifest() {
  local rel="$1"
  [[ ! -f "$MANIFEST" ]] && { echo 0; return; }
  jq -e --arg p "$rel" '[.sources[]?.wiki_page] | index($p)' "$MANIFEST" \
    >/dev/null 2>&1 && echo 1 || echo 0
}

# Per-subdir stats. A "subdir" is a top-level dir under $SOURCES; "ingested PDFs"
# are sources whose key begins with "<subdir>/". "Pages in vault" for a subdir
# are all wiki_page values whose source key begins with "<subdir>/".
emit_row() {
  local subdir="$1"
  local pdfs_source ingested pages_target_met=0 avg_bc="0.0"
  pdfs_source=$(find "$SOURCES/$subdir" -maxdepth 1 -name '*.pdf' 2>/dev/null \
    | wc -l | tr -d ' ')

  local manifest_pages=()
  if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && manifest_pages+=("$p")
    done < <(jq -r --arg s "$subdir/" \
      '.sources | to_entries[] | select(.key | startswith($s)) | .value.wiki_page // empty' \
      "$MANIFEST" 2>/dev/null)
  fi
  ingested=${#manifest_pages[@]}

  local total_bc=0 pages_in_vault=0
  for rel in "${manifest_pages[@]}"; do
    local f="$VAULT/$rel"
    [[ ! -f "$f" ]] && continue
    pages_in_vault=$(( pages_in_vault + 1 ))
    local bc wl
    bc=$(page_has_breadcrumb "$f")
    wl=$(page_unique_wikilinks "$f")
    total_bc=$(( total_bc + bc ))
    if (( bc == 1 && wl >= 5 )); then
      pages_target_met=$(( pages_target_met + 1 ))
    fi
  done

  if (( pages_in_vault > 0 )); then
    avg_bc=$(awk -v t="$total_bc" -v n="$pages_in_vault" 'BEGIN{printf "%.2f", t/n}')
  fi

  local target_met="no"
  (( pages_target_met >= 1 )) && target_met="yes"

  printf '%s\t%d\t%d\t%d\t%s\t%s\n' \
    "$subdir" "$pdfs_source" "$ingested" "$pages_in_vault" "$avg_bc" "$target_met"
}

echo "# campaign-status: wiki=$WIKI_NAME campaign=${CAMPAIGN_ID:-none} head=$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
printf 'subdir\tpdfs_source\tpdfs_ingested\tpages_in_vault\tavg_breadcrumbs\ttarget_met\n'

for d in "$SOURCES"/*/; do
  [[ -d "$d" ]] || continue
  emit_row "$(basename "$d")"
done
