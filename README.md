<p align="center">
  <img src="https://img.shields.io/badge/Pages-151-blue?style=for-the-badge" alt="Pages"/>
  <img src="https://img.shields.io/badge/Wikilinks-3000%2B-green?style=for-the-badge" alt="Wikilinks"/>
  <img src="https://img.shields.io/badge/Flashcards-329-orange?style=for-the-badge" alt="Flashcards"/>
  <img src="https://img.shields.io/badge/Canvases-6-purple?style=for-the-badge" alt="Canvases"/>
  <img src="https://img.shields.io/badge/Obsidian-Ready-7C3AED?style=for-the-badge&logo=obsidian&logoColor=white" alt="Obsidian"/>
</p>

# Rhoton's Wiki

A comprehensive microsurgical neuroanatomy knowledge base built from Albert Rhoton's *Cranial Anatomy and Surgical Approaches* (2023, 1668 pages, 15 chapters). 148 content pages (151 total including meta) covering every major arterial, venous, neural, and cisternal structure relevant to neurosurgical practice.

Built with the [obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) framework (Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern) and compiled autonomously via 150 autoresearch iterations and an 8-phase evolution pipeline.

---

## Quick Start

```bash
git clone https://github.com/brainbloodbarrier/Rhotons-wiki.git
cd Rhotons-wiki
```

Open `rhoton-wiki/vault/` as an Obsidian vault (File > Open Vault), install the community plugins listed below, and start exploring.

### Required Obsidian Plugins

Install via Settings > Community Plugins > Browse:

1. **Dataview** — structured queries across frontmatter
2. **Breadcrumbs** — typed relation traversal (parent, branch-of, innervates, etc.)
3. **ExcaliBrain** — ego-graph hierarchical navigation
4. **Smart Connections** — AI-powered similarity discovery (use `bge-micro-v2` local model)
5. **Advanced Canvas** — teaching flowcharts and decision trees

All plugin configs are pre-written in `.obsidian/` — just install and enable.

### First Steps

- **Cmd+G** — Global graph view (color-coded by category)
- **ExcaliBrain** — Click any page for parent/child/sibling navigation
- `_canvases/` — 6 interactive teaching flowcharts
- `_quizzes/flashcards-all.md` — 329 study flashcards

---

## What's Inside

### 148 Content Pages

| Category | Count | Examples |
|----------|-------|---------|
| Concepts | 64 | Basal cisterns, internal capsule, choroidal fissure, tentorial incisura |
| Entities | 52 | ICA, MCA, PCA, CN III–XII, vein of Galen, lenticulostriates |
| Synthesis | 18 | Perforating arteries map, aneurysm surgery, herniation syndromes |
| References | 14 | Pterional, retrosigmoid, telovelar, combined petrosal approaches |

### Semantic Relations (Breadcrumbs)

Six typed relation pairs model neuroanatomy formally:

| Relation | Inverse | Example |
|----------|---------|---------|
| `parent` | `child` | posterior-fossa contains cerebellum |
| `branch-of` | `branches` | PICA is branch-of vertebral-artery |
| `innervates` | `innervated-by` | CN III innervates extraocular-muscles |
| `traverses` | `traversed-by` | CN VI traverses cavernous-sinus |
| `approach-to` | `approached-via` | pterional targets anterior-circulation |
| `drains-to` | `drained-by` | basal-vein drains-to vein-of-Galen |

### 6 Teaching Canvases

Interactive surgical decision trees and anatomical maps:

- **Circle of Willis** — Complete arterial circle with perforator branches
- **Herniation Syndromes** — Uncal/central/tonsillar flow with CN findings
- **Posterior Fossa Approaches** — Target-based approach decision tree
- **Cranial Nerve Exit Map** — CN I–XII: nucleus to cistern to foramen
- **Anterior Circulation Aneurysms** — ICA bifurcation sites to approach selection
- **Cavernous Sinus Triangles** — 7 surgical windows spatial layout

### Study Tools

- **329 Anki-ready flashcards** (`_quizzes/anki-export.csv`)
- **20 viva-mode oral exam questions** with multi-hop model answers
- **Approach selection quiz** — 10 case-based scenarios
- **Tag-based filtering** — generate quizzes for specific topics

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full three-layer design, skill pipeline, and data flow. The short version:

