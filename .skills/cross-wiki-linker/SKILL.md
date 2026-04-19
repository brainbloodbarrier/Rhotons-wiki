---
title: Cross-Wiki Linker
description: Discovers semantic bridges between pages in different vaults and writes them to crossmap.json. Never modifies vault pages in default mode.
applies_to: [claude-code, opencode, cursor, windsurf, codex]
version: "1.0.0"
---

# Cross-Wiki Linker

## Purpose

Finds semantic relationships between pages that live in **different** wikis
(rhoton ↔ ncx, rhoton ↔ nsatlas, ncx ↔ nsatlas) and records them in
`crossmap.json`. Bridges are stored **only** in `crossmap.json` by default —
vault page bodies are never modified, preserving the byte-identical invariant.

This skill is distinct from `cross-linker`, which adds `[[wikilinks]]`
*within* a single vault.

## Relationship to `pages_index` and the migrator

`crossmap.json` now has two top-level fields used by different tools:

- `bridges[]` — **curated semantic relations** between pages in different
  vaults. Written by this skill. Used by `wiki-query` to surface related
  content across vaults; not consumed by the guard.
- `pages_index{}` — **mechanical lookup table** from normalized basename to
  `[{wiki, path}, ...]`. Written by `lib/crossmap-generate.sh`. Used by
  `lib/autoresearch-guard.sh` to validate `[[wiki:basename]]` syntax and
  by `lib/crosswiki-migrate.sh` to auto-convert bare cross-wiki wikilinks
  into markdown cross-links.

Do not conflate the two. Bridges express authorial intent (what relates
to what). pages_index is a generated index (what exists where). This
skill writes only `bridges`; it never touches `pages_index` (that is
`crossmap-generate.sh`'s responsibility, regenerated on demand).

For the cross-vault reference policy itself (which form to use in prose —
markdown link vs `[[wiki:basename]]` vs bare wikilink), see AGENTS.md
§ *Cross-Vault References*.

## Write Modes

| Mode | Flag | Behavior |
|---|---|---|
| `crossmap-only` | (default) | Writes bridges to `crossmap.json` only. Vaults untouched. |
| `frontmatter` | `--write-mode=frontmatter` | Also appends `cross-wiki-ref:` key to affected pages. **Requires user confirmation.** Relaxes byte-identical invariant. |

Default mode always passes the byte-identical check:
```bash
git diff --name-only HEAD -- '**/vault/**/*.md' | wc -l  # must be 0
```

## Invocation

User says any of:
- "cross-link wikis" / "bridge rhoton to ncx" / "find crossmap bridges"
- "populate crossmap" / "connect my wikis" / "cross-wiki links"
- `/cross-wiki-linker`

## Algorithm

### Step 1 — Load registry

```bash
source lib/resolve-wiki.sh <wiki>  # for each wiki in .config/wikis.json
```

Get all wiki names: `jq -r '.wikis | keys[]' .config/wikis.json`

### Step 2 — Index pages

For each wiki, list all vault pages (excluding `index.md`, `log.md`,
`_meta/`, `.obsidian/`, `.smart-env/`):

```bash
find "$VAULT" -name "*.md" \
  -not -path "*/.obsidian/*" \
  -not -path "*/.smart-env/*" \
  -not -name "index.md" \
  -not -name "log.md" \
  -not -path "*/_meta/*"
```

Extract per page:
- `basename` (normalized: lowercase, spaces→hyphens)
- `tags:` values from frontmatter (if present)
- `title:` from frontmatter

### Step 3 — Score pairs

For every pair `(page_A in wiki_X, page_B in wiki_Y)` where X ≠ Y:

1. **Title similarity** — Levenshtein ratio of normalized basenames. Weight: 0.6.
2. **Tag overlap** — Jaccard index of `tags:` sets. Weight: 0.3.
3. **Exact basename match** — override: if normalized basenames are identical, set `confidence = max(confidence, 0.95)` regardless of other terms. Weight in formula: 0.1.

```
confidence = 0.6 * title_sim + 0.3 * tag_jaccard + 0.1 * exact_match_bonus
if basenames_identical: confidence = max(confidence, 0.95)
```

Emit bridge when `confidence >= 0.75`. Bridges with `confidence >= 0.95`
are considered **exact matches** (same concept, different wiki context).

### Step 4 — Write crossmap.json

Schema:
```json
{
  "version": "1.0",
  "generated_at": "<ISO-8601>",
  "bridges": [
    {
      "wiki_a": "<name>",
      "page_a": "<vault-relative path>",
      "wiki_b": "<name>",
      "page_b": "<vault-relative path>",
      "confidence": 0.97,
      "rationale": "<one sentence>",
      "created_at": "<ISO-8601 date>"
    }
  ]
}
```

Merge strategy: existing bridges with matching `(wiki_a, page_a, wiki_b, page_b)`
are updated (confidence + rationale refreshed); new pairs are appended.
Bridges for pages that no longer exist in either vault are removed.

### Step 5 — Byte-identical check

After writing `crossmap.json`, verify no `.md` in any vault was touched:
```bash
git diff --name-only HEAD -- '**/vault/**/*.md'
# Expected: empty output
```

If any `.md` appears in the diff, abort with exit 1 and list the affected files.

### Step 6 — Frontmatter mode (opt-in only)

If `--write-mode=frontmatter` was passed:
1. Show the user a diff of every frontmatter change before applying.
2. Require explicit confirmation ("yes" / "y").
3. For each bridge, append to both pages' frontmatter:
   ```yaml
   cross-wiki-ref:
     - wiki: <other_wiki>
       page: <other_page>
       confidence: <float>
   ```
4. Re-run guard on affected wikis. Must pass.

## Stop Conditions

- No more page pairs above threshold (exhausted).
- `crossmap.json` grows by zero new bridges (convergence).
- User halts.

## Output

On completion, report:
- Total bridges written / updated / removed.
- Top-5 highest-confidence bridges.
- Any pages with zero outgoing cross-wiki bridges (potential isolation).

## Key Rules

- **Never** make network calls.
- **Never** modify vault `.md` files in `crossmap-only` mode.
- If `crossmap.json` does not exist, create it from scratch.
- Validate output JSON with `jq empty crossmap.json` before reporting done.
- Log to `.autoresearch/<wiki>/results.tsv` is optional (this skill spans wikis, not one wiki).
