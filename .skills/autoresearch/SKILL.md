---
name: autoresearch
description: >
  Local terminal loop that iteratively grows an Obsidian wiki via the
  agent's own reasoning, with quality guards between each step. Runs
  entirely inside Claude Code or OpenCode — no network dependencies in
  the loop itself. Use this skill whenever the user says "run
  autoresearch", "start a campaign", "grow the wiki", "iterate on the
  wiki", "continue the campaign", or drops a slash command like
  `/autoresearch`. Supports any wiki in `.config/wikis.json` (multi-wiki
  aware). If `.config/wikis.json` is not present, falls back to the
  legacy single-vault mode driven by `OBSIDIAN_VAULT_PATH` in `.env`.
applies_to:
  - claude-code
  - opencode
  - codex
version: 1.0.0
---

# Autoresearch — The Local Wiki-Growth Loop

**This is the core feature of the project.** Everything else in
`.skills/` is a building block that this loop composes. When you run
autoresearch, you are the agent executing the loop yourself inside the
terminal. There is no separate runtime. No remote API. No cron. Just
you, a vault, and a git repo.

## Purpose

Autoresearch grows a wiki **from the inside out**. Starting from a
baseline score, each iteration: picks a focused action, executes it,
verifies the result improved the wiki (score goes up), validates the
vault's structural integrity (guard passes), and then either commits
the improvement to git or discards it. A TSV logs every iteration —
kept or discarded — for campaign reproducibility and audit.

Run thousands of iterations by hand over weeks and the wiki compounds.
That's the point.

## Autonomy Defaults

**Por padrão, o loop roda indefinidamente.** Não pergunte "devo continuar?" entre iterações. Não pause para confirmação. Apenas execute o próximo ciclo. O usuário interrompe via Ctrl-C ou enviando uma nova mensagem.

**Inline config** (parse do início da mensagem do usuário):
- `Iterations: N` — roda exatamente N iterações e para com resumo final.
- `Wiki: <nome>` — sobrescreve o wiki alvo.

Se `Iterations` não for especificado → unbounded. Se `Wiki` não for especificado → inferir do nome do branch atual (`autoresearch/<wiki>-campaign-N`), ou pedir ao usuário se ambíguo.

## Non-Negotiable Invariants

1. **Local only.** The loop never makes outbound HTTP requests. Every
   tool invoked is local (bash, filesystem, git). If you find yourself
   wanting to call an external API, stop and ask the user to do it
   out-of-band, then resume the loop with the extracted content.
2. **One action per iteration.** Do not bundle "create 3 pages + fix
   tags + add wikilinks" into a single iteration. That defeats the
   guard/score feedback loop. Pick one action; execute it; verify.
3. **Atomic commits.** If an iteration is kept, it is a single git
   commit. If discarded, no commit exists — `git checkout` restores
   the working tree.
4. **TSV is append-only and ordered.** Every iteration — kept or
   discarded — writes exactly one row. Never rewrite historical rows.
5. **Guard failures halt the loop by default.** A guard failure
   means the vault is in an inconsistent state. Fix it before
   iterating further.

## Preconditions

Before starting a campaign:

1. Working tree is clean (`git status --porcelain` empty, or only
   `.autoresearch/` output).
2. The target wiki's vault directory exists.
3. The baseline score can be computed (verify script runs).
4. The guard passes on the current HEAD.
5. The user has chosen a **campaign theme**: a focused goal for the
   next N iterations (examples: "cross-link synthesis pages",
   "expand incisural-space coverage", "normalize taxonomy tags").
   Without a theme, iterations drift and the TSV becomes noise.

## The Loop

Execute this protocol for every iteration. Each step maps to a concrete
command or tool call. Do not skip steps; do not reorder them.

### Step 1 — Read baseline

Record the current score, the current HEAD commit, and the current TSV
row count. These are your "before" values.

```bash
# Resolve wiki paths (Phase 2+ — uses lib/resolve-wiki.sh)
source lib/resolve-wiki.sh <wiki-name>

# Or legacy single-vault (pre-Phase 2)
VAULT="${OBSIDIAN_VAULT_PATH:-rhoton-wiki/vault}"

SCORE_BEFORE=$(lib/autoresearch-verify.sh <wiki-name>)   # Phase 3+
# Or:  SCORE_BEFORE=$(./autoresearch-verify.sh)          # pre-Phase 3
HEAD_BEFORE=$(git rev-parse --short HEAD)
```