```
rhoton-wiki/vault/
  concepts/          # 64 anatomical structures, cisterns, regions
  entities/          # 52 arteries, veins, nerves
  synthesis/         # 18 cross-cutting synthesis pages
  references/        # 14 surgical approaches
  _meta/             # 3 meta pages (taxonomy, plugin roles, sync config)
  _canvases/         # 6 teaching canvases (.canvas)
  _quizzes/          # Flashcards, viva questions, Anki CSV
  .obsidian/         # Pre-configured plugins
  index.md           # Master index (148 content + 3 meta = 151 total)
  log.md             # Operation log
  .manifest.json     # Source tracking ledger
```

---

## Skills (Agent Capabilities)

This project is a skill-based framework. AI agents (Claude Code, Cursor, Windsurf, Codex, Gemini) read `.skills/` to know how to operate the wiki. No scripts or dependencies are required — the agent **is** the LLM.

### Core Pipeline

| Skill | Purpose |
|-------|---------|
| `wiki-setup` | Initialize vault structure, directories, index, and log |
| `wiki-ingest` | Distill source documents into wiki pages (append or full mode) |
| `wiki-status` | Show ingestion delta, recommend actions, graph insights |
| `wiki-query` | Answer questions from compiled wiki with citations |
| `wiki-lint` | Audit health: orphans, broken links, contradictions, stale content |
| `wiki-update` | Sync knowledge from any project into the vault |
| `wiki-rebuild` | Archive current wiki and rebuild from scratch |
| `wiki-export` | Export graph to JSON, GraphML, Neo4j Cypher, or interactive HTML |

### Content Skills

| Skill | Purpose |
|-------|---------|
| `data-ingest` | Ingest any raw text: chat exports, logs, transcripts, images |
| `claude-history-ingest` | Mine ~/.claude conversations and memories into wiki pages |
| `cross-linker` | Auto-discover and insert missing wikilinks |
| `tag-taxonomy` | Enforce consistent tag vocabulary via canonical taxonomy |

### Domain-Specific Skills (Rhoton Wiki)

| Skill | Purpose |
|-------|---------|
| `quiz-mode` | Generate flashcards, viva questions, and Anki exports |
| `ncx-bridge` | Bridge wiki to clinical data: operative notes, case logs, journal clubs |

### Meta Skills

| Skill | Purpose |
|-------|---------|
| `llm-wiki` | Core pattern reference — three-layer architecture and page templates |
| `skill-creator` | Create, iterate, and benchmark new skills |

---

## Agent Compatibility

| Agent | Bootstrap File | Skills Directory |
|-------|---------------|-----------------|
| Claude Code | `CLAUDE.md` | `.claude/skills/` |
| Cursor | `.cursor/rules/obsidian-wiki.mdc` | `.cursor/skills/` |
| Windsurf | `.windsurf/rules/obsidian-wiki.md` | `.windsurf/skills/` |
| Codex | `AGENTS.md` | `~/.codex/skills/` |
| Antigravity | `GEMINI.md` | `~/.gemini/antigravity/skills/` |
| OpenClaw | `AGENTS.md` | `.agents/skills/` |

All bootstrap files (`CLAUDE.md`, `GEMINI.md`) are symlinks to `AGENTS.md`, the single source of truth.

---

## For Neurosurgery Residents

Recommended study workflow:

1. **Browse** the graph view to explore anatomical relationships
2. **Use ExcaliBrain** to navigate hierarchies (posterior fossa > cerebellum > peduncles)
3. **Open canvases** for visual decision trees before cases
4. **Import flashcards** to Anki for spaced repetition
5. **Run viva questions** with a study partner
6. **Add your own cases** via the `ncx-bridge` skill after surgeries

---

## Built With

- **Source:** Rhoton — Cranial Anatomy and Surgical Approaches, Thieme (2023)
- **Framework:** [obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) (Karpathy LLM Wiki pattern)
- **Agent:** [Claude Code](https://claude.ai/code) with [oh-my-claudecode](https://github.com/nicobailey-llc/oh-my-claudecode)
- **Method:** 150 autoresearch iterations + 8-phase evolution pipeline
- **Viewer:** [Obsidian](https://obsidian.md)

---

## License

Educational use. Source material: Rhoton — Cranial Anatomy and Surgical Approaches, Thieme (2023).
