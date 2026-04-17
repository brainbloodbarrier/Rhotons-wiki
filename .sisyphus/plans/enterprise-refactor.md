---
title: Enterprise-Grade Refactor Plan — pkm-obsidian-wiki
author: Sisyphus
created: 2026-04-17
status: proposed
scope: full repository reorganization + autoresearch formalization
reviewers: [momus, user]
---

# Enterprise-Grade Refactor Plan — pkm-obsidian-wiki

## 0. Executive Summary

The project is a skill-based framework for building multi-vault Obsidian
knowledge bases. Its defining feature is a **local terminal loop** (`/autoresearch`)
that runs inside Claude Code / OpenCode, iteratively expanding a wiki while
enforcing quality guards. Today the feature works but the surrounding
architecture is organically grown:

- Three separate wikis (rhoton, ncx, nsatlas) share almost no infrastructure.
- The autoresearch loop exists only as prose in `CLAUDE.md` + six copy-paste
  bash scripts. It is not a formal skill.
- Root directory mixes config, scripts, vaults, PDFs, generated output, and
  empty stray directories.
- Six documentation files with ~70% overlap.
- Guards validate only frontmatter field presence — no link integrity, no
  orphan detection, no score regression check.

This plan reorganizes the repo into an enterprise-grade structure **without
changing the UX** (`/autoresearch` still runs as a local terminal loop). It
preserves every existing wiki and every existing skill; it adds one critical
skill that is currently missing; and it hardens scripts, documentation, and
directory layout.

### Non-negotiable invariants

1. `/autoresearch` keeps running as a **local, terminal-only loop** in
   Claude Code / OpenCode. No network dependencies added to the loop itself.
2. **Existing wiki page content (body + pre-existing frontmatter) remains
   byte-identical** through Phases 0-6. Only scripts, skills, docs, and
   config move. Phase 7 may add one optional frontmatter key
   (`cross-wiki-ref:`) to pages — but only after explicit user opt-in
   (see Phase 7 actions); by default Phase 7 writes bridges only to
   `crossmap.json` and leaves pages untouched.
3. Any single phase can be rolled back independently via `git revert`.
4. No secret material is ever committed. `.env` never leaves gitignore.
5. The plan must be executable by either a human or a capable agent following
   the phase-by-phase instructions below. No implicit knowledge.

### Out of scope (explicit)

- Changing existing page **body content** (markdown below frontmatter).
- Changing existing frontmatter keys/values. The **only** permitted
  frontmatter mutation anywhere in this plan is the optional
  `cross-wiki-ref:` addition in Phase 7, and only if the user opts in.
- Adding remote APIs to the autoresearch loop itself (local-only invariant).
- Migrating to a different PKM tool.
- Introducing a database / index server outside of `.smart-env` (which is
  plugin-managed).

---

## 1. Current State — Evidence-Based Findings

### 1.1 Root directory (37 entries) — verified `ls -la`

| Artifact | Issue | Evidence |
|---|---|---|
| `autoresearch-guard.sh`, `ncx-autoresearch-guard.sh`, `nsatlas-autoresearch-guard.sh` | 3 copies differing only in `VAULT=` line; variable name also drifts (`ERRORS` vs `FAIL`) | Read all three, confirmed |
| `autoresearch-verify.sh`, `ncx-autoresearch-verify.sh`, `nsatlas-autoresearch-verify.sh` | 3 copies of score function, hardcoded vault path | Read all three, confirmed |
| `autoresearch-results.tsv`, `ncx-autoresearch-results.tsv`, `nsatlas-autoresearch-results.tsv` | 3 output files dumped at repo root | `ls -la` confirmed |
| `~/` | **Literal directory named `~`** at repo root — bug from unquoted `$HOME` in some script | `ls -la` shows `drwxr-xr-x ~` |
| `scripts/` | Empty directory | `ls` returned nothing |
| `reason/` | One-off artifact, unused | 1 stale subdir |
| `Rhoton...pdf` (193 MB) | Huge binary in working tree | `-rw-r--r-- 1 fax 193250076` |
| `crossmap.json` | `{"bridges": []}` — concept declared, zero content | Read file |
| `CLAUDE.md` vs `AGENTS.md` | ~70% content overlap; dispatch tables drift | Diff comparison |

### 1.2 `.gitignore` inconsistency — verified

```
.env                        # OK
*.pdf                       # OK — Rhoton PDF is ignored but still 193MB on disk
autoresearch-results.tsv    # Ignored
# ncx-autoresearch-results.tsv  — NOT ignored
# nsatlas-autoresearch-results.tsv — NOT ignored
# .smart-env/               — NOT ignored, but should be
```

`git status --short` shows 30+ `.smart-env/multi/*.ajson` as Modified. These
are Obsidian Smart Connections plugin output (embeddings) — machine-generated,
should never be tracked.

### 1.3 Guard bug — verified by reading `autoresearch-guard.sh`

```bash
exit $ERRORS
```

POSIX `exit` wraps to mod 256. If `ERRORS >= 256` the shell reports success
(or the wrong code). Silent correctness bug under scale.

Also no `set -euo pipefail`, no argument validation, hardcoded `VAULT=` path.

### 1.4 Missing skill — verified `ls .skills/`

17 skills present. **`autoresearch` is not among them.** The loop protocol
exists only as a ~60-line prose section in `CLAUDE.md`. Any agent running
`/autoresearch` has to parse prose and infer behavior. This is the single
most important feature of the project and it has no canonical skill doc.

