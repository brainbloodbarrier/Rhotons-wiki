#!/usr/bin/env bash
# lib/autoresearch-guard.sh — validate structural integrity of a wiki.
# Requires bash >= 4 (associative arrays). On macOS, ensure Homebrew bash
# is on PATH before /bin/bash.
#
# Usage: lib/autoresearch-guard.sh <wiki-name> [options]
#
# Options:
#   --strict              Treat orphan + taxonomy checks as hard errors
#                         (default: warnings, only frontmatter + wikilinks fail)
#   --baseline <score>    Fail with exit 2 if current score < baseline
#   --format=json         Emit machine-readable JSON summary on stdout
#   --format=tsv          Emit one TSV summary row on stdout
#   --allowlist <path>    Override allowlist path
#                         (default: .config/guard-allowlist.json)
#   --no-allowlist        Ignore allowlist (raw counts)
#
# Exit: 0 pass, 1 hard errors, 2 score regression, 64/65/66/67 from
# resolve-wiki.sh. Violations are always printed to stderr as
# `LEVEL KIND: <detail>`. Summary goes to stdout in the requested format.
# Exit code is clamped (not violation count) to avoid POSIX mod-256
# wrap-around when violations exceed 255.
#
# Checks (Phase 6):
#   [hard]      frontmatter opens with `---` on line 1
#   [hard]      frontmatter contains title, category, tags
#   [hard]      every [[target]] resolves to a .md basename in the vault
#   [warn]      frontmatter contains summary, sources, created, updated
#   [warn|hard] every non-scaffolding page has >=1 incoming wikilink
#   [warn|hard] every tag appears in <vault>/_meta/taxonomy.md
#   [optional]  current score >= baseline (via --baseline)
#
# Allowlist schema (.config/guard-allowlist.json):
# {
#   "<wiki>": {
#     "orphans":              ["relative/path/to/page.md", ...],
#     "broken_wikilinks":     ["page.md -> [[missing-target]]", ...],
#     "taxonomy_violations":  ["page.md -> unknown-tag", ...],
#     "missing_frontmatter":  ["relative/path/to/page.md", ...]
#   }
# }

set -eu
# pipefail intentionally NOT set: some subshells (`sed | head`) emit
# SIGPIPE 141 on early close, which pipefail would surface as spurious.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WIKI_ARG=""
STRICT=0
FORMAT="text"
BASELINE=""
USE_ALLOWLIST=1
ALLOWLIST_PATH="$REPO_ROOT/.config/guard-allowlist.json"

while (( $# )); do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --format=json) FORMAT="json"; shift ;;
    --format=tsv)  FORMAT="tsv";  shift ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --baseline=*) BASELINE="${1#*=}"; shift ;;
    --allowlist) ALLOWLIST_PATH="${2:-}"; shift 2 ;;
    --no-allowlist) USE_ALLOWLIST=0; shift ;;
    -h|--help)
      sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*) echo "guard: unknown option '$1'" >&2; exit 64 ;;
    *)
      if [[ -z "$WIKI_ARG" ]]; then WIKI_ARG="$1"
      else echo "guard: unexpected positional '$1'" >&2; exit 64
      fi
      shift ;;
  esac
done

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-wiki.sh" "$WIKI_ARG"

VAULT="$REPO_ROOT/$WIKI_VAULT"
TAXONOMY="$VAULT/_meta/taxonomy.md"

VIOL_FRONTMATTER=""
VIOL_WIKILINKS=""
VIOL_ORPHANS=""
VIOL_TAXONOMY=""
VIOL_SOFT_FIELDS=""

allow_query() {
  local kind="$1"
  if (( ! USE_ALLOWLIST )) || [[ ! -f "$ALLOWLIST_PATH" ]]; then
    echo "[]"; return
  fi
  jq -c --arg w "$WIKI_NAME" --arg k "$kind" \
    '(.[$w][$k] // [])' "$ALLOWLIST_PATH" 2>/dev/null || echo "[]"
}

is_allowlisted() {
  local kind="$1" needle="$2"
  local list; list=$(allow_query "$kind")
  [[ "$list" == "[]" ]] && return 1
  jq -e --arg n "$needle" 'index($n)' <<< "$list" >/dev/null 2>&1
}

list_pages() {
  find "$VAULT" -name "*.md" \
    -not -path "*/.obsidian/*" \
    -not -path "*/.smart-env/*" \
    -not -name "index.md" \
    -not -name "log.md" \
    -print | sed "s|^$VAULT/||"
}

