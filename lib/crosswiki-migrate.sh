#!/usr/bin/env bash
# lib/crosswiki-migrate.sh — convert locally-unresolved [[basename]] wikilinks
# into markdown cross-links [basename](../<other-wiki>/vault/<path>) when the
# basename exists in exactly one other registered wiki.
#
# Purpose: restore the "self-contained vault" invariant (see issue #51) by
# migrating bare wikilinks that the origin vault cannot resolve locally but
# that do point at real pages in a sibling vault. After migration:
#   - The guard can enforce ERROR BROKEN_WIKILINK for any remaining [[...]].
#   - Obsidian renders the markdown link natively in a multi-vault workspace.
#   - crossmap.json pages_index is the source of truth for the mapping.
#
# Usage:
#   lib/crosswiki-migrate.sh <wiki> --dry-run
#   lib/crosswiki-migrate.sh <wiki> --apply [--report <file>]
#
# Flags:
#   --dry-run     Print the unified diff of intended changes. No writes.
#   --apply       Apply changes to the vault in place.
#   --report FILE Write a markdown report listing ambiguous basenames
#                 (present in >1 other wiki — skipped, need manual resolution)
#                 and genuinely unresolvable basenames (not in any wiki).
#
# Idempotent: a second run against the same vault produces zero changes.
#
# Skip rules per wikilink target:
#   - already resolves locally (PAGE_BASENAMES) → leave alone
#   - contains ':' (already a [[wiki:basename]] cross-wiki syntax) → leave alone
#   - has a file extension (embed/attachment) → leave alone
#   - multi-word target with spaces → leave alone (Obsidian aliases)
#
# Requires: jq, bash >= 4, perl (for safe in-place substitution).

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "crosswiki-migrate: requires bash >= 4 (brew install bash)" >&2
  exit 67
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CROSSMAP="$REPO_ROOT/crossmap.json"
CONFIG="$REPO_ROOT/.config/wikis.json"

WIKI_ARG=""
MODE=""
REPORT=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --report)  REPORT="__next__" ;;
    --report=*) REPORT="${arg#*=}" ;;
    --*) echo "crosswiki-migrate: unknown flag '$arg'" >&2; exit 64 ;;
    *)
      if [[ "$REPORT" == "__next__" ]]; then
        REPORT="$arg"
      elif [[ -z "$WIKI_ARG" ]]; then
        WIKI_ARG="$arg"
      else
        echo "crosswiki-migrate: unexpected positional '$arg'" >&2
        exit 64
      fi
      ;;
  esac
done

if [[ -z "$WIKI_ARG" ]]; then
  echo "crosswiki-migrate: wiki name required" >&2
  echo "usage: $0 <wiki> (--dry-run|--apply) [--report FILE]" >&2
  exit 64
fi
if [[ -z "$MODE" ]]; then
  echo "crosswiki-migrate: must specify --dry-run or --apply" >&2
  exit 64
fi
if [[ ! -f "$CROSSMAP" ]]; then
  echo "crosswiki-migrate: $CROSSMAP not found — run lib/crossmap-generate.sh first" >&2
  exit 66
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/resolve-wiki.sh" "$WIKI_ARG"

VAULT="$REPO_ROOT/$WIKI_VAULT"

normalize_target() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\\$//; s/ /-/g'
}

list_pages() {
  find "$VAULT" -name "*.md" \
    -not -path "*/.obsidian/*" \
    -not -path "*/.smart-env/*" \
    -not -name "index.md" \
    -not -name "log.md" \
    -print | sed "s|^$VAULT/||"
}

# Build local PAGE_BASENAMES (targets that already resolve in this vault — skip).
declare -A PAGE_BASENAMES=()
while IFS= read -r rel; do
  base=$(basename "$rel" .md)
  PAGE_BASENAMES["$(normalize_target "$base")"]=1
done < <(list_pages)

