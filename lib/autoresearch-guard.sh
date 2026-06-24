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

set -euo pipefail
# pipefail is safe here: the only pipelines that could spuriously fail on
# zero grep matches (e.g. taxonomy scan on line ~158) use explicit `|| true`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WIKI_ARG=""
STRICT=0
FORMAT="text"
BASELINE=""
USE_ALLOWLIST=1
QUALITY=0
ALLOWLIST_PATH="$REPO_ROOT/.config/guard-allowlist.json"

while (( $# )); do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --quality) QUALITY=1; shift ;;
    --format=json) FORMAT="json"; shift ;;
    --format=tsv)  FORMAT="tsv";  shift ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --baseline=*) BASELINE="${1#*=}"; shift ;;
    --allowlist) ALLOWLIST_PATH="${2:-}"; shift 2 ;;
    --no-allowlist) USE_ALLOWLIST=0; shift ;;
    -h|--help)
      sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//'
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
VIOL_VAGUE_SOURCES=""
VIOL_MISSING_BREADCRUMBS=""
VIOL_MANIFEST_UNANCHORED=""
VIOL_CROSS_WIKI_WARN=""    # WARN CROSS_WIKI_REF — sanctioned [[wiki:basename]] that resolves
VIOL_CROSS_WIKI_BROKEN=""  # ERROR BROKEN_CROSS_WIKI_REF — [[wiki:basename]] where wiki/basename missing
VIOL_CROSS_LINK_BROKEN=""  # ERROR BROKEN_CROSS_LINK — markdown link to ../<wiki>-wiki/vault/... unresolved

# Typed semantic relations; presence of >=1 counts as a breadcrumb.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/constants.sh"

# Vault subtrees that MUST be anchored to a source PDF in .manifest.json
# when --quality is on. Synthesis, concept, reference, meta pages are
# exempt (they are allowed to be derivative by design).
MANIFEST_REQUIRED_RE='^(procedures|approaches|techniques)/'

MANIFEST_PATH="$VAULT/.manifest.json"

