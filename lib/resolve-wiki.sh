#!/bin/bash
# lib/resolve-wiki.sh — resolve a wiki name from .config/wikis.json into
# environment variables usable by autoresearch scripts and skills.
#
# Usage:
#   source lib/resolve-wiki.sh <wiki-name>
#
# Exports (nullable fields export as empty strings when null in JSON):
#   WIKI_NAME          - the wiki name argument
#   WIKI_VAULT         - relative path to Obsidian vault (validated to exist)
#   WIKI_SOURCES       - path to raw source documents or ""
#   WIKI_RAW_SOURCE    - absolute path to raw source artifact or ""
#   WIKI_EXTRACTIONS   - relative path to extractions dir or ""
#   WIKI_TOOLS         - relative path to tooling dir or ""
#   WIKI_DOMAIN        - short domain descriptor
#   WIKI_OUTPUT        - .autoresearch/<wiki-name> (created if missing)
#
# Exit codes (also sets status when sourced):
#   0   - success
#   64  - wiki name argument missing (EX_USAGE)
#   65  - wiki name not found in registry (EX_DATAERR)
#   66  - registry file or vault directory not found (EX_NOINPUT)
#   67  - jq not installed (EX_NOUSER-adjacent; custom)
#
# This script is safe to `source` repeatedly; it re-resolves on each call.

set -euo pipefail

# Resolve repo root: walk up from PWD until we find .config/wikis.json.
# This works under both bash and zsh and regardless of how the script is invoked.
__find_repo_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.config/wikis.json" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

__RESOLVE_WIKI_ROOT=$(__find_repo_root) || {
  echo "resolve-wiki: .config/wikis.json not found in PWD or any parent" >&2
  return 66 2>/dev/null || exit 66
}

WIKI_NAME="${1:-}"
if [[ -z "$WIKI_NAME" ]]; then
  echo "resolve-wiki: wiki name required (usage: source lib/resolve-wiki.sh <wiki-name>)" >&2
  return 64 2>/dev/null || exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "resolve-wiki: jq is required but not installed (brew install jq)" >&2
  return 67 2>/dev/null || exit 67
fi

CONFIG="$__RESOLVE_WIKI_ROOT/.config/wikis.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "resolve-wiki: $CONFIG not found" >&2
  return 66 2>/dev/null || exit 66
fi

if ! jq empty "$CONFIG" 2>/dev/null; then
  echo "resolve-wiki: $CONFIG is not valid JSON — run: jq empty $CONFIG" >&2
  return 66 2>/dev/null || exit 66
fi
if ! jq -e ".wikis.\"$WIKI_NAME\"" "$CONFIG" >/dev/null 2>&1; then
  AVAILABLE=$(jq -r '.wikis | keys | join(", ")' "$CONFIG")
  echo "resolve-wiki: unknown wiki '$WIKI_NAME' (available: $AVAILABLE)" >&2
  return 65 2>/dev/null || exit 65
fi

export WIKI_NAME
WIKI_VAULT=$(jq -r ".wikis.\"$WIKI_NAME\".vault" "$CONFIG")
WIKI_SOURCES=$(jq -r ".wikis.\"$WIKI_NAME\".sources // empty" "$CONFIG")
WIKI_RAW_SOURCE=$(jq -r ".wikis.\"$WIKI_NAME\".raw_source // empty" "$CONFIG")
WIKI_EXTRACTIONS=$(jq -r ".wikis.\"$WIKI_NAME\".extractions // empty" "$CONFIG")
WIKI_TOOLS=$(jq -r ".wikis.\"$WIKI_NAME\".tools // empty" "$CONFIG")
WIKI_DOMAIN=$(jq -r ".wikis.\"$WIKI_NAME\".domain // empty" "$CONFIG")
OUTPUT_DIR=$(jq -r '.output_dir // ".autoresearch"' "$CONFIG")
WIKI_OUTPUT="$OUTPUT_DIR/$WIKI_NAME"

# Validate vault exists (resolved from repo root).
if [[ ! -d "$__RESOLVE_WIKI_ROOT/$WIKI_VAULT" ]]; then
  echo "resolve-wiki: vault '$WIKI_VAULT' does not exist at $__RESOLVE_WIKI_ROOT/$WIKI_VAULT" >&2
  return 66 2>/dev/null || exit 66
fi

mkdir -p "$__RESOLVE_WIKI_ROOT/$WIKI_OUTPUT"

export WIKI_VAULT WIKI_SOURCES WIKI_RAW_SOURCE WIKI_EXTRACTIONS \
       WIKI_TOOLS WIKI_DOMAIN WIKI_OUTPUT