# Build cross-wiki resolution tables from crossmap.json pages_index.
# RESOLVES[key] = "wiki<tab>path" when key exists in exactly one *other* wiki.
# AMBIGUOUS[key] = "wiki1,wiki2,..." when the basename appears in >1 other wiki.
#
# jq emits one line per (key, wiki, path) triple across all *other* wikis.
# Aggregation is done in bash so we can count duplicates properly.
declare -A RESOLVES=()
declare -A AMBIGUOUS=()
declare -A _SEEN_COUNT=()
declare -A _FIRST_ENTRY=()
declare -A _WIKI_SET=()

while IFS=$'\t' read -r key wiki path; do
  [[ -z "$key" || -z "$wiki" || -z "$path" ]] && continue
  _SEEN_COUNT["$key"]=$(( ${_SEEN_COUNT["$key"]:-0} + 1 ))
  if [[ -z "${_FIRST_ENTRY[$key]:-}" ]]; then
    _FIRST_ENTRY["$key"]=$(printf '%s\t%s' "$wiki" "$path")
  fi
  # Append wiki to the set if not already present.
  existing="${_WIKI_SET[$key]:-}"
  if [[ "$existing" != *"$wiki"* ]]; then
    if [[ -z "$existing" ]]; then
      _WIKI_SET["$key"]="$wiki"
    else
      _WIKI_SET["$key"]="$existing,$wiki"
    fi
  fi