### 1.5 Symlink fragility — verified `setup.sh`

`setup.sh` creates symlinks from `.claude/skills/`, `.agents/skills/`,
`.windsurf/skills/`, `~/.gemini/antigravity/skills/`, `~/.codex/skills/` into
`.skills/`. No validation that the symlinks resolved; no check for pre-existing
non-symlink directories with the same name; uses `set -e` but many `ln -s`
failures are non-fatal on macOS under some conditions.

### 1.6 Multi-wiki has no registry — verified across skills

Every skill reads `OBSIDIAN_VAULT_PATH` from `.env`. `.env` can only point at
one vault. Switching wikis = manual `.env` edit. No way for an agent to know
that three wikis exist or which one is "current."

---

## 2. Target Architecture

### 2.1 Final directory layout

```
pkm-obsidian-wiki/
├── .config/
│   └── wikis.json                   # Wiki registry (NEW)
├── .skills/                         # Canonical skill source
│   ├── autoresearch/SKILL.md        # NEW — formalizes the loop
│   ├── wiki-ingest/SKILL.md
│   ├── wiki-status/SKILL.md
│   ├── wiki-query/SKILL.md
│   ├── wiki-lint/SKILL.md
│   ├── wiki-setup/SKILL.md
│   ├── wiki-update/SKILL.md
│   ├── wiki-rebuild/SKILL.md
│   ├── wiki-export/SKILL.md
│   ├── cross-linker/SKILL.md
│   ├── tag-taxonomy/SKILL.md
│   ├── skill-creator/SKILL.md
│   ├── data-ingest/SKILL.md
│   ├── claude-history-ingest/SKILL.md
│   ├── llm-wiki/SKILL.md
│   ├── ncx-bridge/SKILL.md
│   └── quiz-mode/SKILL.md
├── .autoresearch/                   # Generated output (gitignored except .gitkeep)
│   ├── rhoton/results.tsv
│   ├── ncx/results.tsv
│   └── nsatlas/results.tsv
├── lib/                             # Parameterized shell scripts (NEW)
│   ├── resolve-wiki.sh              # Helper: wiki-name → env vars
│   ├── autoresearch-verify.sh       # verify.sh <wiki-name>
│   ├── autoresearch-guard.sh        # guard.sh <wiki-name>
│   └── README.md
├── rhoton-wiki/
│   ├── vault/
│   ├── extractions/
│   └── tools/
├── ncx-wiki/
│   └── vault/
├── nsatlas-wiki/
│   ├── vault/
│   ├── extractions/
│   └── tools/
├── crossmap.json                    # Populated in later phase
├── .env.example                     # Template (tracked)
├── .env                             # Local secrets (gitignored)
├── .gitignore                       # Tightened
├── AGENTS.md                        # Single source of truth for agents
├── README.md                        # Humans / GitHub
├── SETUP.md                         # Onboarding
├── setup.sh                         # Bootstrap (hardened)
└── .sisyphus/plans/                 # Plan archive (this doc lives here)
```

### 2.2 Files deleted

- `autoresearch-{guard,verify}.sh` (top-level) → replaced by `lib/` versions
- `ncx-autoresearch-{guard,verify}.sh` → replaced
- `nsatlas-autoresearch-{guard,verify}.sh` → replaced
- `*-autoresearch-results.tsv` (root) → moved to `.autoresearch/<wiki>/`
- `CLAUDE.md` → content merged into `AGENTS.md` + `.skills/autoresearch/SKILL.md`
- `ONBOARDING.md` → content merged into `README.md`
- `.github/copilot-instructions.md` → replaced by symlink to `AGENTS.md`
  (or regenerated from it)
- `scripts/` (empty)
- `reason/` (stale one-off)
- `~/` (bug artifact)

### 2.3 Wiki registry schema (`.config/wikis.json`)

All path fields are **nullable** except `vault`. `sources` points at
raw inputs (PDFs, markdown corpora); `extractions` points at processed
intermediate output; both may be null when not applicable or when sources
live outside the repo.

**Rhoton sources note.** The Rhoton raw PDF lives in the working tree
today at `Rhoton - Cranial Anatomy and Surgical Approaches (2023)
[neuroanatomia].pdf` (gitignored). Phase 0 moves it outside the repo.
Its effective "source" for autoresearch ingestion is already the extracted
chapters at `rhoton-wiki/extractions/datalab/`. The registry therefore
treats `extractions` as the operational input and records the external
PDF location via an optional `raw_source` field (null or an absolute
path on the host after Phase 0 move).

```json
{
  "$schema": "./wikis.schema.json",
  "version": "1.0.0",
  "default": "rhoton",
  "wikis": {
    "rhoton": {
      "vault": "rhoton-wiki/vault",
      "sources": null,
      "raw_source": null,
      "extractions": "rhoton-wiki/extractions",
      "tools": "rhoton-wiki/tools",
      "domain": "anatomy",
      "description": "Rhoton Cranial Anatomy"
    },
    "ncx": {
      "vault": "ncx-wiki/vault",
      "sources": "/Users/fax/code/med-ncx",
      "raw_source": null,
      "extractions": null,
      "tools": null,
      "domain": "clinical",
      "description": "NCX clinical neuro"
    },
    "nsatlas": {
      "vault": "nsatlas-wiki/vault",
      "sources": "/Users/fax/code/dev-nsatlas/nsatlas/pdfs/english",
      "raw_source": null,
      "extractions": "nsatlas-wiki/extractions",
      "tools": "nsatlas-wiki/tools",
      "domain": "surgical",
      "description": "Neurosurgical Atlas"
    }
  },
  "crossmap": "crossmap.json",
  "output_dir": ".autoresearch"
}
```

