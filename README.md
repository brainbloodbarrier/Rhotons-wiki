<p align="center">
  <img src="https://img.shields.io/badge/Pages-151-blue?style=for-the-badge" alt="Pages"/>
  <img src="https://img.shields.io/badge/Wikilinks-3000%2B-green?style=for-the-badge" alt="Wikilinks"/>
  <img src="https://img.shields.io/badge/Flashcards-329-orange?style=for-the-badge" alt="Flashcards"/>
  <img src="https://img.shields.io/badge/Canvases-6-purple?style=for-the-badge" alt="Canvases"/>
  <img src="https://img.shields.io/badge/Obsidian-Ready-7C3AED?style=for-the-badge&logo=obsidian&logoColor=white" alt="Obsidian"/>
</p>

# Rhoton's Wiki

**A comprehensive microsurgical neuroanatomy knowledge base** built from Albert Rhoton's *Cranial Anatomy and Surgical Approaches* (2023, 1668 pages, 15 chapters). 151 interconnected pages covering every major arterial, venous, neural, and cisternal structure relevant to neurosurgical practice.

Built with the [obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) framework (LLM Wiki pattern by [Karpathy](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)) and compiled autonomously via 150 iterations of autoresearch + 8-phase evolution pipeline.

---

## What's Inside

### 151 Anatomical Pages

| Category | Count | Examples |
|----------|-------|---------|
| **Concepts** | 67 | Basal cisterns, internal capsule, choroidal fissure, tentorial incisura |
| **Entities** | 52 | ICA, MCA, PCA, CN III-XII, vein of Galen, lenticulostriates |
| **Synthesis** | 18 | Perforating arteries map, aneurysm surgery, herniation syndromes, cistern-approach map |
| **References** | 14 | Pterional, retrosigmoid, telovelar, combined petrosal, endoscopic endonasal |

### Semantic Architecture (Breadcrumbs)

Six typed relations model neuroanatomy formally:

| Relation | Inverse | Use |
|----------|---------|-----|
| `parent` / `child` | Anatomical containment | *posterior-fossa contains cerebellum* |
| `branch-of` / `branches` | Vascular hierarchy | *PICA is branch-of vertebral-artery* |
| `innervates` / `innervated-by` | Neural targets | *CN III innervates extraocular-muscles* |
| `traverses` / `traversed-by` | Spatial transit | *CN VI traverses cavernous-sinus* |
| `approach-to` / `approached-via` | Surgical corridors | *pterional-approach targets anterior-circulation* |
| `drains-to` / `drained-by` | Venous drainage | *basal-vein drains-to vein-of-Galen* |

### 4-Layer Plugin Stack

| Layer | Plugin | Role |
|-------|--------|------|
| 1. Semantics | **Breadcrumbs** | Formal typed relations |
| 2. Navigation | **ExcaliBrain** | Ego-graph hierarchical navigation |
| 3. Presentation | **Advanced Canvas** | Teaching flowcharts & decision trees |
| 4. Discovery | **Smart Connections** | AI-powered similarity suggestions |

Supporting: Dataview (queries), Extended Graph (global view with folder coloring + arrows), Node Auto-resize, Persistent Graph.

### 6 Teaching Canvases

Interactive surgical decision trees and anatomical maps:

- **Circle of Willis** --- Complete arterial circle with perforator branches
- **Herniation Syndromes** --- Uncal/central/tonsillar flow with CN findings
- **Posterior Fossa Approaches** --- Target-based approach decision tree
- **Cranial Nerve Exit Map** --- CN I-XII: nucleus to cistern to foramen
- **Anterior Circulation Aneurysms** --- ICA bifurcation sites to approach selection
- **Cavernous Sinus Triangles** --- 7 surgical windows spatial layout

### Study Tools

- **329 Anki-ready flashcards** (`_quizzes/anki-export.csv`)
- **20 viva-mode oral exam questions** with multi-hop model answers
- **Approach selection quiz** --- 10 case-based scenarios
- **Tag-based filtering** --- generate quizzes for specific topics

---

## Quick Start

### 1. Clone and open in Obsidian

```bash
git clone https://github.com/brainbloodbarrier/Rhotons-wiki.git
cd Rhotons-wiki
```

Open `rhoton-wiki/vault/` as an Obsidian vault.

### 2. Install community plugins (one-time)

In Obsidian > Settings > Community Plugins > Browse:

1. Dataview
2. Breadcrumbs
3. ExcaliBrain
4. Smart Connections (choose `bge-micro-v2` local model)
5. Advanced Canvas

All plugin configs are pre-written --- just install and enable.

### 3. Explore

- **Cmd+G** --- Global graph view (color-coded by category)
- **ExcaliBrain** --- Click any page for ego-graph navigation
- Open `_canvases/` --- Interactive teaching flowcharts
- Open `_quizzes/flashcards-all.md` --- Study flashcards

---

## Architecture

