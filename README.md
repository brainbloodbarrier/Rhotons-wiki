<p align="center">
  <img src="https://img.shields.io/badge/Pages-161-blue?style=for-the-badge" alt="Pages"/>
  <img src="https://img.shields.io/badge/Wikilinks-8469-green?style=for-the-badge" alt="Wikilinks"/>
  <img src="https://img.shields.io/badge/Figures-884-red?style=for-the-badge" alt="Figures"/>
  <img src="https://img.shields.io/badge/Words-127K-teal?style=for-the-badge" alt="Words"/>
  <img src="https://img.shields.io/badge/Flashcards-329-orange?style=for-the-badge" alt="Flashcards"/>
  <img src="https://img.shields.io/badge/Canvases-6-purple?style=for-the-badge" alt="Canvases"/>
  <img src="https://img.shields.io/badge/Obsidian-Ready-7C3AED?style=for-the-badge&logo=obsidian&logoColor=white" alt="Obsidian"/>
</p>

# Rhoton's Wiki

The complete microsurgical neuroanatomy knowledge base compiled from Albert Rhoton's *Cranial Anatomy and Surgical Approaches* (Thieme, 2023) — all **20 chapters**, all **3 parts**, all **1,668 pages** distilled into an interconnected Obsidian vault.

161 wiki pages. 884 anatomical figures. 8,469 cross-references. 6 interactive teaching canvases. Built autonomously through 170 autoresearch iterations across two evolutionary campaigns.

---

## Quick Start

```bash
git clone https://github.com/brainbloodbarrier/Rhotons-wiki.git
```

Open `rhoton-wiki/vault/` as an Obsidian vault. Install community plugins, enable them, done.

### Plugins (all configs pre-set in `.obsidian/`)

| Plugin | Purpose |
|--------|---------|
| **Dataview** | Structured queries across frontmatter |
| **Breadcrumbs** | Typed relation traversal (parent, branch-of, innervates...) |
| **ExcaliBrain** | Ego-graph hierarchical navigation |
| **Smart Connections** | AI-powered similarity discovery (`bge-micro-v2` local) |
| **Advanced Canvas** | Teaching flowcharts and decision trees |

---

## Content

### 155 Anatomy Pages + 6 Meta

| Category | Count | Scope |
|----------|-------|-------|
| **Concepts** | 69 | Cisterns, ventricles, fossa, incisural spaces, brainstem, cerebrum |
| **Entities** | 52 | ICA, MCA, PCA, PICA, SCA, CN III-XII, vein of Galen, lenticulostriates |
| **Synthesis** | 20 | Perforating arteries, aneurysm surgery, herniation syndromes, NVC |
| **References** | 14 | Pterional, retrosigmoid, telovelar, far-lateral, combined petrosal |
| **Quizzes** | 3 | Flashcards, viva questions, approach selection |
| **Meta** | 3 | Taxonomy, plugin roles, sync config |

### 20 Chapters Covered

| Part | Chapters | Content |
|------|----------|---------|
| **I** | 1 | Operative techniques and instrumentation |
| **II** | 2-10 | Cerebrum, arteries, aneurysms, veins, ventricles, cranial base, sellar region, orbit, temporal bone |
| **III** | 11-20 | CP angle, tentorial incisura, foramen magnum, posterior fossa approaches, middle fossa, jugular foramen, basal cisterns |

### 884 Anatomical Figures

Every figure from the Datalab extraction pipeline, catalogued with attribution, confidence level, and source page:

| Confidence | Count | Status |
|------------|-------|--------|
| High | 628 | Embedded with caption |
| Medium | 161 | Embedded with caption |
| Low | 63 | Catalogued, not embedded |
| Unattributed | 32 | Catalogued, not embedded |

Figures live in `vault/_attachments/figures/` and are embedded inline as `![[figure.jpg]]` with italicized captions linking to relevant wiki pages.

### Semantic Relations (Breadcrumbs)

Six typed relation pairs in frontmatter model neuroanatomy formally:

```
parent ↔ child          posterior-fossa → cerebellum
branch-of ↔ branches    PICA → vertebral-artery
innervates ↔ innervated-by    CN III → extraocular-muscles
traverses ↔ traversed-by      CN VI → cavernous-sinus
approach-to ↔ approached-via   pterional → anterior-circulation
drains-to ↔ drained-by        basal-vein → vein-of-Galen
```

### 48 Canonical Tags

Controlled vocabulary enforced across all pages. Categories: region (19), system (11), circulation (4), surgical (5), clinical (5), meta (3), domain (1).

### 6 Teaching Canvases