# Obsidian wikilink resolution is case-insensitive and treats spaces
# interchangeably with hyphens. Normalize basenames to a canonical key
# (lowercase, spaces→hyphens) to match that behavior.
normalize_target() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/\\$//; s/ /-/g'
}

declare -A PAGE_BASENAMES=()
while IFS= read -r rel; do
  base=$(basename "$rel" .md)
  key=$(normalize_target "$base")
  PAGE_BASENAMES["$key"]=1
done < <(list_pages)

declare -A ALLOWED_TAGS=()
HAS_TAXONOMY=0
if [[ -f "$TAXONOMY" ]]; then
  HAS_TAXONOMY=1
  while IFS= read -r tag; do
    [[ -n "$tag" ]] && ALLOWED_TAGS["$tag"]=1
  done < <(grep -oE '^- `[a-z0-9][a-z0-9-]*`' "$TAXONOMY" | sed 's/^- `//; s/`$//')
fi

declare -A INCOMING=()

while IFS= read -r rel; do
  f="$VAULT/$rel"
  HEAD_LINE=$(head -1 "$f" 2>/dev/null || true)
  if [[ "$HEAD_LINE" != "---" ]]; then
    is_allowlisted missing_frontmatter "$rel" \
      || VIOL_FRONTMATTER+="ERROR MISSING_FRONTMATTER: $rel"$'\n'
    continue
  fi

  FM=$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {exit} fm {print}' "$f")

  for field in title category tags; do
    grep -qE "^${field}:" <<< "$FM" \
      || VIOL_FRONTMATTER+="ERROR MISSING_${field}: $rel"$'\n'
  done
  for field in summary sources created updated; do
    grep -qE "^${field}:" <<< "$FM" \
      || VIOL_SOFT_FIELDS+="WARN MISSING_${field}: $rel"$'\n'
  done

  if (( HAS_TAXONOMY )); then
    TAGS=$(awk '
      /^tags:/ {
        inline=$0; sub(/^tags:[[:space:]]*/,"",inline)
        if (inline ~ /^\[/) { gsub(/[\[\],]/," ",inline); print inline; next }
        in_list=1; next
      }
      in_list {
        if (/^[^[:space:]]/) { in_list=0; next }
        if (/^[[:space:]]*-[[:space:]]+/) {
          sub(/^[[:space:]]*-[[:space:]]+/,""); print
        }
      }
    ' <<< "$FM" | tr -d '"' | tr -d "'")
    for t in $TAGS; do
      [[ -z "$t" ]] && continue
      if [[ -z "${ALLOWED_TAGS[$t]:-}" ]]; then
        entry="$rel -> $t"
        is_allowlisted taxonomy_violations "$entry" \
          || VIOL_TAXONOMY+="WARN UNKNOWN_TAG: $entry"$'\n'
      fi
    done
  fi

  # Extract wikilinks (exclude `![[...]]` embeds, which point at binary
  # attachments like figures/pdfs, not vault pages). Awk walks each line,
  # inspecting the byte before each `[[` match to decide embed vs. link.
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    clean=$(printf '%s' "$target" | sed 's/|.*$//; s/#.*$//')
    [[ -z "$clean" ]] && continue
    # Skip anything that looks like a binary attachment (has a file ext).
    case "$clean" in *.jpg|*.jpeg|*.png|*.gif|*.svg|*.pdf|*.webp|*.mp4|*.mov|*.canvas) continue ;; esac
    key=$(normalize_target "$clean")
    INCOMING["$key"]=$(( ${INCOMING["$key"]:-0} + 1 ))
    if [[ -z "${PAGE_BASENAMES[$key]:-}" ]]; then
      entry="$rel -> [[${clean}]]"
      is_allowlisted broken_wikilinks "$entry" \
        || VIOL_WIKILINKS+="ERROR BROKEN_WIKILINK: $entry"$'\n'
    fi
  done < <(awk '
    {
      line = $0
      while (match(line, /\[\[[^]]+\]\]/)) {
        before = (RSTART > 1) ? substr(line, RSTART-1, 1) : ""
        inner  = substr(line, RSTART+2, RLENGTH-4)
        if (before != "!") print inner
        line = substr(line, RSTART+RLENGTH)
      }
    }
  ' "$f")
done < <(list_pages)

while IFS= read -r rel; do
  case "$rel" in
    _meta/*|_canvases/*|_quizzes/*|_attachments/*) continue ;;
  esac
  base=$(basename "$rel" .md)
  key=$(normalize_target "$base")
  count=${INCOMING["$key"]:-0}
  if (( count == 0 )); then
    is_allowlisted orphans "$rel" \
      || VIOL_ORPHANS+="WARN ORPHAN: $rel"$'\n'
  fi
done < <(list_pages)

count_lines() {
  local s="$1"
  [[ -z "$s" ]] && { echo 0; return; }
  printf '%s' "$s" | grep -c . || true
}

FM_ERRORS=$(count_lines "$VIOL_FRONTMATTER")
WL_ERRORS=$(count_lines "$VIOL_WIKILINKS")
ORPHAN_WARN=$(count_lines "$VIOL_ORPHANS")
TAXO_WARN=$(count_lines "$VIOL_TAXONOMY")
SOFT_WARN=$(count_lines "$VIOL_SOFT_FIELDS")

HARD_ERRORS=$(( FM_ERRORS + WL_ERRORS ))
if (( STRICT )); then
  HARD_ERRORS=$(( HARD_ERRORS + ORPHAN_WARN + TAXO_WARN ))
fi

BASELINE_FAIL=0
CURRENT_SCORE=""
if [[ -n "$BASELINE" ]]; then
  CURRENT_SCORE=$("$SCRIPT_DIR/autoresearch-verify.sh" "$WIKI_NAME")
  (( CURRENT_SCORE < BASELINE )) && BASELINE_FAIL=1
fi

[[ -n "$VIOL_FRONTMATTER" ]] && printf '%s' "$VIOL_FRONTMATTER" >&2
[[ -n "$VIOL_WIKILINKS" ]]   && printf '%s' "$VIOL_WIKILINKS"   >&2
[[ -n "$VIOL_ORPHANS" ]]     && printf '%s' "$VIOL_ORPHANS"     >&2
[[ -n "$VIOL_TAXONOMY" ]]    && printf '%s' "$VIOL_TAXONOMY"    >&2
[[ -n "$VIOL_SOFT_FIELDS" ]] && printf '%s' "$VIOL_SOFT_FIELDS" >&2

case "$FORMAT" in
  json)
    jq -n \
      --arg wiki "$WIKI_NAME" \
      --argjson fm "$FM_ERRORS" \
      --argjson wl "$WL_ERRORS" \
      --argjson orphans "$ORPHAN_WARN" \
      --argjson taxonomy "$TAXO_WARN" \
      --argjson soft "$SOFT_WARN" \
      --argjson hard_errors "$HARD_ERRORS" \
      --argjson strict "$STRICT" \
      --argjson baseline_fail "$BASELINE_FAIL" \
      --arg baseline "${BASELINE:-}" \
      --arg current_score "${CURRENT_SCORE:-}" \
      '{
        wiki: $wiki,
        strict: ($strict == 1),
        checks: {
          frontmatter_errors:  $fm,
          broken_wikilinks:    $wl,
          orphan_pages:        $orphans,
          taxonomy_violations: $taxonomy,
          soft_field_warnings: $soft
        },
        hard_errors: $hard_errors,
        baseline:      (if $baseline      == "" then null else ($baseline|tonumber)      end),
        current_score: (if $current_score == "" then null else ($current_score|tonumber) end),
        baseline_fail: ($baseline_fail == 1),
        passed:        ($hard_errors == 0 and $baseline_fail == 0)
      }'
    ;;
  tsv)
    printf '%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n' \
      "$WIKI_NAME" "$FM_ERRORS" "$WL_ERRORS" "$ORPHAN_WARN" "$TAXO_WARN" \
      "$SOFT_WARN" "$HARD_ERRORS" "${BASELINE:-}" "${CURRENT_SCORE:-}"
    ;;
  text)
    echo "guard: $WIKI_NAME — frontmatter=$FM_ERRORS wikilinks=$WL_ERRORS orphans=$ORPHAN_WARN taxonomy=$TAXO_WARN soft=$SOFT_WARN strict=$STRICT hard=$HARD_ERRORS" >&2
    (( BASELINE_FAIL )) && echo "guard: SCORE REGRESSION — current=$CURRENT_SCORE baseline=$BASELINE" >&2
    ;;
esac

(( BASELINE_FAIL )) && exit 2
(( HARD_ERRORS > 0 )) && exit 1
exit 0
