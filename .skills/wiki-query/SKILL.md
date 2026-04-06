---
name: wiki-query
description: >
  Answer questions by searching the compiled Obsidian wiki. Use this skill when the user asks a question
  about their knowledge base, wants to find information across their wiki, asks "what do I know about X",
  "find everything related to Y", or wants synthesized answers with citations from their wiki pages.
  Also use when the user wants to explore connections between topics in their wiki. Works from any project.
---

# Wiki Query — Knowledge Retrieval

You are answering questions against a compiled Obsidian wiki, not raw source documents. The wiki contains pre-synthesized, cross-referenced knowledge.

## Before You Start

1. Read `~/.obsidian-wiki/config` to get `OBSIDIAN_VAULT_PATH` (works from any project). Fall back to `.env` if you're inside the obsidian-wiki repo.
2. Read `$OBSIDIAN_VAULT_PATH/index.md` to understand the wiki's scope and structure

## Query Process

### Step 1: Understand the Question

Classify the query type:
- **Factual lookup** — "What is X?" → Find the relevant page(s)
- **Relationship query** — "How does X relate to Y?" → Find both pages and their cross-references
- **Synthesis query** — "What's the current thinking on X?" → Find all pages that touch X, synthesize
- **Gap query** — "What don't I know about X?" → Find what's missing, check open questions sections

### Step 2: Search the Wiki

Use Grep and Glob to search `OBSIDIAN_VAULT_PATH`:
- Search page titles and filenames first (Glob `**/*.md`)
- Then search content for the query terms (Grep)
- Follow `[[wikilinks]]` from found pages to discover related content
- Check the `tags` in frontmatter for thematic matches

### Step 3: Read Relevant Pages

Read the pages you found. Pay attention to:
- The main content (the distilled knowledge)
- The `sources` frontmatter (for citations)
- The `[[wikilinks]]` (for related pages you should also read)
- The "Open Questions" sections (for known gaps)

### Step 4: Synthesize an Answer

Compose your answer from wiki content:
- Cite specific wiki pages using `[[page-name]]` notation
- If the wiki has contradictions, present both sides
- If the wiki doesn't cover something, say so explicitly
- Suggest which sources might fill the gap

### Step 5: Log the Query

Append to `log.md`:
```
- [TIMESTAMP] QUERY query="the user's question" result_pages=N
```

## Answer Format

Structure answers like this:

> **Based on the wiki:**
>
> [Your synthesized answer with [[wikilinks]] to source pages]
>
> **Pages consulted:** [[page-a]], [[page-b]], [[page-c]]
>
> **Gaps:** [What the wiki doesn't cover that might be relevant]
