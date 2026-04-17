# Obsidian Wiki — Agent Context

This project is a **skill-based framework** for building and maintaining a multi-vault Obsidian knowledge base. The agent is the runtime: every workflow lives as markdown instructions under `.skills/`, executed directly by an AI coding agent (Claude Code, Cursor, Windsurf, Codex, Gemini, OpenClaw, …).

## Quick Orientation

1. Read `.config/wikis.json` — the **multi-wiki registry** (default: `rhoton`). Every wiki declares its vault, sources, extractions, tools, and domain.
2. Resolve a wiki into env vars with `source lib/resolve-wiki.sh <wiki-name>`. Exports `WIKI_VAULT`, `WIKI_SOURCES`, `WIKI_EXTRACTIONS`, `WIKI_TOOLS`, `WIKI_DOMAIN`, `WIKI_OUTPUT`.
3. `.env` still holds `OBSIDIAN_VAULT_PATH` for legacy single-wiki skills. New skills must read the registry.
4. Each vault's `.manifest.json` tracks what's been ingested. Always read it before planning work.
5. Skills in `.skills/` are the canonical source; `setup.sh` symlinks them into every agent's expected directory.

## Skill Dispatch

One row per skill. Every row resolves to a real `.skills/<name>/SKILL.md` on disk.

| User says… | Read this skill |
|---|---|
| "set up my wiki" / "initialize" | `.skills/wiki-setup/SKILL.md` |
| "ingest" / "add this to the wiki" / "process these docs" | `.skills/wiki-ingest/SKILL.md` |
| "import my Claude history" / "mine my conversations" | `.skills/claude-history-ingest/SKILL.md` |
| "process this export" / "ingest this data" / logs, transcripts | `.skills/data-ingest/SKILL.md` |
| "what's the status" / "show the delta" / "what's been ingested" | `.skills/wiki-status/SKILL.md` |
| "wiki insights" / "what's central" / "show me the hubs" | `.skills/wiki-status/SKILL.md` (insights mode) |
| "what do I know about X" / any question against the wiki | `.skills/wiki-query/SKILL.md` |
| "audit" / "lint" / "find broken links" / "wiki health" | `.skills/wiki-lint/SKILL.md` |
| "rebuild" / "start over" / "archive" / "restore" | `.skills/wiki-rebuild/SKILL.md` |
| "link my pages" / "cross-reference" / "connect my wiki" | `.skills/cross-linker/SKILL.md` |
| "cross-link wikis" / "bridge rhoton to ncx" / "populate crossmap" / "connect my wikis" | `.skills/cross-wiki-linker/SKILL.md` |
| "fix my tags" / "normalize tags" / "tag audit" | `.skills/tag-taxonomy/SKILL.md` |
| "update wiki" / "sync to wiki" / "save this to my wiki" | `.skills/wiki-update/SKILL.md` |
| "run autoresearch" / "start a campaign" / `/autoresearch` | `.skills/autoresearch/SKILL.md` |
| "quiz me" / "flashcards" / "viva mode" / "anki export" | `.skills/quiz-mode/SKILL.md` |
| "ncx bridge" / "link ncx cases to rhoton anatomy" | `.skills/ncx-bridge/SKILL.md` |
| "create a new skill" | `.skills/skill-creator/SKILL.md` |
| "export wiki" / "graphml" / "neo4j" / "visualize wiki" | `.skills/wiki-export/SKILL.md` |
| "llm wiki pattern" / architecture reference | `.skills/llm-wiki/SKILL.md` |

## Autoresearch System

The wiki grows iteratively via the `/autoresearch` local terminal loop. Every iteration: pick one action (ingest / augment / cross-link / tag-audit), verify score, run guard, commit-or-discard. Canonical spec: `.skills/autoresearch/SKILL.md`.

### Tooling (`lib/`)

| Script | Usage | Purpose |
|---|---|---|
| `lib/resolve-wiki.sh` | `source lib/resolve-wiki.sh <wiki>` | Registry → env vars |
| `lib/autoresearch-verify.sh` | `lib/autoresearch-verify.sh <wiki>` | Emits integer score on stdout |
| `lib/autoresearch-guard.sh` | `lib/autoresearch-guard.sh <wiki>` | Exit 0 on pass, 1 on violations |

### Score Function

```
score = (pages * 10) + (wikilinks * 2) + (words / 100)
```

Counted across every `.md` in the vault except `index.md`, `log.md`, and files under `.obsidian/` or `.smart-env/`.

### Result TSVs

Per-wiki iteration log lives at `.autoresearch/<wiki>/results.tsv` (gitignored except `.gitkeep`). Columns: `iteration | commit | metric | delta | guard | status | description`.

### Loop Invariant

Local only. No network calls inside the loop. The agent's own reasoning is the generator; guards are the discriminator.

## Key Rules

