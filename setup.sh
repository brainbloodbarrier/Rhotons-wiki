#!/bin/bash
# setup.sh — configures skill discovery for all supported AI agents.
#
# Usage:
#   bash setup.sh           # install / update symlinks
#   bash setup.sh --verify  # check current state; no modifications
#
# What it does:
#   1. Requires jq (multi-wiki registry parsing). Installs nothing; aborts
#      with install instructions if missing.
#   2. Creates .env from .env.example (if not present).
#   3. Prompts for vault path if unset and writes ~/.obsidian-wiki/config.
#   4. Symlinks .skills/* into each agent's expected skills directory:
#        - .claude/skills/      (Claude Code, workspace)
#        - .cursor/skills/      (Cursor)
#        - .windsurf/skills/    (Windsurf)
#        - .agents/skills/      (Antigravity / workspace-scoped generic agents)
#        - ~/.claude/skills/    (Claude Code, global: wiki-update, wiki-query)
#        - ~/.gemini/antigravity/skills/  (Gemini)
#        - ~/.codex/skills/     (Codex)
#        - ~/.agents/skills/    (OpenClaw, OpenCode, Factory Droid, …)
#
# Idempotence contract: running this script twice produces identical output.
# Every symlink operation goes through ensure_symlink() which is a no-op when
# the link already points at the correct source.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.skills"

VERIFY_MODE=0
if [[ "${1:-}" == "--verify" ]]; then
  VERIFY_MODE=1
fi