**Git-as-memory (obrigatório a cada iteração):**
```bash
git log --oneline -5   # quais targets já foram commitados nesta campanha
```
Use esse histórico para escolher o próximo target sem repetir páginas já criadas e para explorar adjacências naturais (ex: se iter anterior foi `wernicke-area`, candidatos são `broca-area`, `arcuate-fasciculus`, `frontal-lobe`).

### Step 2 — Baseline guard

Run the guard on the current HEAD. If it fails, you cannot begin an
iteration — the vault is already broken. Halt and report which checks
failed so the user can fix them out-of-band.

```bash
lib/autoresearch-guard.sh <wiki-name> || {
  echo "Baseline guard failed. Halting."
  exit 1
}
```

### Step 3 — Select one action

From the campaign theme, pick exactly one of the following:

- **Create a page.** A new concept, entity, synthesis, or reference
  page. Must have full frontmatter (title, category, tags, sources,
  created, updated) and ≥ 1 wikilink to an existing page. Prefer
  creating pages that already have incoming links from synthesis
  or index pages but are currently redlinks.
- **Augment a page.** Add content to an existing page: new sections,
  new wikilinks, new figures, clarified frontmatter. Do not rewrite
  the page wholesale — additive only.
- **Cross-link.** Add wikilinks between existing pages. Use the
  `cross-linker` skill for systematic sweeps.
- **Normalize taxonomy.** Fix tags against `_meta/taxonomy.md`. Use
  the `tag-taxonomy` skill.
- **Audit fix.** Address a broken link, orphan page, or other issue
  reported by the `wiki-lint` skill.

Mixing types within a single iteration is a loop-protocol violation.

### Step 4 — Execute the action

Edit / create files. Do not run the verify or guard scripts yet. Your
only output of this step is a dirty working tree.

### Step 5 — Verify (post-action score)

Re-run the verify script. This is your "after" value.

```bash
SCORE_AFTER=$(lib/autoresearch-verify.sh <wiki-name>)
DELTA=$((SCORE_AFTER - SCORE_BEFORE))
```

### Step 6 — Guard (post-action)

Run the guard. Capture exit code.

```bash
lib/autoresearch-guard.sh <wiki-name>
GUARD_EXIT=$?
```

### Step 7 — Decide: keep or discard

| Guard | Score | Decision |
|---|---|---|
| pass (exit 0) | strictly greater | **keep** |
| pass | equal or lower | discard (unless action was a pure audit-fix with zero score impact by design — annotate in TSV) |
| fail (exit > 0) | — | discard regardless of score |

### Step 8a — Keep path

```bash
git add -A
git commit -m "autoresearch(<wiki>): <short description of action>"
HEAD_AFTER=$(git rev-parse --short HEAD)
ITERATION=$((CURRENT_TSV_ROW_COUNT + 1))
# Append TSV row (see schema below)
```

### Step 8b — Discard path

```bash
git checkout -- <vault-path>
# Any files created outside git tracking (unlikely in a clean workflow):
git clean -fd <vault-path>
HEAD_AFTER="$HEAD_BEFORE"
ITERATION=$((CURRENT_TSV_ROW_COUNT + 1))
# Append TSV row marking this iteration as discarded
```

### Step 9 — Update vault meta

If the action was kept:

- Update `<vault>/index.md` to include the new/augmented page(s).
- Update `<vault>/log.md` with a one-line entry describing what
  happened in this iteration.

These two files are conventional, not enforced by the guard. Missing
them makes the vault harder to read but does not break anything.

### Step 10 — Loop ou parar

**DEFAULT: Loop imediato.** Vá direto ao Step 1 do próximo ciclo. NÃO emita "devo continuar?". NÃO pause. NÃO espere confirmação do usuário entre iterações normais.

Após commitar (ou descartar), emita UMA linha de progresso e inicie o próximo ciclo imediatamente:
```
[iter N] score=XXXX Δ=+YY guard=pass status=keep → próximo: <target-name>
```

**Parar** apenas quando uma das stop conditions abaixo disparar.

## Score Function (formal spec)

```
score = 10·pages + 2·wikilinks + (words / 100)
```

Where:

