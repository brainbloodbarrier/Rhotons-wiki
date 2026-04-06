---
name: wiki-status
description: >
  Show the current state of the wiki — what's been ingested, what's pending, and the delta between sources
  and wiki content. Use this skill when the user asks "what's the status", "how much is ingested",
  "what's left to process", "show me the delta", "what changed since last ingest", "wiki dashboard",
  or wants an overview of their knowledge base health and completeness. Also use before deciding whether
  to append or rebuild.
---

# Wiki Status — Audit & Delta

You are computing the current state of the wiki: what's been ingested, what's new since last ingest, and what the delta looks like. This helps the user decide whether to append (ingest the delta) or rebuild (archive and reprocess everything).

## Before You Start

1. Read `.env` to get `OBSIDIAN_VAULT_PATH`, `OBSIDIAN_SOURCES_DIR`, `CLAUDE_HISTORY_PATH`
2. Read `.manifest.json` at the vault root — this is the ingest tracking ledger

## The Manifest

The manifest lives at `$OBSIDIAN_VAULT_PATH/.manifest.json`. It tracks every source file that has been ingested. If it doesn't exist, this is a fresh vault with nothing ingested.

```json
{
  "version": 1,
  "last_updated": "2026-04-06T10:30:00Z",
  "sources": {
    "/absolute/path/to/file.md": {
      "ingested_at": "2026-04-06T10:30:00Z",
      "size_bytes": 4523,
      "modified_at": "2026-04-05T08:00:00Z",
      "source_type": "document",
      "project": null,
      "pages_created": ["concepts/transformers.md"],
      "pages_updated": ["entities/vaswani.md"]
    },
    "~/.claude/projects/-Users-name-my-app/abc123.jsonl": {
      "ingested_at": "2026-04-06T11:00:00Z",
      "size_bytes": 128000,
      "modified_at": "2026-04-06T09:00:00Z",
      "source_type": "claude_conversation",
      "project": "my-app",
      "pages_created": ["entities/my-app.md"],
      "pages_updated": ["skills/react-debugging.md"]
    }
  },
  "projects": {
    "my-app": {
      "source_path": "~/.claude/projects/-Users-name-my-app",
      "vault_path": "projects/my-app",
      "last_ingested": "2026-04-06T11:00:00Z",
      "conversations_ingested": 5,
      "conversations_total": 8,
      "memory_files_ingested": 3
    }
  },
  "stats": {
    "total_sources_ingested": 42,
    "total_pages": 87,
    "total_projects": 6,
    "last_full_rebuild": null
  }
}
```

## Step 1: Scan Current Sources

Build an inventory of everything available to ingest right now:

### Documents (from `OBSIDIAN_SOURCES_DIR`)
```
Glob each directory in OBSIDIAN_SOURCES_DIR for all text files
Record: path, size, modification time
```

### Claude History (from `CLAUDE_HISTORY_PATH`)
```
Glob: ~/.claude/projects/*/          → project directories
Glob: ~/.claude/projects/*/*.jsonl   → conversation files
Glob: ~/.claude/projects/*/memory/*.md → memory files
Record: path, size, modification time, parent project
```

### Any other sources the user has pointed at previously
Check the manifest for source paths outside the standard directories.

## Step 2: Compute the Delta

Compare current sources against the manifest. Classify each source file:

| Status | Meaning | Action needed |
|---|---|---|
| **New** | File exists on disk, not in manifest | Needs ingesting |
| **Modified** | File in manifest, but `modified_at` on disk is newer than `ingested_at` | Needs re-ingesting |
| **Unchanged** | File in manifest, not modified since ingest | Nothing to do |
| **Deleted** | In manifest, but file no longer exists on disk | Note it — wiki pages may be stale |

For Claude history specifically, also compute:
- New projects (directories in `~/.claude/projects/` not in manifest)
- New conversations within existing projects
- Updated memory files

## Step 3: Report the Status

Present a clear summary:

```markdown
# Wiki Status

## Overview
- **Total wiki pages:** 87 across 6 categories
- **Total sources ingested:** 42
- **Projects tracked:** 6
- **Last ingest:** 2026-04-06T11:00:00Z

## Delta (what's changed since last ingest)

### New sources (never ingested): 12
| Source | Type | Size |
|---|---|---|
| ~/Documents/research/new-paper.pdf | document | 2.1 MB |
| ~/.claude/projects/-Users-.../session-xyz.jsonl | claude_conversation | 340 KB |
| ... | | |

### Modified sources (need re-ingesting): 3
| Source | Last ingested | Last modified | Delta |
|---|---|---|---|
| ~/notes/architecture.md | 2026-04-01 | 2026-04-05 | 4 days newer |
| ... | | | |

### New projects (not yet in wiki): 2
- **tractorex** (3 conversations, 2 memory files)
- **papertech** (1 conversation, 0 memory files)

### Deleted sources (ingested but gone): 0

## Summary
- **Ready to ingest:** 12 new + 3 modified = 15 sources
- **Up to date:** 27 sources unchanged
- **Recommendation:** Append (delta is small relative to total)
```

## Step 4: Recommend Action

Based on the delta, recommend one of:

| Situation | Recommendation |
|---|---|
| Delta is small (<20% of total) | **Append** — just ingest the new/modified sources |
| Delta is large (>50% of total) | **Rebuild** — archive and reprocess everything |
| Many deleted sources | **Lint first** — check for stale pages, then decide |
| First time / empty vault | **Full ingest** — process everything |
| User just wants to see status | **No action** — just report |

Tell the user:
- "You have X new sources and Y modified sources. I'd recommend [append/rebuild]."
- "Want me to [ingest the delta / rebuild from scratch / just look at a specific project]?"

## Notes

- If the manifest doesn't exist, report everything as "new" and recommend a full ingest
- This skill only reads and reports — it doesn't modify anything
- The actual ingest work is done by the ingest skills (`wiki-ingest`, `claude-history-ingest`, `data-ingest`)
- Those skills are responsible for updating the manifest after they finish
