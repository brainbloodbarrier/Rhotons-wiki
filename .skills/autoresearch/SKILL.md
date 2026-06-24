---
name: autoresearch
description: >
  Local terminal loop that iteratively grows an Obsidian wiki via the
  agent's own reasoning, gated on a measured quality metric and a
  structural guard between each step. Runs entirely inside Claude Code
  or OpenCode — no network in the loop. Use whenever the user says "run
  autoresearch", "grow the wiki", "iterate on the wiki", "continue the
  campaign", or drops `/autoresearch`. Multi-wiki aware via
  `.config/wikis.json`. The wikis are independent — no cross-wiki links.
applies_to:
  - claude-code
  - opencode
  - codex
version: 2.0.0
---

# Autoresearch — The Local Wiki-Growth Loop

**This is the core feature of the project.** You are the agent executing
the loop yourself inside the terminal. There is no separate runtime, no
remote API, no cron. Just you, a vault, and a git repo.

## Purpose

Autoresearch grows a wiki **from the inside out**. Each iteration picks
one focused action, executes it, and keeps it **only if it improves the
wiki's measured quality** without breaking structural integrity. Run it
by hand over weeks and the wiki compounds.

Quality is three independent dimensions, emitted by the guard
(`--format=json | jq .quality`):

- **coverage** — `pages`, `orphan_pages`, `orphan_ratio`
- **links_resolve** — `resolve_ratio` (1.0 = every `[[link]]` resolves)
- **breadcrumb_density** — fraction of non-scaffolding pages carrying
  ≥1 typed relation (`parent:`, `child:`, `branch-of:`, …)

**There is no single score.** That is deliberate. The old v1 scalar hid
regressions — it went *up* when you added a broken link and *down* when
a migration fixed links. Three raw ratios cannot be gamed by
aggregation; each is inspected on its own.

## Non-Negotiable Invariants

1. **Local only.** No outbound HTTP, no external MCP (Context7,
   WebFetch, WebSearch) inside an iteration. Your reasoning plus
   pre-extracted material in `<wiki>/extractions/` is the only input.
2. **One action per iteration.** Never bundle "create a page + fix tags
   + add links". One action; execute; measure.
3. **Atomic commits.** Kept iteration = one git commit. Discarded =
   `git checkout` restores the tree, no commit.
4. **Guard hard failure halts the loop.** A hard error means the vault
   is structurally broken. Fix it before iterating.
5. **Wikis are independent.** Every `[[link]]` resolves within its own
   vault. There are **no cross-vault links** — if a page needs a fact
   from another wiki, restate the fact, don't link across.
6. **Commit only on a non-main branch** (`autoresearch/<wiki>-campaign-N`).

## Preconditions

1. Clean working tree (`git status --porcelain` empty).
2. The target wiki's vault exists.
3. Guard passes on HEAD (`hard_errors == 0`).
4. A **narrow theme** for the next N iterations, chosen from what the
   metric shows. Examples: nsatlas `breadcrumb_density` is 0.0 → "add
   typed breadcrumbs to procedures"; a high `orphan_ratio` → "link the
   orphans"; a known gap → "create the missing cranial-nerve pages".
   Vague themes ("improve the wiki") drift — don't.

## The Loop

`$BASH` = `/opt/homebrew/bin/bash` (the guard needs bash ≥ 4; macOS
`/bin/bash` is 3.2 and breaks it). Run this for every iteration.

### 1 — Baseline
Capture current quality and confirm the vault is healthy.
```bash
source lib/resolve-wiki.sh <wiki>
Q_BEFORE=$($BASH lib/autoresearch-guard.sh <wiki> --format=json)
echo "$Q_BEFORE" | jq -e '.hard_errors == 0' >/dev/null \
  || { echo "baseline broken — halt"; exit 1; }
```