done < <(jq -r --arg w "$WIKI_ARG" '
  .pages_index | to_entries[] | .key as $k
  | .value[] | select(.wiki != $w)
  | [$k, .wiki, .path] | @tsv
' "$CROSSMAP")

for key in "${!_SEEN_COUNT[@]}"; do
  count="${_SEEN_COUNT[$key]}"
  wikis="${_WIKI_SET[$key]}"
  # Count distinct wikis via comma split.
  IFS=',' read -r -a wiki_arr <<< "$wikis"
  if (( ${#wiki_arr[@]} == 1 && count == 1 )); then
    RESOLVES["$key"]="${_FIRST_ENTRY[$key]}"
  else
    AMBIGUOUS["$key"]="$wikis"
  fi
done

# Per-file migration. Writes to STDOUT unified diff in --dry-run; edits
# in place in --apply.
TOTAL_CONVERTED=0
TOTAL_AMBIGUOUS=0
TOTAL_UNRESOLVED=0
MODIFIED_FILES=0

declare -A REPORT_AMBIGUOUS=()    # basename → wikis
declare -A REPORT_UNRESOLVED=()   # basename → count

while IFS= read -r rel; do
  f="$VAULT/$rel"
  [[ -f "$f" ]] || continue

  # Extract candidate basenames: non-embed [[...]] without ':', extension,
  # pipe, anchor, or spaces.
  declare -A SEEN=()
  converted_in_file=0
  updated_content=$(cat "$f")

  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    clean="${target%%|*}"
    clean="${clean%%#*}"
    case "$clean" in
      *:*) continue ;;
      *.jpg|*.jpeg|*.png|*.gif|*.svg|*.pdf|*.webp|*.mp4|*.mov|*.canvas) continue ;;
    esac
    [[ "$clean" == *" "* ]] && continue
    [[ -z "$clean" ]] && continue

    key=$(normalize_target "$clean")
    [[ -n "${PAGE_BASENAMES[$key]:-}" ]] && continue   # resolves locally
    [[ -n "${SEEN[$key]:-}" ]] && continue              # already processed for this file
    SEEN["$key"]=1

    if [[ -n "${AMBIGUOUS[$key]:-}" ]]; then
      REPORT_AMBIGUOUS["$key"]="${AMBIGUOUS[$key]}"
      TOTAL_AMBIGUOUS=$(( TOTAL_AMBIGUOUS + 1 ))
      continue
    fi

    if [[ -z "${RESOLVES[$key]:-}" ]]; then
      REPORT_UNRESOLVED["$key"]=$(( ${REPORT_UNRESOLVED[$key]:-0} + 1 ))
      TOTAL_UNRESOLVED=$(( TOTAL_UNRESOLVED + 1 ))
      continue
    fi

    # Resolvable: rewrite every occurrence of [[clean]] (and [[clean|alias]],
    # [[clean#anchor]]) in this file to a markdown cross-link. Preserve the
    # alias or anchor if present, else use the clean slug as the link text.
    IFS=$'\t' read -r tgt_wiki tgt_path <<< "${RESOLVES[$key]}"
    replacement_path="../${tgt_wiki}-wiki/vault/${tgt_path}"

    # Perl is used instead of sed because BSD sed on macOS treats bracket
    # sequences inconsistently for this pattern. Environment variables carry
    # the slug and path so the perl source is free of bash-level quoting
    # concerns. Three passes, each with a single bounded match.
    # Order matters: alias and anchor patterns must run before the bare
    # pattern so the bare pattern does not partially consume them.
    #
    # NOTE: `CLEAN=x perl ...` injects env into the perl process, but only
    # when perl is the command directly. With a pipe, we use a subshell so
    # the export scope spans the pipeline on both sides.
    export CLEAN="$clean"
    export REP="$replacement_path"
    updated_content=$(printf '%s' "$updated_content" | perl -0777 -pe '
      my $c = quotemeta($ENV{CLEAN});
      my $r = $ENV{REP};
      s/\[\[${c}\|([^\]]+)\]\]/[$1]($r)/g;
      s/\[\[${c}\#([^\]]+)\]\]/[$ENV{CLEAN}]($r#$1)/g;
      s/\[\[${c}\]\]/[$ENV{CLEAN}]($r)/g;
    ')
    converted_in_file=$(( converted_in_file + 1 ))
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

  unset SEEN

  if (( converted_in_file > 0 )); then
    MODIFIED_FILES=$(( MODIFIED_FILES + 1 ))
    TOTAL_CONVERTED=$(( TOTAL_CONVERTED + converted_in_file ))
    if [[ "$MODE" == "dry-run" ]]; then
      diff -u --label "a/$rel" --label "b/$rel" "$f" <(printf '%s' "$updated_content") || true
    else
      printf '%s' "$updated_content" > "$f"
    fi
  fi
done < <(list_pages)

# Summary to stderr.
{
  echo "crosswiki-migrate: $WIKI_ARG (mode=$MODE)"
  echo "  files modified:     $MODIFIED_FILES"
  echo "  basenames converted: $TOTAL_CONVERTED"
  echo "  ambiguous skipped:  ${#REPORT_AMBIGUOUS[@]} unique ($TOTAL_AMBIGUOUS occurrences)"
  echo "  unresolved skipped: ${#REPORT_UNRESOLVED[@]} unique ($TOTAL_UNRESOLVED occurrences)"
} >&2

if [[ -n "$REPORT" ]]; then
  {
    echo "# crosswiki-migrate report — wiki=$WIKI_ARG, mode=$MODE"
    echo ""
    echo "## Ambiguous basenames (present in >1 other wiki — manual resolution needed)"
    echo ""
    if (( ${#REPORT_AMBIGUOUS[@]} == 0 )); then
      echo "_None._"
    else
      for key in "${!REPORT_AMBIGUOUS[@]}"; do
        printf -- "- \`%s\` → %s\n" "$key" "${REPORT_AMBIGUOUS[$key]}"
      done | sort
    fi
    echo ""
    echo "## Unresolved basenames (not in any registered wiki — genuine broken links)"
    echo ""
    if (( ${#REPORT_UNRESOLVED[@]} == 0 )); then
      echo "_None._"
    else
      for key in "${!REPORT_UNRESOLVED[@]}"; do
        printf -- "- \`%s\` (%d occurrences)\n" "$key" "${REPORT_UNRESOLVED[$key]}"
      done | sort
    fi
  } > "$REPORT"
  echo "crosswiki-migrate: report written to $REPORT" >&2
fi