- **pages** = count of `*.md` files inside `<vault>`, excluding
  `.obsidian/`, `.smart-env/`, `index.md`, and `log.md`.
- **wikilinks** = count of `[[...]]` occurrences (including aliased
  `[[target|label]]` forms) across the same set of files.
- **words** = total `wc -w` across the same set of files, integer
  divided by 100.

### Rationale per term

- **10·pages** rewards content breadth. Creating a new page is worth
  at least +10 even before it has any content.
- **2·wikilinks** rewards connectivity. A new page with 5 wikilinks
  outward and 1 link from an existing page = +10 + 12 = +22.
- **words / 100** rewards depth without overwhelming the other terms.
  A substantial new section (500 words) adds +5.

### Known weaknesses

- **Redlinks count.** `[[does-not-exist]]` is counted as a wikilink
  even if the target page doesn't exist. The `wiki-lint` skill
  catches redlinks; a future guard should fail on them.
- **Orphan pages count.** A new page counts +10 regardless of whether
  anything links to it. Phase 6 of the refactor plan adds an orphan
  check to the guard.
- **No content-quality signal.** Words are counted, not their
  usefulness. Accept this: the agent's judgment carries that load.

### Future work

- Weighted wikilinks (links inside synthesis pages worth more than
  links inside index pages).
- Typed-relation bonuses (parent/child/branch-of relations worth
  extra vs plain `[[...]]`).
- Anti-gaming: penalty for empty pages, duplicate content, or
  drive-by wikilinks with no surrounding context.

## Guard Validations

The guard script runs a series of checks. Each check independently
contributes to the error count; the overall exit code is 1 if ANY
check fails, 0 if all pass.

Current (Phase 3) checks:

1. **Frontmatter presence.** Every non-meta `.md` file starts with a
   `---` frontmatter block.
2. **Required frontmatter keys.** `title`, `category`, `tags` must be
   present.

Planned (Phase 6) checks:

3. **Wikilink integrity.** Every `[[target]]` and `[[target|label]]`
   resolves to an existing `.md` file in the vault.
4. **Orphan detection.** Every page (except `index.md`, `log.md`,
   `_meta/*.md`) has at least one incoming wikilink.
5. **Taxonomy compliance.** Every `tags:` value exists in
   `<vault>/_meta/taxonomy.md` if that file exists.
6. **No-regression.** With `--baseline <score>` flag, guard exits 1 if
   current score is less than the baseline.

The guard is intentionally structural. Content quality is the agent's
job; structural integrity is the guard's job.

## Result TSV Schema

Path: `.autoresearch/<wiki-name>/results.tsv`

### Columns

```
iteration  commit  metric  delta  guard  guard-metric  status  description
```

| Column | Type | Meaning |
|---|---|---|
| `iteration` | integer | 0 for the initial baseline, 1+ for each subsequent iteration |
| `commit` | string | 7-char git SHA of the kept commit, or `-` if discarded |
| `metric` | integer | Score after the iteration (for discarded, same as before) |
| `delta` | signed integer | `metric` minus the previous row's `metric` |
| `guard` | `pass` / `fail` | Guard exit status after the iteration |
| `guard-metric` | integer or `-` | Number of guard errors (0 if pass); `-` means not measured |
| `status` | `baseline` / `keep` / `discard` | Iteration outcome |
| `description` | free text | One-line human-readable description of the action |

### Delimiter

Tab character (`\t`). No quoting. Descriptions must not contain literal
tab characters — replace with spaces if needed.

### Header

The first line MAY be a comment starting with `#` (e.g.
`# metric_direction: higher_is_better`). The second line is the
column header. The third line onward is iteration data.

### Append semantics

Every new iteration appends exactly one row to the end of the file.
Historical rows are never rewritten. If you need to fix a metadata
error in a past row, add a new row documenting the correction rather
than editing in place.

## Campaign Concept

A **campaign** is N iterations pursuing a single theme. The campaign's
name goes in the `description` column so you can grep/filter the TSV
for a specific campaign's iterations.

Good themes are narrow and measurable:

- `cross-link-synthesis-pages`: run cross-linker repeatedly, one
  synthesis page at a time, until all synthesis pages have ≥ 5
  outgoing wikilinks.
- `expand-cn-coverage`: create pages for any cranial nerve
  currently missing from the vault.