```
rhoton-wiki/vault/
  concepts/          # 67 anatomical structures, cisterns, regions
  entities/          # 52 arteries, veins, nerves, other structures
  synthesis/         # 18 cross-cutting synthesis pages
  references/        # 14 surgical approaches
  _meta/             # Taxonomy, plugin roles, sync config
  _canvases/         # 6 teaching canvases (.canvas)
  _quizzes/          # Flashcards, viva questions, Anki CSV
  .obsidian/         # Pre-configured plugins
  index.md           # Master index with 151 page inventory
  log.md             # Operation log
  .manifest.json     # Source tracking
  .stignore          # Syncthing ignore patterns
```

### Score Metrics

| Metric | Value |
|--------|-------|
| Pages | 151 |
| Wikilinks | 3000+ |
| Typed Relations | 104 pages annotated |
| Frontmatter Fields | title, category, tags, sources, summary, aliases, parent, approach-to, drains-to |
| Guard Check | All pages pass (frontmatter validated) |

---

## Built With

- **Source:** Rhoton - Cranial Anatomy and Surgical Approaches (2023)
- **Framework:** [obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) (Karpathy LLM Wiki pattern)
- **Agent:** [Claude Code](https://claude.ai/code) with [oh-my-claudecode](https://github.com/nicobailey-llc/oh-my-claudecode)
- **Method:** 150 autoresearch iterations (autonomous modify-verify-keep/discard loop) + 8-phase evolution pipeline
- **Viewer:** [Obsidian](https://obsidian.md)

---

## Skills

Two custom skills for extending the wiki:

| Skill | Trigger | What it does |
|-------|---------|-------------|
| `quiz-mode` | "quiz", "flashcards", "test me", "viva" | Generate flashcards and exam questions from wiki pages |
| `ncx-bridge` | "ncx", "operative note", "case log" | Bridge wiki to clinical data: operative notes, journal clubs, case logs |

Plus 14 inherited skills from the obsidian-wiki framework (wiki-ingest, cross-linker, wiki-query, wiki-lint, etc.).

---

## For Neurosurgery Residents

This wiki is designed for surgical anatomy study. Recommended workflow:

1. **Browse** the graph view to explore anatomical relationships
2. **Use ExcaliBrain** to navigate parent-child hierarchies (e.g., posterior fossa > cerebellum > peduncles)
3. **Open canvases** for visual decision trees before cases
4. **Import flashcards** to Anki for spaced repetition
5. **Run viva questions** with a study partner
6. **Add your own cases** via the NCX bridge skill after surgeries

---

## License

Educational use. Source material: Rhoton - Cranial Anatomy and Surgical Approaches, Thieme (2023).

---

<details>
<summary><h2>Original obsidian-wiki Framework Documentation</h2></summary>

A knowledge mgmt system inspired by [gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) published by Andrej Karpathy about maintaining a personal knowledge base with LLMs : the "LLM Wiki" pattern.

Instead of asking an LLM the same questions over over (or doing RAG every time), you compile knowledge once into interconnected markdown files and keep them current. In this case Obsidian is the viewer and the LLM is the maintainer.

We took that and built a framework around it. The whole thing is a set of markdown skill files that any AI coding agent (Claude Code, Cursor, Windsurf, whatever you use) can read and execute. You point it at your Obsidian vault and tell it what to do.

### Quick Start

```bash
git clone https://github.com/Ar9av/obsidian-wiki.git
cd obsidian-wiki
bash setup.sh
```

### Agent Compatibility

| Agent | Bootstrap File | Skills Directory |
|-------|---------------|-----------------|
| **Claude Code** | `CLAUDE.md` | `.claude/skills/` |
| **Cursor** | `.cursor/rules/obsidian-wiki.mdc` | `.cursor/skills/` |
| **Windsurf** | `.windsurf/rules/obsidian-wiki.md` | `.windsurf/skills/` |
| **Codex** | `AGENTS.md` | `~/.codex/skills/` |
| **Antigravity** | `GEMINI.md` | `~/.gemini/antigravity/skills/` |
| **OpenClaw** | `AGENTS.md` | `.agents/skills/` |

### Skills

| Skill | What it does |
|-------|-------------|
| `wiki-setup` | Initialize vault structure |
| `wiki-ingest` | Distill documents into wiki pages |
| `wiki-status` | Show ingestion status and delta |
| `wiki-query` | Answer questions from the wiki |
| `wiki-lint` | Find broken links, orphans, contradictions |
| `cross-linker` | Auto-discover and insert missing wikilinks |
| `tag-taxonomy` | Enforce consistent tag vocabulary |
| `wiki-export` | Export graph to JSON, GraphML, Neo4j, HTML |
| `wiki-rebuild` | Archive and rebuild from scratch |
| `wiki-update` | Sync current project knowledge into vault |

For full framework documentation, see the [original repo](https://github.com/Ar9av/obsidian-wiki).

</details>
