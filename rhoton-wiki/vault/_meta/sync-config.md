---
title: Sync Configuration
category: meta
tags:
  - meta
summary: >-
  # Syncthing Sync Strategy
---

# Syncthing Sync Strategy

## What Syncs
- All `*.md` files (vault content)
- `_canvases/*.canvas` (teaching flowcharts)
- `_quizzes/*` (flashcards, Anki exports)
- `_meta/*` (taxonomy, plugin-roles, this file)
- `.manifest.json` (source tracking)
- `attachments/figures/*` (optional — large)

## What Does NOT Sync
- `.obsidian/workspace.json` (device-specific layout)
- `.obsidian/workspace-mobile.json` (mobile layout)
- `.smart-connections/` (device-local embeddings)
- `.smart-env/` (Smart Connections environment)
- `.trash/` (Obsidian trash)

## .stignore
Place at vault root. Contents:
```
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.smart-connections/
.smart-env/
.trash/
```

## Per-Device Plugin Rebuilds
Each device must rebuild its own:
- Smart Connections embedding index
- Dataview cache
- ExcaliBrain node cache
- Extended-graph layout state