- **Compile, don't retrieve.** The wiki is pre-compiled knowledge. Update existing pages before creating new ones.
- **Always update `.manifest.json`** after ingesting — it tracks what's been processed per wiki.
- **Always update `index.md` and `log.md`** after any write operation.
- **Use `[[wikilinks]]`** for internal links. Never use plain markdown links to vault pages.
- **Frontmatter is required** on every wiki page: `title`, `category`, `tags`, `sources`, `created`, `updated`.
- **Never modify `.obsidian/`** — plugin configs are pre-committed and per-vault.
- **Respect the tag taxonomy.** Do not invent tags. Consult `<vault>/_meta/taxonomy.md` and `.skills/tag-taxonomy/` before writing.
- **No secrets in git.** `.env`, `.env.local`, and any API keys stay gitignored.

## Multi-Wiki Registry

Currently registered wikis (see `.config/wikis.json` for authoritative state):

| Wiki | Vault | Domain | Sources |
|---|---|---|---|
| `rhoton` | `rhoton-wiki/vault` | anatomy | Datalab extractions (`rhoton-wiki/extractions/datalab/`) |
| `ncx` | `ncx-wiki/vault` | clinical | External corpus at `/Users/fax/code/med-ncx` |
| `nsatlas` | `nsatlas-wiki/vault` | surgical | PDFs at `/Users/fax/code/dev-nsatlas/nsatlas/pdfs/english` |

Rhoton raw PDF (193 MB) lives outside the repo; its operational input for autoresearch is the pre-extracted Datalab markdown at `rhoton-wiki/extractions/datalab/chapters/`. Do **not** call the Datalab API unless a new PDF needs extraction.

## Environment Variables

Set in `.env` (gitignored):

| Variable | Required | Purpose |
|---|---|---|
| `OBSIDIAN_VAULT_PATH` | legacy | Single-vault path for pre-registry skills. New code reads `.config/wikis.json`. |
| `OBSIDIAN_SOURCES_DIR` | no | Override source dir for skills that scan external corpora. |
| `DATALAB_API_KEY` | no | Only needed for new PDF extractions (not for ingestion). |

## Architecture

Three-layer pattern (full reference: `.skills/llm-wiki/SKILL.md`):

- **Layer 1 — Sources.** PDFs, markdown corpora, transcripts, Datalab extractions. Live outside the vault.
- **Layer 2 — Compiled Wiki.** The Obsidian vault itself. Pages are interconnected via `[[wikilinks]]` and typed breadcrumb relations.
- **Layer 3 — Schema.** Skills, frontmatter rules, semantic relations, tag taxonomy. This layer governs what Layer 2 is allowed to look like.

### Vault Categories

| Directory | Content |
|---|---|
| `concepts/` | Anatomical structures, cisterns, regions |
| `entities/` | Arteries, veins, nerves (discrete units) |
| `synthesis/` | Cross-cutting integration pages |
| `references/` | Surgical approach protocols |
| `_meta/` | Taxonomy, plugin roles, sync config |
| `_canvases/` | Teaching flowcharts (`.canvas`) |
| `_quizzes/` | Flashcards, viva questions, Anki CSV |
| `_attachments/` | Figures, diagrams, binary assets |

### Semantic Relations (Breadcrumbs)

Six typed relation pairs expressed in frontmatter:

| Relation | Inverse | Example |
|---|---|---|
| `parent` | `child` | posterior-fossa contains cerebellum |
| `branch-of` | `branches` | PICA is branch-of vertebral-artery |
| `innervates` | `innervated-by` | CN III innervates extraocular-muscles |
| `traverses` | `traversed-by` | CN VI traverses cavernous-sinus |
| `approach-to` | `approached-via` | pterional targets anterior-circulation |
| `drains-to` | `drained-by` | basal-vein drains-to vein-of-Galen |

### Controlled Tag Vocabulary

`<vault>/_meta/taxonomy.md` is the source of truth (48 canonical tags for the rhoton vault). Do not invent new tags — either use existing ones or propose additions to the taxonomy file first.

## Datalab Extraction Pipeline

Source material is pre-extracted. No external API calls needed for ingestion.

| Path | Content |
|---|---|
| `rhoton-wiki/tools/datalab/` | PDF extraction client (`datalab_convert.py`) |
| `rhoton-wiki/tools/datalab-augment/` | Figure staging + chapter mapping scripts |
| `rhoton-wiki/extractions/datalab/` | 20 chapters of extracted markdown + 885 figures |
| `rhoton-wiki/extractions/datalab-augment/` | Processed figure metadata |

Use chapter dirs under `extractions/datalab/chapters/` as source material when augmenting pages.

## Setup

`bash setup.sh` — install/update skill symlinks for every supported agent.
`bash setup.sh --verify` — dry-run; reports MISSING/STALE without modifying anything.

Preconditions: `jq` ≥ 1.6 on host (multi-wiki registry parsing). The script aborts with install instructions if missing.

## Further Reading

- `README.md` — human-facing project overview.
- `SETUP.md` — onboarding walkthrough.
- `.sisyphus/plans/enterprise-refactor.md` — refactor history and phase ledger.
- `.skills/llm-wiki/SKILL.md` — Karpathy LLM Wiki pattern, full theory.