After Phase 0 moves the Rhoton PDF to (for example)
`~/Library/PKM-Sources/rhoton.pdf`, the user updates `rhoton.raw_source`
in their local `.config/wikis.json` to that absolute path. The committed
version ships with `raw_source: null` and a comment in SETUP.md instructing
the user to fill it in if they need PDF re-extraction workflows.

A JSON Schema file (`wikis.schema.json`) is committed alongside for
validation; `lib/resolve-wiki.sh` uses `jq` (already a dev assumption — verify
in Phase 0) to parse.

---

## 3. Phased Execution Plan

Each phase is **independently revertable** and has explicit success criteria.
Phases marked P0 must complete before any P1; P1 before P2; etc. Within a
priority tier, phases can run in any order.

### Phase 0 — Cleanup & Hygiene (P0)

**Objective.** Remove junk, fix known bugs, tighten `.gitignore`. Zero
behavior change for the autoresearch loop.

**Preconditions.**
- `jq` installed on host (`jq --version` returns ≥ 1.6). Document in SETUP.md.
- Current `git status` captured before start (for rollback reference).
- Existing autoresearch TSVs backed up to `/tmp/refactor-backup/` (safety).

**Actions.**

1. `rm -rf "~"` (the literal `~` directory at repo root).
2. `rmdir scripts/` (empty).
3. Move `reason/` to `.archive/reason/` (don't delete — may contain notes).
4. Move `Rhoton - Cranial Anatomy and Surgical Approaches (2023) [neuroanatomia].pdf`
   out of the repo (to `~/Library/PKM-Sources/` or similar). Document new
   path in `.env.example`. PDF is already `.gitignore`d so no git action needed.
5. Add to `.gitignore`:
   ```
   .smart-env/
   .obsidian/plugins/*/data.json
   .obsidian/workspace*.json
   .autoresearch/
   !.autoresearch/.gitkeep
   *-autoresearch-results.tsv
   .omc/
   .remember/
   ```
6. `git rm --cached` for every `.smart-env/**/*.ajson` currently tracked
   (there are 30+). These are embeddings, not source.
7. Create `.env.example` entry:
   ```
   # Legacy — individual wiki paths (deprecated, read .config/wikis.json)
   OBSIDIAN_VAULT_PATH=rhoton-wiki/vault
   ```
8. Remove the hardcoded `DATALAB_API_KEY` from `.env` committed to working
   tree if present; move to `.env.local` (new gitignored file) or keep in
   `.env` (still gitignored). **Verify no commit ever contained it** via
   `git log -S DATALAB_API_KEY --all`. If found, rotate the key externally
   before continuing.

**Success criteria.**
- `git status --short` shows zero `.smart-env/`, `.obsidian/plugins/*/data.json`,
  `.obsidian/workspace*.json` entries.
- `ls -la` at repo root no longer shows `~/`, `scripts/`, `reason/`, or PDF.
- `bash autoresearch-guard.sh` (still the old script at this phase) still
  runs and produces the same output as before.
- `git log -S DATALAB_API_KEY --all` returns nothing (or key has been
  rotated).

**Rollback.** `git checkout HEAD -- .gitignore` + restore moved files from
`/tmp/refactor-backup/` + `git rm --cached` reversal via `git add -A`.

**Estimated effort.** 30 min.

---

### Phase 1 — Autoresearch as Skill (P0)

**Objective.** Create `.skills/autoresearch/SKILL.md` formalizing the loop
that currently lives as prose in `CLAUDE.md`. This is the **most important
phase** of the entire refactor.

**Preconditions.** Phase 0 complete.

**Actions.**

1. Create `.skills/autoresearch/SKILL.md` with sections:
   - **Frontmatter** (YAML: title, description, applies_to, version).
   - **Purpose.** One-paragraph statement: "Local terminal loop that
     iteratively grows a wiki via the agent's own reasoning, enforcing
     quality guards between each step."
   - **Loop protocol** (numbered, atomic):
     1. Read baseline (run verify → record score).
     2. Select action (ingest / cross-link / audit / taxonomy — one at a time).
     3. Execute action.
     4. Re-verify (score).
     5. Run guard.
     6. If guard fails OR score regressed → discard via `git checkout`
        and log `discarded` row in `.autoresearch/<wiki>/results.tsv`.
     7. Else → commit and log `kept` row.
     8. Update `index.md` and `log.md` in the vault.
     9. Iterate until stop condition (user halts, N iterations, score
        plateau, or guard catastrophic failure).
   - **Score function** (formal spec, not just bash):
     `score = 10·pages + 2·wikilinks + words/100`
     Rationale per term. Known weaknesses. Future-work notes.
   - **Guard validations** (complete list, parameterizable):
     required frontmatter fields, wikilink integrity, orphan detection,
     taxonomy compliance, no-regression-vs-baseline.
   - **Result TSV schema** (columns, types, meaning):
     `timestamp, wiki, iteration, action, score_before, score_after,
     guard_errors, decision, commit_sha, notes`.
   - **Campaign concept.** A campaign = N iterations with a named theme
     (e.g., `cross-linking-sweep`, `taxonomy-normalization`). Tracked via
     TSV `notes` column.
   - **Multi-wiki awareness.** Skill reads `.config/wikis.json`; takes
     wiki-name as input; resolves paths via `lib/resolve-wiki.sh`.
   - **Stop conditions** (explicit list).
   - **Rollback guarantees.** Every iteration is atomic (one commit per
     kept iteration). `git revert HEAD` always works.
   - **Local-only invariant.** Skill must not make network calls. Only
     the agent's own reasoning + local tools.

2. In `AGENTS.md`, add `/autoresearch` to the skill dispatch table pointing
   at `.skills/autoresearch/SKILL.md`.

3. Remove the `## Autoresearch` prose section from `CLAUDE.md` (Phase 5
   will delete CLAUDE.md entirely; this is prep).

**Success criteria — all must be verified by executable commands, not
prose.**

1. **File exists and is frontmatter-valid.**
   ```bash
   test -f .skills/autoresearch/SKILL.md
   head -1 .skills/autoresearch/SKILL.md | grep -q '^---$'
   awk '/^---$/{c++} c==2{exit} END{exit (c<2)}' .skills/autoresearch/SKILL.md
   wc -l .skills/autoresearch/SKILL.md | awk '{exit ($1 < 200)}'
   ```
   All four commands exit 0.

2. **Skill is discoverable via AGENTS.md.**
   ```bash
   grep -q 'autoresearch' AGENTS.md
   ```
   Exit 0.

3. **Smoke test — one full loop iteration against rhoton-wiki.** This
   phase predates the parameterized scripts, so the smoke test uses the
   existing `autoresearch-verify.sh` and `autoresearch-guard.sh` for the
   score/guard primitives, but the *orchestration* is driven by reading
   `.skills/autoresearch/SKILL.md`:

   ```bash
   # Baseline
   SCORE_BEFORE=$(./autoresearch-verify.sh)
   ./autoresearch-guard.sh || exit 1    # must pass before we start

   # Agent reads .skills/autoresearch/SKILL.md and picks ONE trivial
   # deterministic action — e.g., add a single new valid wikilink between
   # two existing pages that are known to be unlinked. This action is
   # pre-agreed in the smoke test setup (e.g., link A -> B where B already
   # exists in the vault).

   # Post-action verification
   SCORE_AFTER=$(./autoresearch-verify.sh)
   ./autoresearch-guard.sh
   GUARD_EXIT=$?

   # Decision logic per the skill
   if [[ $GUARD_EXIT -eq 0 ]] && (( SCORE_AFTER >= SCORE_BEFORE )); then
     git add -A && git commit -m "autoresearch: smoke test iteration (kept)"
     DECISION=kept
   else
     git checkout -- rhoton-wiki/vault
     DECISION=discarded
   fi

   # TSV row appended
   printf '%s\t%s\t%d\t%d\t%d\t%s\n' \
     "$(date -Iseconds)" rhoton 1 "$SCORE_BEFORE" "$SCORE_AFTER" "$DECISION" \
     >> autoresearch-results.tsv
   ```

   **Pass condition:** the smoke test runs end-to-end with exit 0,
   DECISION is `kept` (since the pre-agreed action is deterministically
   valid), SCORE_AFTER > SCORE_BEFORE (by exactly 2 because one wikilink
   was added), and `autoresearch-results.tsv` gained exactly one new row
   with the expected tab-separated columns.

   The skill doc is considered complete when a reasonably capable agent
   (Claude Code / OpenCode on a current model) can execute this smoke
   test by reading only `AGENTS.md` + `.skills/autoresearch/SKILL.md`,
   without opening `CLAUDE.md` or the bash scripts.

4. **Dispatch table coverage.** Every skill dir under `.skills/` has
   a row in `AGENTS.md`'s dispatch table. Automated check:
   ```bash
   for d in .skills/*/; do
     name=$(basename "$d")
     grep -q "$name" AGENTS.md || { echo "MISSING: $name"; exit 1; }
   done
   ```
   Exit 0.

**Rollback.** Delete `.skills/autoresearch/`, revert `AGENTS.md`,
`git checkout -- rhoton-wiki/vault autoresearch-results.tsv`.

**Estimated effort.** 2-3 h for the skill doc; +30 min for smoke-test
scripting.

---

### Phase 2 — Multi-Wiki Configuration (P1)

**Objective.** Introduce `.config/wikis.json` as the single source of truth
for wiki locations. All scripts and skills stop hardcoding paths.

**Preconditions.** Phase 1 complete. `jq` available.

**Actions.**

1. Create `.config/wikis.json` per schema in §2.3.
2. Create `.config/wikis.schema.json` (JSON Schema draft-07).
3. Create `lib/resolve-wiki.sh`:
   ```bash
   #!/bin/bash
   # Usage: source lib/resolve-wiki.sh <wiki-name>
   # Exports: WIKI_NAME, WIKI_VAULT, WIKI_SOURCES, WIKI_RAW_SOURCE,
   #          WIKI_EXTRACTIONS, WIKI_TOOLS, WIKI_DOMAIN, WIKI_OUTPUT
   # Nullable fields export as empty strings when null in JSON.
   set -euo pipefail
   WIKI_NAME="${1:-}"
   [[ -z "$WIKI_NAME" ]] && { echo "resolve-wiki: wiki name required"; exit 64; }
   CONFIG=".config/wikis.json"
   [[ -f "$CONFIG" ]] || { echo "resolve-wiki: $CONFIG not found"; exit 66; }
   jq -e ".wikis.\"$WIKI_NAME\"" "$CONFIG" > /dev/null \
     || { echo "resolve-wiki: unknown wiki '$WIKI_NAME'"; exit 65; }
   export WIKI_NAME
   export WIKI_VAULT=$(jq -r ".wikis.\"$WIKI_NAME\".vault" "$CONFIG")
   [[ -d "$WIKI_VAULT" ]] \
     || { echo "resolve-wiki: vault '$WIKI_VAULT' not found"; exit 66; }
   export WIKI_SOURCES=$(jq -r ".wikis.\"$WIKI_NAME\".sources // empty" "$CONFIG")
   export WIKI_RAW_SOURCE=$(jq -r ".wikis.\"$WIKI_NAME\".raw_source // empty" "$CONFIG")
   export WIKI_EXTRACTIONS=$(jq -r ".wikis.\"$WIKI_NAME\".extractions // empty" "$CONFIG")
   export WIKI_TOOLS=$(jq -r ".wikis.\"$WIKI_NAME\".tools // empty" "$CONFIG")
   export WIKI_DOMAIN=$(jq -r ".wikis.\"$WIKI_NAME\".domain" "$CONFIG")
   export WIKI_OUTPUT=".autoresearch/$WIKI_NAME"
   mkdir -p "$WIKI_OUTPUT"
   ```
4. Create `.autoresearch/` with `.gitkeep`.
5. Update the autoresearch skill (from Phase 1) to reference
   `lib/resolve-wiki.sh` and `.config/wikis.json`.

**Success criteria.**
- `source lib/resolve-wiki.sh rhoton && echo "$WIKI_VAULT"` prints
  `rhoton-wiki/vault`.
- `source lib/resolve-wiki.sh nonexistent` exits 65 with clear error.
- `source lib/resolve-wiki.sh` (no arg) exits 64 with clear error.
- Schema validation: `jq` + a schema validator (ajv-cli if available,
  otherwise manual) confirms `.config/wikis.json` matches the schema.

**Rollback.** `rm -rf .config lib .autoresearch`.

**Estimated effort.** 1 h.

---

### Phase 3 — Script Hardening & Parameterization (P1)

**Objective.** Replace six copy-paste scripts with two parameterized versions
in `lib/`. Fix the `exit $ERRORS` wrap-around bug.

**Preconditions.** Phase 2 complete.

**Actions.**

1. Create `lib/autoresearch-verify.sh`:
   ```bash
   #!/bin/bash
   # Usage: lib/autoresearch-verify.sh <wiki-name>
   # Outputs: integer score on stdout.
   set -euo pipefail
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   source "$SCRIPT_DIR/resolve-wiki.sh" "${1:-}"
   PAGES=$(find "$WIKI_VAULT" -name "*.md" \
     -not -path "*/.obsidian/*" -not -path "*/.smart-env/*" \
     -not -name "index.md" -not -name "log.md" | wc -l | tr -d ' ')
   LINKS=$(grep -r '\[\[' "$WIKI_VAULT" --include="*.md" 2>/dev/null \
     | wc -l | tr -d ' ')
   WORDS=$(find "$WIKI_VAULT" -name "*.md" \
     -not -path "*/.obsidian/*" -not -path "*/.smart-env/*" \
     -exec cat {} + 2>/dev/null | wc -w | tr -d ' ')
   SCORE=$(( (PAGES * 10) + (LINKS * 2) + (WORDS / 100) ))
   echo "$SCORE"
   ```
2. Create `lib/autoresearch-guard.sh`:
   ```bash
   #!/bin/bash
   # Usage: lib/autoresearch-guard.sh <wiki-name>
   # Exit: 0 = pass, 1 = any violations. Prints violations to stderr.
   set -euo pipefail
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   source "$SCRIPT_DIR/resolve-wiki.sh" "${1:-}"
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
       grep -q "^${field}:" <<< "$FRONTMATTER" || {
         echo "MISSING $field: $f" >&2
         ERRORS=$((ERRORS + 1))
       }
     done
   done < <(find "$WIKI_VAULT" -name "*.md" \
     -not -path "*/.obsidian/*" -not -path "*/.smart-env/*" \
     -not -name "index.md" -not -name "log.md")
   if (( ERRORS > 0 )); then
     echo "GUARD FAILED: $ERRORS error(s)" >&2
     exit 1
   fi
   exit 0
   ```
   Note: exit code is clamped to 1, not `$ERRORS`. Count goes to stderr.
3. Migrate existing TSVs:
   - `git mv autoresearch-results.tsv .autoresearch/rhoton/results.tsv`
   - `git mv ncx-autoresearch-results.tsv .autoresearch/ncx/results.tsv`
   - `git mv nsatlas-autoresearch-results.tsv .autoresearch/nsatlas/results.tsv`
   - Note: `.autoresearch/` is gitignored per Phase 0, so these become
     untracked after the move. If the user wants history, move then
     `git add -f`. Decide per user preference.
4. Delete old scripts:
   - `rm autoresearch-guard.sh autoresearch-verify.sh`
   - `rm ncx-autoresearch-guard.sh ncx-autoresearch-verify.sh`
   - `rm nsatlas-autoresearch-guard.sh nsatlas-autoresearch-verify.sh`

**Success criteria.**
- `lib/autoresearch-verify.sh rhoton` outputs an integer identical to what
  the old `autoresearch-verify.sh` produced (record before / compare after).
- `lib/autoresearch-guard.sh rhoton` exit code matches old script's clamped
  to 0/1: i.e. old_exit == 0 ↔ new_exit == 0, old_exit > 0 ↔ new_exit == 1.
- Old scripts no longer exist.
- TSV files are accessible at `.autoresearch/<wiki>/results.tsv`.

**Rollback.** Git revert; old scripts restored automatically.

**Estimated effort.** 1 h.

---

### Phase 4 — setup.sh Hardening (P1)

**Objective.** Fix the `~/` literal-directory bug, make symlink creation
idempotent and verified, produce machine-readable status.

**Preconditions.** None (independent of Phases 1-3; can parallelize with any
P1).

**Actions.**

1. Audit `setup.sh` for unquoted `$HOME` expansions. Find the line(s) that
   produced the literal `~/` and fix with proper expansion.
2. Wrap every `ln -s` with:
   ```bash
   ensure_symlink() {
     local src=$1 dst=$2
     if [[ -L "$dst" ]]; then
       local actual; actual=$(readlink "$dst")
       [[ "$actual" == "$src" ]] && return 0
       rm "$dst"
     elif [[ -e "$dst" ]]; then
       echo "ERROR: $dst exists and is not a symlink. Aborting." >&2
       return 1
     fi
     ln -s "$src" "$dst"
   }
   ```
3. Add `setup.sh --verify` flag that only checks current state and prints
   pass/fail summary without modifying anything.
4. Add detection for missing `jq` (required from Phase 2 onward); abort
   with install instructions.

**Success criteria.**
- Running `setup.sh` twice in a row produces identical output (idempotent).
- `setup.sh --verify` on a clean checkout returns exit 0.
- No literal `~/` directory ever appears in the repo.
- All agent skill dirs (`.claude/skills/`, `.agents/skills/`,
  `.windsurf/skills/`) either symlink to `.skills/*` or clearly error.

**Rollback.** Git revert `setup.sh`.

**Estimated effort.** 1 h.

---

### Phase 5 — Documentation Unification (P2)

**Objective.** Collapse 6 docs → 3 non-overlapping docs. `AGENTS.md` becomes
the single source of truth for agents.

**Preconditions.** Phase 1 complete (autoresearch skill exists to reference).

**Actions.**

1. Merge `CLAUDE.md` content into:
   - `AGENTS.md` (agent-facing overview + skill dispatch table, complete).
   - `.skills/autoresearch/SKILL.md` (the autoresearch section; most already
     moved in Phase 1).
   Delete `CLAUDE.md`.
2. Merge `ONBOARDING.md` into `README.md` under a "Team Onboarding" section.
   Delete `ONBOARDING.md`.
3. Replace `.github/copilot-instructions.md` with a symlink:
   `ln -s ../AGENTS.md .github/copilot-instructions.md`
   (If GitHub rejects symlinks for copilot-instructions, keep a 3-line stub:
   `# See AGENTS.md in repo root.` with a CI check to fail if it drifts.)
4. Audit `AGENTS.md` skill dispatch table against actual `.skills/`
   contents. Add missing entries (`quiz-mode`, `ncx-bridge`, `autoresearch`).
5. Ensure `README.md` has:
   - Project intro (one paragraph).
   - Installation (link to SETUP.md).
   - Quick start (three commands).
   - Architecture overview (link to `.skills/llm-wiki/SKILL.md`).
   - Multi-wiki list generated from `.config/wikis.json`.

**Success criteria.**
- Exactly three top-level docs: `README.md`, `AGENTS.md`, `SETUP.md`.
- `CLAUDE.md` and `ONBOARDING.md` deleted (evidence in `git log`).
- No section in `AGENTS.md` duplicates content in `README.md` or `SETUP.md`.
- `AGENTS.md` dispatch table has one row per skill in `.skills/`.
- Every skill referenced in `AGENTS.md` dispatch table exists on disk.

**Rollback.** Git revert.

**Estimated effort.** 1-2 h.

---

### Phase 6 — Enterprise Guard System (P3)

**Objective.** Upgrade the guard from frontmatter-presence to real wiki
quality validation.

**Preconditions.** Phases 1-3 complete.

**Actions.**

1. Extend `lib/autoresearch-guard.sh` (or split into composable checks):
   - **Frontmatter fields** (existing + `summary`, `sources`, `created`,
     `updated`).
   - **Wikilink integrity.** Every `[[target]]` resolves to an existing
     `.md` file in the vault. Aliases `[[target|label]]` also checked.
   - **Orphan detection.** Every page (except `index.md`, `log.md`,
     `_meta/*.md`) has ≥1 incoming wikilink.
   - **Taxonomy compliance.** Every `tags:` value exists in
     `<vault>/_meta/taxonomy.md` (if present; warn if taxonomy missing).
   - **No-regression score check.** Guard accepts optional
     `--baseline <score>` flag. If current score < baseline, exit 1.
2. Add `--format=json` flag to output machine-readable results for the
   autoresearch skill to consume.
3. Extend TSV schema with per-check pass/fail columns.

**Success criteria.**
- `lib/autoresearch-guard.sh rhoton --format=json` produces valid JSON with
  `{ "errors": N, "checks": { "frontmatter": ..., "wikilinks": ..., ... } }`.
- Running guard against a deliberately broken page (orphan + broken wikilink
  + missing tag) produces exactly 3 errors of the expected kinds.
- Running guard against the current production vaults produces an initial
  error report; those errors are either fixed or added to a documented
  allowlist in `.config/guard-allowlist.json`.

**Rollback.** Git revert.

**Estimated effort.** 3-4 h.

---

### Phase 7 — Crossmap Activation (P3)

**Objective.** Turn `crossmap.json` from empty stub into a functional
cross-wiki bridge registry populated by a new skill. Bridges are stored
**exclusively in `crossmap.json`** by default — vault pages are not
modified, preserving the byte-identical invariant from §0.

**Preconditions.** Phases 1-3 complete.

**Actions.**

1. Create `.skills/cross-wiki-linker/SKILL.md` (distinct from existing
   `cross-linker` which links within a single wiki). The skill has two
   modes:
   - **`--write-mode=crossmap-only`** (default): bridges go to
     `crossmap.json`, no page mutations. Obsidian plugins or the
     `wiki-query` skill read `crossmap.json` at query time to surface
     cross-wiki relationships. **Preserves byte-identical invariant.**
   - **`--write-mode=frontmatter`** (opt-in): in addition to writing
     `crossmap.json`, adds a `cross-wiki-ref:` key to the affected pages.
     Requires explicit user confirmation (skill prompts before writing).
     Relaxes the byte-identical invariant; user acknowledges.
2. Skill algorithm:
   a. Enumerate all pages across all wikis in `.config/wikis.json`.
   b. For each pair `(page_A in wiki_X, page_B in wiki_Y)` with X ≠ Y,
      compute similarity (title overlap, tag overlap, content embedding
      if `.smart-env` available — optional).
   c. Emit bridge entries above threshold into `crossmap.json`.
   d. **If and only if** `--write-mode=frontmatter` was explicitly
      selected, also add `cross-wiki-ref:` to both pages.
3. Define `crossmap.json` schema (version, bridges array with
   `{ wiki_a, page_a, wiki_b, page_b, confidence, rationale,
     created_at }`).
4. Add `skill: cross-wiki-linker` dispatch row to `AGENTS.md`.

**Success criteria.**
- `crossmap.json` has ≥ 1 bridge after running the skill in default
  (`crossmap-only`) mode against the three existing wikis.
- **Byte-identical check:** `git diff -- '*.md'` inside every vault after
  a default-mode run is empty. Automated check:
  ```bash
  git diff --name-only HEAD -- 'rhoton-wiki/vault/**/*.md' \
    'ncx-wiki/vault/**/*.md' 'nsatlas-wiki/vault/**/*.md' | wc -l
  ```
  Output = 0.
- `crossmap.json` validates against the committed JSON schema.
- Schema committed; existing `crossmap.json` structure remains backward-
  compatible (version field honored — current file is `version: "1.0"`).
- Frontmatter-mode path tested with a dry-run flag that prints the diff
  without applying.

**Rollback.** `git checkout -- crossmap.json` (vaults never touched in
default mode).

**Estimated effort.** 4-6 h.

---

## 4. Dependency Graph

```
Phase 0 ──┬─→ Phase 1 ──┬─→ Phase 2 ──┬─→ Phase 3 ──┬─→ Phase 6
          │             │             │             ├─→ Phase 7
          │             │             │             └─→ Phase 5 (only needs Phase 1)
          │             │             └─→ Phase 4 (parallelizable with P1/P2)
          │             └─→ Phase 5 (needs Phase 1)
          └────────────────────────────→ Phase 4 (can start after Phase 0)
```

Critical path: 0 → 1 → 2 → 3 → 6/7.

Phase 4 and Phase 5 can run in parallel with the critical path once their
prerequisites are satisfied.

## 5. Verification Plan (End-to-End)

After all phases complete, the following must all pass. Every check is an
executable command with a concrete expected result.

1. `bash setup.sh --verify` → exit 0 on a fresh clone.
2. `lib/autoresearch-verify.sh rhoton` → exit 0, stdout is a positive
   integer. Same for `ncx` and `nsatlas`.
3. `lib/autoresearch-guard.sh rhoton` → exit 0, or exit 1 with all errors
   listed in `.config/guard-allowlist.json`. Same for `ncx` and `nsatlas`.
4. `jq empty .config/wikis.json` → exit 0 (valid JSON). Plus schema
   validation via `ajv validate -s .config/wikis.schema.json -d
   .config/wikis.json` → exit 0 (if `ajv-cli` installed; else documented
   as a manual review step).
5. For each wiki in `rhoton`, `ncx`, `nsatlas`: run the Phase 1 smoke test
   (verify → deterministic action → verify → guard → commit-or-discard →
   TSV row). All three must complete with exit 0 and produce a new TSV
   row in `.autoresearch/<wiki>/results.tsv`.
6. `git status --porcelain` on a clean checkout shows zero tracked
   `.smart-env/*`, `.obsidian/workspace*`, `.obsidian/plugins/*/data.json`,
   `~/`, `scripts/`, `*-autoresearch-results.tsv` (old root variants),
   or the root PDF entries.
7. `AGENTS.md` skill dispatch table has exactly one row per dir in
   `.skills/`. Automated check:
   ```bash
   SKILL_DIRS=$(ls -1d .skills/*/ | wc -l | tr -d ' ')
   ROWS_IN_AGENTS=$(grep -c '^| ' AGENTS.md | tr -d ' ')
   # Rows count may include header; compare against SKILL_DIRS with known offset
   ```
8. The autoresearch loop remains entirely local. Automated check:
   ```bash
   grep -rE 'curl|wget|http[s]?://' lib/ .skills/autoresearch/ \
     && { echo "FAIL: outbound HTTP reference found"; exit 1; } \
     || echo "OK: no outbound HTTP"
   ```
   (Documentation URLs in comments are fine as long as they are not
   executed; refine the regex to ignore comment-only lines if needed.)
9. Byte-identical vault invariant (§0 invariant #2). After all phases
   except the opt-in Phase 7 frontmatter mode:
   ```bash
   git log --oneline --all -- 'rhoton-wiki/vault/**/*.md' \
                              'ncx-wiki/vault/**/*.md' \
                              'nsatlas-wiki/vault/**/*.md' \
     | head -20
   ```
   The output should show no commits authored by this refactor touching
   vault page markdown files (vs. the baseline pre-refactor HEAD).

## 6. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Existing autoresearch TSV history lost in move | Low | Medium | Backup to `/tmp/refactor-backup/` in Phase 0; user decides on `git add -f` for new location |
| Symlink fix breaks agents mid-session | Low | Low | Run Phase 4 only between sessions; `--verify` flag allows dry-run |
| `jq` not available on user's system | Medium | High | Phase 0 adds `jq` check to SETUP.md; setup.sh fails fast with install instructions |
| Guard becomes too strict, blocks loop | Medium | Medium | Allowlist (`.config/guard-allowlist.json`) + baseline mode allow incremental tightening |
| DATALAB_API_KEY found in git history | Unknown | Critical | Phase 0 step 8 verifies via `git log -S`; rotate key before proceeding if found |
| CLAUDE.md deletion breaks Claude Code auto-discovery | Low | Low | Claude Code discovers `AGENTS.md` too; verify before Phase 5 by running a Claude Code session against the branch |
| Phase 7 similarity algorithm produces noise | High | Low | Confidence threshold + manual review of first bridge batch; skill emits to staging file first |
| Phase 7 `--write-mode=frontmatter` violates byte-identical invariant | Low | Medium | Default mode never touches pages; frontmatter mode is opt-in and prompts user; dry-run flag shows diff before applying |

## 7. Open Questions for User

These must be resolved before execution begins. Default answers proposed;
user confirms or overrides.

1. **Move the 193MB PDF outside the repo?** Default: yes, to
   `~/Library/PKM-Sources/rhoton.pdf`. Alternative: keep as-is (gitignored).
2. **Preserve autoresearch TSV git history in new `.autoresearch/` location?**
   Default: yes via `git mv` (history preserved, then gitignore applied going
   forward). Alternative: leave old TSVs in place as archive and start fresh.
3. **Delete `reason/` or archive it?** Default: archive to `.archive/reason/`.
4. **Keep `.github/copilot-instructions.md` as symlink or stub?** Default:
   symlink if repo-level workflow allows; stub otherwise.
5. **Rotate `DATALAB_API_KEY` prophylactically?** Default: yes, even if not
   in git history, as it's been in working tree for multiple sessions.
6. **Execution mode: one phase at a time with review, or commit all phases
   on a branch then review?** Default: branch-per-phase with PR-style
   review; faster but user may prefer staged commits on a single branch.

## 8. Estimated Total Effort

| Phase | Effort |
|---|---|
| 0 — Cleanup | 30 min |
| 1 — Autoresearch skill | 2-3 h |
| 2 — Multi-wiki config | 1 h |
| 3 — Script hardening | 1 h |
| 4 — setup.sh | 1 h |
| 5 — Docs unification | 1-2 h |
| 6 — Enterprise guards | 3-4 h |
| 7 — Crossmap activation | 4-6 h |
| **Total (P0-P3)** | **~14-20 h** |
| **Minimum viable (P0 only)** | **~3-4 h** |

A session focused only on P0 phases (0 + 1) delivers:
- Clean repo (junk removed, gitignore tight).
- Canonical autoresearch skill (the single biggest improvement).
- No behavior changes to the running loop.

Everything else is incremental polish.

---

## 9. Commit Strategy

One commit per phase. Commit message template:

```
refactor(phase-N): <short phase title>

Summary of changes in this phase.
Success criteria verified:
- [x] criterion 1
- [x] criterion 2
Rollback: git revert <this commit>.
```

All commits on a feature branch `refactor/enterprise-grade`. User reviews
each before merge.

## 10. Success Definition (Project-Level)

The refactor is complete when all three of these are simultaneously true:

1. A new contributor with zero context reads `README.md` + `AGENTS.md` +
   `SETUP.md` and can successfully run one `/autoresearch` loop iteration
   against any of the three wikis.
2. `git status --short` on a clean checkout is empty, and every phase's
   success criteria are verified.
3. The total line count of documentation is lower than today (deduplication
   achieved), while skill coverage (skills per user-facing action) is
   higher than today (autoresearch formalized).

---

*End of plan.*
