---
name: ncx-bridge
description: >
  Bridge the Rhoton Wiki to the NCX (Neurosurgery Context) pipeline.
  Trigger on: "ncx", "operative note", "case log", "journal club",
  "surgical case", "link case", "ingest case", "clinical data".
---

# NCX Bridge — Clinical Pipeline Integration

Connect the Rhoton anatomical wiki to real-world clinical data: operative notes, case logs, journal clubs, and imaging findings.

## Before You Start

1. Read `.env` for `OBSIDIAN_VAULT_PATH`
2. Read `index.md` for full page inventory
3. Check if NCX data pipeline exists at `data/` or external path

## Ingest Modes

### 1. Operative Note Ingest
Distill anatomy encountered in real surgical cases into wiki annotations.

**Input:** Operative note text (paste or file)
**Process:**
1. Parse anatomical structures mentioned in the note
2. Match to existing wiki pages (title/alias lookup)
3. For each match, add a `## Case Experience` entry to the wiki page:
   ```markdown
   ## Case Experience
   - **2026-04-15** — Aberrant AICA loop encountered in CPA during VS resection.
     Meatal loop extended 5mm beyond porus. Preserved with microsurgical dissection.
   ```
4. If a structure is mentioned that has no wiki page, flag for potential page creation.

### 2. Journal Club Ingest
Add recent literature that confirms or updates Rhoton's descriptions.

**Input:** Paper citation + key finding
**Process:**
1. Match finding to relevant wiki page(s)
2. Add to `## Recent Literature` section:
   ```markdown
   ## Recent Literature
   - Smith et al. (2025) — Described a 15% incidence of accessory MMA from
     ophthalmic artery in 200 CT angiograms. *Updates Rhoton Ch.7 frequency data.*
   ```

### 3. Case-Based Learning Link
Link surgical cases to approach pages for pattern recognition.

**Input:** Case summary (diagnosis, location, approach used, outcome)
**Process:**
1. Identify the surgical approach used → link to `references/` page
2. Identify anatomy encountered → link to `concepts/` and `entities/` pages
3. Add bidirectional links: case → approach, approach → case

## Syncthing Configuration

### .stignore patterns
```
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.smart-connections/
.smart-env/
.trash/
*.canvas.bak
```

### Sync Strategy
- **Vault markdown** — sync everywhere (macOS, Android via Obsidian Mobile)
- **Attachments/figures** — sync selectively (large files, optional on mobile)
- **Plugin data** — device-local (each device rebuilds its own indexes)
- **Embeddings** — never sync (.smart-connections/ is in .gitignore)

## Output
- Modified wiki pages with `## Case Experience` or `## Recent Literature` sections
- Updated `log.md` with ingest record
- Flagged unmatched structures for potential new page creation