# ensure_symlink <src> <dst>
# Idempotent symlink creation. `src` is taken as-given (relative or absolute)
# so callers can choose the appropriate flavor:
#   - workspace-scoped links (under the repo): pass a RELATIVE src so the
#     symlink survives cloning to any host. Workspace symlinks are tracked
#     in git and MUST be portable.
#   - global/home-scoped links (under $HOME): pass an ABSOLUTE src. Global
#     links are per-host and not tracked.
# Exit codes:
#   0  - symlink is correct (was already or was just created/fixed)
#   1  - destination exists and is not a symlink (aborted to avoid data loss)
#   2  - source does not exist (aborted)
ensure_symlink() {
  local src="$1"
  local dst="$2"
  local resolve_src
  if [[ "$src" = /* ]]; then
    resolve_src="$src"
  else
    resolve_src="$(cd "$(dirname "$dst")" && cd "$(dirname "$src")" && pwd)/$(basename "$src")"
  fi
  if [[ ! -e "$resolve_src" ]]; then
    echo "  ERROR: source '$src' (resolved: $resolve_src) does not exist" >&2
    return 2
  fi
  if [[ -L "$dst" ]]; then
    local actual
    actual=$(readlink "$dst")
    if [[ "$actual" == "$src" ]]; then
      return 0
    fi
    if (( VERIFY_MODE )); then
      echo "  STALE: $dst -> $actual (expected $src)" >&2
      return 1
    fi
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    echo "  ERROR: $dst exists and is not a symlink" >&2
    return 1
  fi
  if (( VERIFY_MODE )); then
    echo "  MISSING: $dst" >&2
    return 1
  fi
  ln -s "$src" "$dst"
}

# link_all_skills_into <target_dir> <label> [relative]
# When the third argument is "relative", workspace-scoped relative paths are
# used for each symlink source (portable across clones). Otherwise absolute
# paths are used (required for global/home-scoped directories).
link_all_skills_into() {
  local target_dir="$1"
  local label="$2"
  local mode="${3:-absolute}"
  if (( ! VERIFY_MODE )); then
    mkdir -p "$target_dir"
  elif [[ ! -d "$target_dir" ]]; then
    echo "  MISSING: $target_dir" >&2
    return 1
  fi
  local failed=0
  for skill in "$SKILLS_DIR"/*/; do
    local skill_name
    skill_name="$(basename "$skill")"
    local src
    if [[ "$mode" == "relative" ]]; then
      src="../../.skills/$skill_name"
    else
      src="${skill%/}"
    fi
    ensure_symlink "$src" "$target_dir/$skill_name" || failed=1
  done
  if (( failed )); then
    echo "⚠️   $label has symlink issues"
    return 1
  fi
  echo "✅  $label"
  return 0
}

echo ""
echo "╔══════════════════════════════════════════════════╗"
if (( VERIFY_MODE )); then
  echo "║         obsidian-wiki — Agent Setup (verify)     ║"
else
  echo "║         obsidian-wiki — Agent Setup              ║"
fi
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Step 0: required tools ─────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "❌  jq is required but not installed." >&2
  echo "    Install: brew install jq   (macOS)" >&2
  echo "             apt install jq    (Debian/Ubuntu)" >&2
  echo "             pacman -S jq      (Arch)" >&2
  exit 1
fi
echo "✅  jq found: $(jq --version)"

# ── Step 1: .env ──────────────────────────────────────────────
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  if (( VERIFY_MODE )); then
    echo "⚠️   .env missing (would be copied from .env.example on install)"
  else
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "✅  Created .env from .env.example"
    echo "    → Edit .env and set OBSIDIAN_VAULT_PATH before using skills."
  fi
else
  echo "✅  .env already exists"
fi

# ── Step 1b: ~/.obsidian-wiki/config ──────────────────────────
GLOBAL_CONFIG_DIR="$HOME/.obsidian-wiki"
GLOBAL_CONFIG="$GLOBAL_CONFIG_DIR/config"

VAULT_PATH=""
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  VAULT_PATH=$(grep -E '^OBSIDIAN_VAULT_PATH=' "$SCRIPT_DIR/.env" | cut -d'=' -f2-)
fi

if (( VERIFY_MODE )); then
  if [[ -z "$VAULT_PATH" ]] || [[ "$VAULT_PATH" == "/path/to/your/vault" ]]; then
    echo "⚠️   OBSIDIAN_VAULT_PATH is empty or a placeholder in .env"
  else
    echo "✅  OBSIDIAN_VAULT_PATH=$VAULT_PATH"
  fi
  if [[ -f "$GLOBAL_CONFIG" ]]; then
    echo "✅  $GLOBAL_CONFIG exists"
  else
    echo "⚠️   $GLOBAL_CONFIG missing"
  fi
else
  mkdir -p "$GLOBAL_CONFIG_DIR"
  if [[ -z "$VAULT_PATH" ]] || [[ "$VAULT_PATH" == "/path/to/your/vault" ]]; then
    echo ""
    read -rp "  Where is your Obsidian vault? (absolute path): " VAULT_PATH
    if [[ -n "$VAULT_PATH" ]]; then
      sed -i.bak "s|^OBSIDIAN_VAULT_PATH=.*|OBSIDIAN_VAULT_PATH=$VAULT_PATH|" "$SCRIPT_DIR/.env"
      rm -f "$SCRIPT_DIR/.env.bak"
    fi
  fi
  cat > "$GLOBAL_CONFIG" <<EOF
OBSIDIAN_VAULT_PATH=$VAULT_PATH
OBSIDIAN_WIKI_REPO=$SCRIPT_DIR
EOF
  echo "✅  Global config written to ~/.obsidian-wiki/config"
fi

# ── Step 2: Workspace-scoped skill symlinks ────────────────────
AGENT_DIRS=(
  ".claude/skills"
  ".cursor/skills"
  ".windsurf/skills"
  ".agents/skills"
)

for agent_dir in "${AGENT_DIRS[@]}"; do
  target="$SCRIPT_DIR/$agent_dir"
  link_all_skills_into "$target" "$agent_dir/" "relative" || true
done

# ── Step 3: Global skills for Claude Code (subset) ─────────────
GLOBAL_SKILLS=("wiki-update" "wiki-query")
GLOBAL_SKILL_DIR="$HOME/.claude/skills"

if (( ! VERIFY_MODE )); then
  mkdir -p "$GLOBAL_SKILL_DIR"
elif [[ ! -d "$GLOBAL_SKILL_DIR" ]]; then
  echo "⚠️   MISSING: $GLOBAL_SKILL_DIR"
fi
failed=0
for skill_name in "${GLOBAL_SKILLS[@]}"; do
  ensure_symlink "$SKILLS_DIR/$skill_name" "$GLOBAL_SKILL_DIR/$skill_name" || failed=1
done
if (( failed )); then
  echo "⚠️   ~/.claude/skills/ has symlink issues"
else
  echo "✅  ~/.claude/skills/ (wiki-update, wiki-query)"
fi

# ── Step 4: Global skills for Gemini / Codex / OpenClaw ────────
link_all_skills_into "$HOME/.gemini/antigravity/skills" "~/.gemini/antigravity/skills/" || true
link_all_skills_into "$HOME/.codex/skills" "~/.codex/skills/" || true
link_all_skills_into "$HOME/.agents/skills" "~/.agents/skills/ (OpenClaw + generic)" || true

# ── Step 5: Summary ────────────────────────────────────────────
SKILL_COUNT=$(ls -d "$SKILLS_DIR"/*/ 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "───────────────────────────────────────────────────"
if (( VERIFY_MODE )); then
  echo " Verify complete. Review any ⚠️  lines above."
else
  echo " Setup complete."
fi
echo ""
echo " Skills found:    $SKILL_COUNT"
echo " Agents ready:    Claude Code, Cursor, Windsurf, Antigravity/Gemini, Codex, OpenClaw"
echo ""
echo " Bootstrap files:"
echo "   AGENTS.md       → Codex, OpenClaw, OpenCode, Droid, Claude Code"
echo "   .cursor/rules/  → Cursor"
echo "   .windsurf/rules/ → Windsurf"
echo "   .github/copilot-instructions.md → GitHub Copilot"
echo ""
echo " Next steps:"
echo "   1. Open this project in your agent"
echo "   2. Say: \"Set up my wiki\""
echo ""
echo " From any other project:"
echo "   /wiki-update    → sync knowledge into your vault"
echo "   /wiki-query     → ask questions against your wiki"
echo "───────────────────────────────────────────────────"
echo ""