- `normalize-tags-to-taxonomy`: one iteration per non-canonical tag
  until `wiki-lint` reports zero taxonomy violations.

Bad themes are vague: "improve the wiki", "add more content",
"make it better".

## Multi-Wiki Awareness

When `.config/wikis.json` exists:

1. Accept a `<wiki-name>` argument for every script invocation.
2. Resolve paths via `source lib/resolve-wiki.sh <wiki-name>` to
   export `WIKI_VAULT`, `WIKI_EXTRACTIONS`, `WIKI_OUTPUT`, etc.
3. Write TSV to `${WIKI_OUTPUT}/results.tsv` (i.e.
   `.autoresearch/<wiki-name>/results.tsv`).
4. Commits use conventional message: `autoresearch(<wiki-name>): ...`.

When `.config/wikis.json` does NOT exist (pre-Phase-2 or fallback):

1. Use `OBSIDIAN_VAULT_PATH` from `.env` for the vault.
2. Write TSV to the legacy root-level `autoresearch-results.tsv`.
3. Commits use `autoresearch: ...`.

Prefer the multi-wiki path whenever the registry is present. It scales
to additional wikis without code changes.

## Stop Conditions

Exit the loop when any of these become true:

1. **User halts.** The user interrupts (Ctrl-C, `/cancel`, or a
   new prompt). Finish the current iteration cleanly (commit or
   discard); do not leave a dirty working tree.
2. **Iteration budget reached.** The user specified `N` iterations;
   `N` iterations have completed.
3. **Score plateau.** Cinco iterações consecutivas com `delta <= 0`. Ao detectar plateau: emitir resumo (score atual, total de iters, delta médio) e perguntar ao usuário se quer mudar de tema ou parar. NÃO parar silenciosamente. Em bounded mode, reportar plateau no resumo final sem cancelar antecipadamente.
4. **Catastrophic guard failure.** Guard returns > 10 errors in a
   single iteration. Something structural broke; halt and ask the
   user to investigate.
5. **Git operation fails.** `git commit` or `git checkout` returns
   non-zero. Halt; do not retry.

## Rollback Guarantees

- **Per-iteration rollback.** `git revert <commit-sha>` undoes a
  single kept iteration. The TSV row for that iteration remains as
  historical record; add a new row noting the revert.
- **Per-campaign rollback.** `git reset --hard <baseline-sha>`
  discards an entire campaign. Only use this if the user explicitly
  asks — it rewrites history.
- **Discard safety.** A discarded iteration never enters git history.
  The working tree is restored via `git checkout --`. The TSV row is
  the only trace.

## When Not to Use This Skill

- **First-time setup.** Use `wiki-setup` to initialize a vault from
  empty. Run autoresearch only after baseline content exists.
- **Bulk import.** Use `wiki-ingest` to load many sources at once.
  Autoresearch is for incremental growth, not batch ingest.
- **Quick audit.** Use `wiki-lint` for a one-shot integrity check
  without the iterative overhead.
- **Cross-linking alone.** Use `cross-linker` directly if you just
  want to run one pass. Autoresearch wraps it with tracking.

## Local-Only Invariant (restated)

The loop must not make network calls. Concretely:

- No `curl`, `wget`, or any HTTP client in the iteration path.
- No MCP tools that reach external services (Context7, WebFetch,
  WebSearch) during an iteration. The agent's own reasoning plus the
  pre-extracted source material in `<wiki>/extractions/` is enough.
- Pre-extraction (e.g., Datalab PDF conversion) happens out-of-band
  by the user, before autoresearch starts. The loop consumes what's
  already in the extractions directory.

This invariant is why autoresearch is a terminal loop: it's the entire
thing. No services, no servers, no cloud. Just a vault and a loop.

## See Also

- `.skills/wiki-ingest/SKILL.md` — bulk ingestion of source documents.
- `.skills/cross-linker/SKILL.md` — insert missing wikilinks between
  related pages.
- `.skills/tag-taxonomy/SKILL.md` — enforce controlled tag vocabulary.
- `.skills/wiki-lint/SKILL.md` — structural audit.
- `.skills/wiki-status/SKILL.md` — current state + delta insights.
- `.sisyphus/plans/enterprise-refactor.md` — the plan that formalized
  this skill; refer to §Phase 1 for the skill's full rationale.
