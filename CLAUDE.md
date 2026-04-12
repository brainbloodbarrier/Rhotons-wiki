# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Orientation

1. Read `.env` for `OBSIDIAN_VAULT_PATH` (currently `rhoton-wiki/vault/`).
2. Read `.manifest.json` at the vault root to see what's been ingested.
3. Skills are in `.skills/` — each subfolder has a `SKILL.md` with a complete workflow.
4. This is a **markdown-only** project. No scripts, no dependencies. The agent IS the runtime.

## Skill Dispatch

| User says... | Read this skill |
|---|---|
| "set up my wiki" / "initialize" | `.skills/wiki-setup/SKILL.md` |
| "ingest" / "add this to the wiki" | `.skills/wiki-ingest/SKILL.md` |
| "import my Claude history" | `.skills/claude-history-ingest/SKILL.md` |
| "process this export" / logs, transcripts | `.skills/data-ingest/SKILL.md` |
| "what's the status" / "show the delta" | `.skills/wiki-status/SKILL.md` |
| "wiki insights" / "show me the hubs" | `.skills/wiki-status/SKILL.md` (insights mode) |
| "what do I know about X" | `.skills/wiki-query/SKILL.md` |
| "audit" / "lint" / "broken links" | `.skills/wiki-lint/SKILL.md` |
| "rebuild" / "start over" | `.skills/wiki-rebuild/SKILL.md` |
| "link my pages" / "cross-reference" | `.skills/cross-linker/SKILL.md` |
| "fix my tags" / "normalize tags" | `.skills/tag-taxonomy/SKILL.md` |
| "update wiki" / "sync to wiki" | `.skills/wiki-update/SKILL.md` |
| "create a new skill" | `.skills/skill-creator/SKILL.md` |
| "export wiki" / "graphml" / "neo4j" | `.skills/wiki-export/SKILL.md` |
| "quiz me" / "flashcards" / "viva" | `.skills/quiz-mode/SKILL.md` |

## Key Rules

- **Compile, don't retrieve.** The wiki is pre-compiled knowledge. Update existing pages, don't just append.
- **Always update `.manifest.json`** after ingesting — it tracks what's been processed.
- **Always update `index.md` and `log.md`** after any operation.
- **Use `[[wikilinks]]`** to connect related pages. Never use markdown links for internal pages.
- **Frontmatter is required** on every wiki page: `title`, `category`, `tags`, `sources`, `created`, `updated`.
- **Never modify `.obsidian/`** — plugin configs are pre-set.

## Autoresearch System

The wiki is built iteratively via autoresearch campaigns. Each iteration creates/augments pages and is scored.

### Scripts

| Script | Purpose |
|--------|---------|
| `autoresearch-verify.sh` | Computes score: `(PAGES * 10) + (LINKS * 2) + (WORDS / 100)` |
| `autoresearch-guard.sh` | Validates all pages have frontmatter with `title`, `category`, `tags` |
| `autoresearch-results.tsv` | Iteration log: `iteration \| commit \| metric \| delta \| guard \| status \| description` |

### Campaign Workflow

1. Read `autoresearch-results.tsv` for current baseline
2. Create or augment wiki pages from source material
3. Run `autoresearch-verify.sh` → new score
4. Run `autoresearch-guard.sh` → frontmatter validation (exit 0 = pass)
5. Score improves AND guard passes → commit + append to TSV → next iteration
6. Score regresses OR guard fails → discard changes → try different content

### Current State

- **Campaign 1:** 150 iterations, 139 pages created (COMPLETE)
- **Campaign 2:** Datalab-augmented iterations, score 11587→11803 (IN PROGRESS)

## Datalab Extraction Pipeline

Source material has been pre-extracted from the PDF. No external API calls needed for ingestion.

| Path | Content |
|------|---------|
| `rhoton-wiki/tools/datalab/` | PDF extraction client (`datalab_convert.py`) |
| `rhoton-wiki/tools/datalab-augment/` | Figure staging + chapter mapping scripts |
| `rhoton-wiki/extractions/datalab/` | 20 chapters of extracted markdown + 885 figures (223MB) |
| `rhoton-wiki/extractions/datalab-augment/` | Processed figure metadata |

### Chapter Extractions

Each chapter in `extractions/datalab/chapters/<chapter>/` contains markdown and figure references. Use these as source material for wiki page creation/augmentation — do NOT call the Datalab API.

## Environment Variables

Set in `.env` (not committed):

| Variable | Required | Purpose |
|----------|----------|---------|
| `OBSIDIAN_VAULT_PATH` | yes | Path to vault (default: `rhoton-wiki/vault`) |
| `OBSIDIAN_SOURCES_DIR` | no | Source documents directory |
| `DATALAB_API_KEY` | no | Only for new PDF extractions (not needed for ingestion) |

## Architecture

**Three-layer pattern** (see `.skills/llm-wiki/SKILL.md` for full reference):
- **Layer 1 — Sources:** PDFs, documents, images, datalab extractions
- **Layer 2 — Compiled Wiki:** Obsidian vault with interconnected pages
- **Layer 3 — Schema:** Skills, frontmatter rules, semantic relations

### Vault Categories

| Directory | Content |
|-----------|---------|
| `concepts/` | Anatomical structures, cisterns, regions |
| `entities/` | Arteries, veins, nerves (discrete units) |
| `synthesis/` | Cross-cutting integration pages |
| `references/` | Surgical approach protocols |
| `_meta/` | Taxonomy, plugin roles, sync config |
| `_canvases/` | Teaching flowcharts (.canvas) |
| `_quizzes/` | Flashcards, viva questions, Anki CSV |

### Semantic Relations (Breadcrumbs)

Six typed relation pairs in frontmatter:

| Relation | Inverse | Example |
|----------|---------|---------|
| `parent` | `child` | posterior-fossa contains cerebellum |
| `branch-of` | `branches` | PICA is branch-of vertebral-artery |
| `innervates` | `innervated-by` | CN III innervates extraocular-muscles |
| `traverses` | `traversed-by` | CN VI traverses cavernous-sinus |
| `approach-to` | `approached-via` | pterional targets anterior-circulation |
| `drains-to` | `drained-by` | basal-vein drains-to vein-of-Galen |

### Controlled Tag Vocabulary

See `rhoton-wiki/vault/_meta/taxonomy.md` for the 48 canonical tags. Do not invent new tags — use existing ones or propose additions to the taxonomy.