| Canvas | Content |
|--------|---------|
| Circle of Willis | Arterial circle with perforator branches |
| Herniation Syndromes | Uncal/central/tonsillar flow with CN findings |
| Posterior Fossa Approaches | Target-based approach decision tree |
| Cranial Nerve Exit Map | CN I-XII: nucleus to cistern to foramen |
| Anterior Circulation Aneurysms | Bifurcation sites to approach selection |
| Cavernous Sinus Triangles | 7 surgical windows spatial layout |

### Study Tools

- **329 Anki-ready flashcards** (`_quizzes/anki-export.csv`)
- **20 viva-mode oral exam questions** with multi-hop model answers
- **Approach selection quiz** with case-based scenarios

---

## How It Was Built

### Campaign 1 — Page Creation (150 iterations)

Starting from zero, 139 wiki pages compiled from Rhoton chapters 1-15. Each iteration: create or augment pages, verify score, validate frontmatter, keep or discard.

### Campaign 2 — Datalab Augmentation (20 iterations)

All 20 chapters extracted via Datalab (PDF to structured markdown + 884 figures). Each chapter augmented existing pages with new anatomical detail:

- Trigeminal root somatotopy and NVC compression data
- 3-category approach classification for foramen magnum
- Inter-cisternal arachnoid membrane taxonomy
- Transcondylar/paracondylar approach variants
- Cavernous sinus extradural dissection technique

### Post-Campaign Passes

- **Figure integration:** 787 high/medium-confidence figures embedded across 41 pages
- **Cross-linking:** 440 new wikilinks via automated registry matching
- **Alias expansion:** 7 curated aliases validated through adversarial reasoning
- **Tag normalization:** Non-canonical tags corrected to controlled vocabulary

### Evolution Metric

```
Score = (pages * 10) + (wikilinks * 2) + (words / 100)
```

| Milestone | Score |
|-----------|-------|
| Campaign 1 complete (150 iterations) | 11,587 |
| Campaign 2 complete (20 iterations) | 11,947 |
| Figure integration + cross-linking | 14,434 |

---

## Vault Structure

```
rhoton-wiki/vault/
  concepts/          # 69 anatomical structures, cisterns, regions
  entities/          # 52 arteries, veins, nerves
  synthesis/         # 20 cross-cutting synthesis pages
  references/        # 14 surgical approaches
  _meta/             # Taxonomy, plugin roles, sync config
  _canvases/         # 6 teaching canvases (.canvas)
  _quizzes/          # Flashcards, viva questions, Anki CSV
  _attachments/      # 884 anatomical figures
  .obsidian/         # Pre-configured plugins
```

---

## Skills (Agent Capabilities)

Skill-based framework. AI agents read `.skills/` to operate the wiki. No scripts or dependencies — the agent IS the runtime.

| Skill | Purpose |
|-------|---------|
| `wiki-ingest` | Distill source documents into wiki pages |
| `wiki-status` | Show delta, recommend actions, graph insights |
| `wiki-query` | Answer questions from compiled wiki with citations |
| `wiki-lint` | Audit: orphans, broken links, contradictions |
| `cross-linker` | Auto-discover and insert missing wikilinks |
| `tag-taxonomy` | Enforce controlled tag vocabulary |
| `quiz-mode` | Generate flashcards, viva questions, Anki exports |
| `wiki-export` | Export to JSON, GraphML, Neo4j Cypher, interactive HTML |

### Agent Compatibility

| Agent | Bootstrap | Skills |
|-------|-----------|--------|
| Claude Code | `CLAUDE.md` | `.skills/` |
| Cursor | `.cursor/rules/` | `.cursor/skills/` |
| Windsurf | `.windsurf/rules/` | `.windsurf/skills/` |
| Codex | `AGENTS.md` | `~/.codex/skills/` |
| Gemini | `GEMINI.md` | `~/.gemini/skills/` |

---

## For Neurosurgery Residents

1. **Graph view** (Cmd+G) for anatomical relationship overview
2. **ExcaliBrain** for hierarchical navigation (posterior fossa > cerebellum > peduncles)
3. **Canvases** for visual decision trees before cases
4. **Flashcards** to Anki for spaced repetition
5. **Viva questions** with a study partner for oral exam prep
6. **Add your own cases** via the `ncx-bridge` skill after surgeries

---

## Built With

| Component | Tool |
|-----------|------|
| Source | Rhoton — *Cranial Anatomy and Surgical Approaches*, Thieme (2023) |
| Extraction | [Datalab](https://github.com/VikParuchuri/marker) PDF to Markdown + Figures |
| Compilation | [Claude Code](https://claude.ai/code) with autoresearch |
| Orchestration | [oh-my-claudecode](https://github.com/nicobailey-llc/oh-my-claudecode) |
| Viewer | [Obsidian](https://obsidian.md) |
| Pattern | [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) |

---

## License

Educational use. Source material: Rhoton — *Cranial Anatomy and Surgical Approaches*, Thieme (2023).
