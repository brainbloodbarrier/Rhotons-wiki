---
title: Plugin Roles
category: meta
tags:
  - meta
summary: >-
  # Plugin Roles — 4-Layer Architecture
---

# Plugin Roles — 4-Layer Architecture

No-overlap rule: each layer has exclusive responsibility. Do not use one layer's plugin for another layer's job.

## Layer 1: Semantic Relations — Breadcrumbs
**Exclusive role:** Formal typed relations between pages.
- `parent`/`child` — anatomical containment
- `branch-of`/`branches` — vascular hierarchy
- `innervates`/`innervated-by` — neural targets
- `traverses`/`traversed-by` — spatial transit
- `approach-to`/`approached-via` — surgical corridors
- `drains-to`/`drained-by` — venous drainage

**Do NOT use:** Smart Connections for formal relations. Breadcrumbs = declared truth.

## Layer 2: Visual Navigation — ExcaliBrain
**Exclusive role:** Ego-graph navigation using Breadcrumbs relations.
- Parent/child → hierarchical tree
- Same → lateral associations
- Max depth 2 (M1 8GB memory-safe)
- Node colors by folder: concepts=blue, entities=green, synthesis=orange, references=red

**Do NOT use:** Juggl (overlaps with ExcaliBrain). Extended-graph handles global overview.

## Layer 3: Presentation — Advanced Canvas
**Exclusive role:** Curated teaching flowcharts and decision trees.
- Surgical approach decision trees
- Anatomical relationship diagrams
- Canvas files in `_canvases/` directory
- NOT a replacement for the graph view

**Do NOT use:** For auto-generated knowledge maps. Canvas = hand-curated editorial content.

## Layer 4: AI Discovery — Smart Connections
**Exclusive role:** Similarity-based discovery via embeddings.
- "Similar notes" panel for serendipitous connections
- Chat with notes for natural language queries
- Local embeddings (bge-micro-v2) — no API calls

**Do NOT use:** For formal relations. Smart Connections = probabilistic suggestions only.

## Supporting Plugins
- **Dataview** — query engine for frontmatter (tables, lists, tasks)
- **Extended Graph** — global graph view with tag/folder coloring and arrows
- **Node Auto-resize** — scale nodes by link count in graph
- **Persistent Graph** — remember graph view state
