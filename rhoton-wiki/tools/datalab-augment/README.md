# datalab-augment

Pipeline that augments the curated Rhoton Wiki vault at `rhoton-wiki/vault/` with layout-preserving content extracted via the Datalab Convert API at `rhoton-wiki/extractions/datalab/`.

## Phases

| Phase | Script | Reads | Writes | Cost |
|---|---|---|---|---|
| A — map | `map_chapters.py` + `attribute_figures.py` | vault/, extractions/datalab/ | extractions/datalab-augment/plan/*.json | free |
| B — figures | `stage_figures.py` | plan/figures-attribution.json | vault/_attachments/figures/ + figures-manifest.json | free |
| C — dry-run | `llm_merge.py --dry-run` | plan/, vault/ | extractions/datalab-augment/dry-run/ | Claude API |
| D — review | (manual) | dry-run/report.md | append `MERGE APPROVED` line | free |
| E — apply | `llm_merge.py apply` | dry-run/ (approved) | vault/*.md + per-chapter commits | free |
| F — validate | `validate.py` | vault/ | extractions/datalab-augment/final-report.md | free |

## Usage (once all phases land)

    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    .venv/bin/python augment.py map       # Phase A — free
    .venv/bin/python augment.py figures   # Phase B — free
    AUGMENT_BUDGET_USD=100 .venv/bin/python augment.py dry-run  # Phase C
    # (manual review + append MERGE APPROVED)
    .venv/bin/python augment.py apply     # Phase E
    .venv/bin/python augment.py validate  # Phase F

## Safety rails

- Feature branch `wiki/datalab-augment` for all writes
- Per-chapter atomic commits
- Wikilink set-inclusion check (old ⊆ new) before every write
- Paragraph preservation check (5 random 50-char substrings)
- Hard budget cap via AUGMENT_BUDGET_USD env
- Pre-submit projection, halt on overrun
- Rollback: `git checkout main`

See `/Users/fax/obsidian-wiki/~/.claude/plans/humble-squishing-mitten.md` for the full plan.