allow_query() {
  local kind="$1"
  if (( ! USE_ALLOWLIST )) || [[ ! -f "$ALLOWLIST_PATH" ]]; then
    echo "[]"; return
  fi
  local result
  if ! result=$(jq -c --arg w "$WIKI_NAME" --arg k "$kind" \
      '(.[$w][$k] // [])' "$ALLOWLIST_PATH" 2>&1); then
    echo "guard: allowlist parse error ($ALLOWLIST_PATH): $result" >&2
    echo "[]"; return
  fi
  echo "$result"
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
# interchangeably with hyphens. normalize_target (from constants.sh, sourced
# above) maps basenames to a canonical key (lowercase, spaces→hyphens) to
# match that behavior.

declare -A PAGE_BASENAMES=()
while IFS= read -r rel; do
  base=$(basename "$rel" .md)
  key=$(normalize_target "$base")
  PAGE_BASENAMES["$key"]=1
done < <(list_pages)

# Cross-wiki resolution: load pages_index from crossmap.json if present.
# CROSSWIKI_BASENAMES is kept for backward-compat consumers but the guard
# itself no longer uses it to silence ERROR BROKEN_WIKILINK — see PR #51.
#
# CROSSWIKI_BY_WIKI is the map used by the [[wiki:basename]] validation:
#   key = "<wiki>:<normalized-basename>", value = 1
# This is populated in sync with pages_index so the guard can confirm a
# given [[rhoton:corpus-callosum]] target genuinely exists in rhoton.
declare -A CROSSWIKI_BASENAMES=()
declare -A CROSSWIKI_BY_WIKI=()
_CROSSMAP="$REPO_ROOT/crossmap.json"
if [[ -f "$_CROSSMAP" ]] && jq -e '.pages_index' "$_CROSSMAP" >/dev/null 2>&1; then
  while IFS= read -r cw_key; do
    [[ -n "$cw_key" ]] && CROSSWIKI_BASENAMES["$cw_key"]=1
  done < <(jq -r --arg w "$WIKI_NAME" \
    '.pages_index | to_entries[] | select(any(.value[]; .wiki != $w)) | .key' \
    "$_CROSSMAP" 2>/dev/null || true)
  while IFS=$'\t' read -r cw_wiki cw_key; do
    [[ -n "$cw_wiki" && -n "$cw_key" ]] && CROSSWIKI_BY_WIKI["$cw_wiki:$cw_key"]=1
  done < <(jq -r '.pages_index | to_entries[] | .key as $k | .value[] | [.wiki, $k] | @tsv' \
    "$_CROSSMAP" 2>/dev/null || true)
fi

# Registered wiki names (used to validate [[wiki:...]] and ../<wiki>-wiki/... prefixes).
declare -A VALID_WIKIS=()
while IFS= read -r _vw; do
  [[ -n "$_vw" ]] && VALID_WIKIS["$_vw"]=1
done < <(jq -r '.wikis | keys[]' "$REPO_ROOT/.config/wikis.json" 2>/dev/null || true)

declare -A ALLOWED_TAGS=()
HAS_TAXONOMY=0
if [[ -f "$TAXONOMY" ]]; then
  HAS_TAXONOMY=1
  while IFS= read -r tag; do
    [[ -n "$tag" ]] && ALLOWED_TAGS["$tag"]=1
  done < <(grep -oE '^- `[a-z0-9][a-z0-9-]*`' "$TAXONOMY" 2>/dev/null | sed 's/^- `//; s/`$//' || true)
fi

declare -A INCOMING=()

while IFS= read -r rel; do
  f="$VAULT/$rel"
  if ! HEAD_LINE=$(head -1 "$f" 2>/dev/null); then
    VIOL_FRONTMATTER+="ERROR UNREADABLE: $rel"$'\n'
    continue
  fi
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

  if (( QUALITY )); then
    # Check 1: vague sources — the sources: field exists but its value has
    # no chapter/page/section specificity (just an author or domain name).
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
    ' <<< "$FM")
    if [[ -n "$SOURCES_VALUE" ]]; then
      # Vague = no digit (chapter/page/year) AND length < 40 chars per line.
      has_specific=0
      while IFS= read -r srcline; do
        [[ -z "$srcline" ]] && continue
        if [[ "$srcline" =~ [0-9] ]] || (( ${#srcline} >= 40 )); then
          has_specific=1
          break
        fi
      done <<< "$SOURCES_VALUE"
      if (( ! has_specific )); then
        entry="$rel"
        is_allowlisted vague_sources "$entry" \
          || VIOL_VAGUE_SOURCES+="WARN VAGUE_SOURCES: $entry"$'\n'
      fi
    fi

    # Check 2: missing typed breadcrumb — non-scaffolding pages should have
    # >=1 typed relation. Scaffolding (_meta/_canvases/_quizzes/_attachments/
    # index/log) is exempt from this check.
    case "$rel" in
      _meta/*|_canvases/*|_quizzes/*|_attachments/*) ;;
      index.md|log.md) ;;
      *)
        if ! grep -qE "$BREADCRUMB_RE" <<< "$FM"; then
          is_allowlisted missing_breadcrumbs "$rel" \
            || VIOL_MISSING_BREADCRUMBS+="WARN MISSING_BREADCRUMB: $rel"$'\n'
        fi
        ;;
    esac

    # Check 3: manifest anchoring — pages under procedures/approaches/
    # techniques/ must appear as a value of .sources[*].wiki_page in the
    # vault manifest. Missing manifest file is fatal to the check (skip).
    if [[ "$rel" =~ $MANIFEST_REQUIRED_RE ]] && [[ -f "$MANIFEST_PATH" ]]; then
      if ! jq -e --arg p "$rel" \
          '[.sources[]?.wiki_page] | index($p)' "$MANIFEST_PATH" \
          >/dev/null 2>&1; then
        is_allowlisted manifest_unanchored "$rel" \
          || VIOL_MANIFEST_UNANCHORED+="WARN MANIFEST_UNANCHORED: $rel"$'\n'
      fi
    fi
  fi

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

    # Sanctioned cross-wiki syntax: [[wiki:basename]]
    # Accepted if `wiki` is a registered wiki and `basename` exists in its
    # pages_index. Emits WARN (not error) — Obsidian does not render this
    # natively, but the guard validates the intent.
    if [[ "$clean" == *:* && "$clean" != *" "* ]]; then
      cw_wiki="${clean%%:*}"
      cw_base="${clean#*:}"
      if [[ "$cw_wiki" =~ ^[a-z][a-z0-9-]*$ ]]; then
        cw_key=$(normalize_target "$cw_base")
        entry="$rel -> [[${clean}]]"
        if [[ -z "${VALID_WIKIS[$cw_wiki]:-}" ]]; then
          is_allowlisted broken_cross_wiki_refs "$entry" \
            || VIOL_CROSS_WIKI_BROKEN+="ERROR BROKEN_CROSS_WIKI_REF: $entry (wiki '$cw_wiki' not in registry)"$'\n'
        elif [[ -n "${CROSSWIKI_BY_WIKI[$cw_wiki:$cw_key]:-}" ]]; then
          is_allowlisted cross_wiki_refs "$entry" \
            || VIOL_CROSS_WIKI_WARN+="WARN CROSS_WIKI_REF: $entry"$'\n'
        else
          is_allowlisted broken_cross_wiki_refs "$entry" \
            || VIOL_CROSS_WIKI_BROKEN+="ERROR BROKEN_CROSS_WIKI_REF: $entry (basename not in wiki '$cw_wiki')"$'\n'
        fi
        continue
      fi
    fi

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

  # Cross-vault markdown links: [text](../<wiki>-wiki/vault/<path>.md)
  # These are the recommended form for cross-wiki references because
  # Obsidian resolves relative paths natively inside a monorepo workspace.
  while IFS= read -r mdlink; do
    [[ -z "$mdlink" ]] && continue
    if [[ "$mdlink" =~ ^\.\./([a-z][a-z0-9-]*)-wiki/vault/(.+\.md)$ ]]; then
      cv_wiki="${BASH_REMATCH[1]}"
      cv_path="${BASH_REMATCH[2]}"
      # Strip anchor (#section) if present.
      cv_path="${cv_path%%#*}"
      target_abs="$REPO_ROOT/${cv_wiki}-wiki/vault/$cv_path"
      entry="$rel -> $mdlink"
      if [[ -z "${VALID_WIKIS[$cv_wiki]:-}" ]]; then
        is_allowlisted broken_cross_links "$entry" \
          || VIOL_CROSS_LINK_BROKEN+="ERROR BROKEN_CROSS_LINK: $entry (wiki '$cv_wiki' not in registry)"$'\n'
      elif [[ ! -f "$target_abs" ]]; then
        is_allowlisted broken_cross_links "$entry" \
          || VIOL_CROSS_LINK_BROKEN+="ERROR BROKEN_CROSS_LINK: $entry (file not found)"$'\n'
      fi
    fi
  done < <(awk '
    {
      line = $0
      while (match(line, /\]\(\.\.\/[^)]+\)/)) {
        inner = substr(line, RSTART+2, RLENGTH-3)
        print inner
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
VAGUE_WARN=$(count_lines "$VIOL_VAGUE_SOURCES")
MISSING_BC_WARN=$(count_lines "$VIOL_MISSING_BREADCRUMBS")
UNANCHORED_WARN=$(count_lines "$VIOL_MANIFEST_UNANCHORED")
CROSS_WIKI_WARN=$(count_lines "$VIOL_CROSS_WIKI_WARN")
CROSS_WIKI_BROKEN_ERR=$(count_lines "$VIOL_CROSS_WIKI_BROKEN")
CROSS_LINK_BROKEN_ERR=$(count_lines "$VIOL_CROSS_LINK_BROKEN")

HARD_ERRORS=$(( FM_ERRORS + WL_ERRORS + CROSS_WIKI_BROKEN_ERR + CROSS_LINK_BROKEN_ERR ))
if (( STRICT )); then
  HARD_ERRORS=$(( HARD_ERRORS + ORPHAN_WARN + TAXO_WARN ))
  if (( QUALITY )); then
    HARD_ERRORS=$(( HARD_ERRORS + VAGUE_WARN + MISSING_BC_WARN + UNANCHORED_WARN ))
  fi
fi

BASELINE_FAIL=0
CURRENT_SCORE=""
if [[ -n "$BASELINE" ]]; then
  CURRENT_SCORE=$("$SCRIPT_DIR/autoresearch-verify.sh" "$WIKI_NAME")
  (( CURRENT_SCORE < BASELINE )) && BASELINE_FAIL=1
fi

[[ -n "$VIOL_FRONTMATTER" ]]         && printf '%s' "$VIOL_FRONTMATTER"         >&2
[[ -n "$VIOL_WIKILINKS" ]]           && printf '%s' "$VIOL_WIKILINKS"           >&2
[[ -n "$VIOL_ORPHANS" ]]             && printf '%s' "$VIOL_ORPHANS"             >&2
[[ -n "$VIOL_TAXONOMY" ]]            && printf '%s' "$VIOL_TAXONOMY"            >&2
[[ -n "$VIOL_SOFT_FIELDS" ]]         && printf '%s' "$VIOL_SOFT_FIELDS"         >&2
[[ -n "$VIOL_VAGUE_SOURCES" ]]       && printf '%s' "$VIOL_VAGUE_SOURCES"       >&2
[[ -n "$VIOL_MISSING_BREADCRUMBS" ]] && printf '%s' "$VIOL_MISSING_BREADCRUMBS" >&2
[[ -n "$VIOL_MANIFEST_UNANCHORED" ]] && printf '%s' "$VIOL_MANIFEST_UNANCHORED" >&2
[[ -n "$VIOL_CROSS_WIKI_WARN" ]]     && printf '%s' "$VIOL_CROSS_WIKI_WARN"     >&2
[[ -n "$VIOL_CROSS_WIKI_BROKEN" ]]   && printf '%s' "$VIOL_CROSS_WIKI_BROKEN"   >&2
[[ -n "$VIOL_CROSS_LINK_BROKEN" ]]   && printf '%s' "$VIOL_CROSS_LINK_BROKEN"   >&2

case "$FORMAT" in
  json)
    jq -n \
      --arg wiki "$WIKI_NAME" \
      --argjson fm "$FM_ERRORS" \
      --argjson wl "$WL_ERRORS" \
      --argjson orphans "$ORPHAN_WARN" \
      --argjson taxonomy "$TAXO_WARN" \
      --argjson soft "$SOFT_WARN" \
      --argjson vague "$VAGUE_WARN" \
      --argjson missing_bc "$MISSING_BC_WARN" \
      --argjson unanchored "$UNANCHORED_WARN" \
      --argjson cw_warn "$CROSS_WIKI_WARN" \
      --argjson cw_broken "$CROSS_WIKI_BROKEN_ERR" \
      --argjson cl_broken "$CROSS_LINK_BROKEN_ERR" \
      --argjson hard_errors "$HARD_ERRORS" \
      --argjson strict "$STRICT" \
      --argjson quality "$QUALITY" \
      --argjson baseline_fail "$BASELINE_FAIL" \
      --arg baseline "${BASELINE:-}" \
      --arg current_score "${CURRENT_SCORE:-}" \
      '{
        wiki: $wiki,
        strict:  ($strict  == 1),
        quality: ($quality == 1),
        checks: {
          frontmatter_errors:    $fm,
          broken_wikilinks:      $wl,
          orphan_pages:          $orphans,
          taxonomy_violations:   $taxonomy,
          soft_field_warnings:   $soft,
          vague_sources:         $vague,
          missing_breadcrumbs:   $missing_bc,
          manifest_unanchored:   $unanchored,
          cross_wiki_refs:       $cw_warn,
          broken_cross_wiki_refs: $cw_broken,
          broken_cross_links:    $cl_broken
        },
        hard_errors: $hard_errors,
        baseline:      (if $baseline      == "" then null else ($baseline|tonumber)      end),
        current_score: (if $current_score == "" then null else ($current_score|tonumber) end),
        baseline_fail: ($baseline_fail == 1),
        passed:        ($hard_errors == 0 and $baseline_fail == 0)
      }'
    ;;
  tsv)
    printf '%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n' \
      "$WIKI_NAME" "$FM_ERRORS" "$WL_ERRORS" "$ORPHAN_WARN" "$TAXO_WARN" \
      "$SOFT_WARN" "$VAGUE_WARN" "$MISSING_BC_WARN" "$UNANCHORED_WARN" \
      "$CROSS_WIKI_WARN" "$CROSS_WIKI_BROKEN_ERR" "$CROSS_LINK_BROKEN_ERR" \
      "$HARD_ERRORS" "${BASELINE:-}" "${CURRENT_SCORE:-}"
    ;;
  text)
    echo "guard: $WIKI_NAME — frontmatter=$FM_ERRORS wikilinks=$WL_ERRORS orphans=$ORPHAN_WARN taxonomy=$TAXO_WARN soft=$SOFT_WARN strict=$STRICT hard=$HARD_ERRORS" >&2
    if (( CROSS_WIKI_WARN + CROSS_WIKI_BROKEN_ERR + CROSS_LINK_BROKEN_ERR > 0 )); then
      echo "guard: $WIKI_NAME — [cross-wiki] refs=$CROSS_WIKI_WARN broken_refs=$CROSS_WIKI_BROKEN_ERR broken_links=$CROSS_LINK_BROKEN_ERR" >&2
    fi
    if (( QUALITY )); then
      echo "guard: $WIKI_NAME — [quality] vague_sources=$VAGUE_WARN missing_breadcrumbs=$MISSING_BC_WARN manifest_unanchored=$UNANCHORED_WARN" >&2
    fi
    (( BASELINE_FAIL )) && echo "guard: SCORE REGRESSION — current=$CURRENT_SCORE baseline=$BASELINE" >&2
    ;;
esac

(( BASELINE_FAIL )) && exit 2
(( HARD_ERRORS > 0 )) && exit 1
exit 0