### 2 — Select one action
- **Create a page** — full frontmatter (title, category, tags, sources,
  created, updated), ≥1 typed breadcrumb, and a planned incoming link
  (don't strand it as an orphan).
- **Augment a page** — additive sections / breadcrumbs / wikilinks.
- **Cross-link (intra-wiki)** — wikilinks between existing pages in the
  same vault. Use the `cross-linker` skill.
- **Normalize taxonomy** — fix tags against `_meta/taxonomy.md`. Use
  `tag-taxonomy`.
- **Audit-fix** — a broken link, orphan, missing breadcrumb, or a
  leftover cross-wiki markdown link (strip it to plain text).

### 3 — Execute
Edit/create files under `<wiki>-wiki/vault/` only. Don't run the guard yet.

### 4 — Re-measure
```bash
Q_AFTER=$($BASH lib/autoresearch-guard.sh <wiki> --format=json)
```

### 5 — Gate: keep or discard
**Keep iff ALL hold** (comparing `Q_AFTER` to `Q_BEFORE`):
- `hard_errors == 0` (frontmatter valid, every link resolves), **and**
- ≥1 quality dimension **improved**, **and**
- no quality dimension **regressed**.

| Dimension | improved | regressed |
|---|---|---|
| coverage | `pages` ↑ or `orphan_ratio` ↓ | `orphan_ratio` ↑ |
| links_resolve | `resolve_ratio` ↑ | `resolve_ratio` ↓ (broken>0 is already a hard error → discard) |
| breadcrumb_density | `density` ↑ | `density` ↓ |

Consequences to internalize:
- A new page with no incoming link raises `orphan_ratio` → regression →
  **discard until you link it**. Orphans are no longer free progress.
- Adding a breadcrumb to an existing page raises `density` with nothing
  else moving → valid keep (pure audit-fix).

### 6a — Keep
```bash
git add -A && git commit -m "autoresearch(<wiki>): <one-line action>"
```

### 6b — Discard
```bash
git checkout -- <wiki>-wiki/vault
git clean -fd <wiki>-wiki/vault   # remove new untracked pages, else they inflate the next baseline
```

### 7 — Meta (kept only)
Update `<vault>/index.md` and `log.md` (conventional, not guard-enforced).

### 8 — Loop or stop (see Stop Conditions).

## Progress & audit

No TSV, no score file. **Git history is the audit log** — one commit per
kept iteration. To see where a wiki stands at any time:
```bash
$BASH lib/autoresearch-guard.sh <wiki> --format=json | jq .quality
```
Within a run, hold `Q_BEFORE`/`Q_AFTER` in shell variables for the gate.

## Stop Conditions

1. **User halts** — finish the current iteration cleanly; no dirty tree.
2. **Iteration budget N reached.**
3. **Quality ceiling** — `orphan_ratio == 0` AND `resolve_ratio == 1`
   AND `breadcrumb_density` at/above the theme's target. Nothing left to
   improve under this theme.
4. **N consecutive discards** (e.g. 5) — the agent can't find an
   improving action; the theme is exhausted. Ask the user for a new one.
5. **Git op fails** — halt, do not retry.

## The Guard (the discriminator)

`lib/autoresearch-guard.sh <wiki> [--strict] [--quality] [--format=json|tsv]`
validates structure and emits the quality metric in a single file-walk.

- **HARD** (exit 1): missing/invalid frontmatter; any `[[target]]` that
  doesn't resolve to a page in the **same** vault.
- **SOFT** (warn, exit 0): orphans, taxonomy violations, missing soft
  fields; under `--quality` also vague sources, missing breadcrumbs,
  manifest-unanchored. `--strict` promotes orphans + taxonomy (and the
  quality warns) to hard.
- **quality** block: always emitted in `--format=json`.
- Exit: 0 pass, 1 hard errors, 64–67 config.

Structural integrity is the guard's job; content quality is yours.

## Multi-Wiki

`.config/wikis.json` defines `rhoton`, `ncx`, `nsatlas` — each an
**independent** vault. Every script takes a `<wiki>` arg;
`source lib/resolve-wiki.sh <wiki>` exports `WIKI_VAULT` etc. Commits:
`autoresearch(<wiki>): …`. Branch: `autoresearch/<wiki>-campaign-N`.

## When Not to Use This Skill

- **First-time setup** → `wiki-setup`.
- **Bulk import** → `wiki-ingest`.
- **Quick audit** → `wiki-lint`, or just run the guard.
- **One cross-linking pass** → `cross-linker` directly.

## See Also

- `.skills/cross-linker/SKILL.md` — intra-wiki wikilink discovery.
- `.skills/tag-taxonomy/SKILL.md` — controlled tag vocabulary.
- `.skills/wiki-lint/SKILL.md` — structural audit.
- `.skills/wiki-status/SKILL.md` — current state + delta insights.
