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

## Usage

    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    .venv/bin/python map_chapters.py        # Phase A — chapter mapping (free)
    .venv/bin/python attribute_figures.py   # Phase A — figure attribution (free)
    .venv/bin/python stage_figures.py       # Phase B — figure staging (free)

Phases C–F (`llm_merge.py`, `validate.py`) are not yet implemented.

## Safety rails

- Feature branch `wiki/datalab-augment` for all writes
- Per-chapter atomic commits
- Wikilink set-inclusion check (old ⊆ new) before every write
- Paragraph preservation check (5 random 50-char substrings)
- Hard budget cap via AUGMENT_BUDGET_USD env
- Pre-submit projection, halt on overrun
- Rollback: `git checkout main`
