---
title: C2 Revise Queue
wiki: nsatlas
created: 2026-04-18
updated: 2026-04-18
source_audit: audits/c2-iter100-119.md
---

# C2 Revise Queue

Pages flagged by formal audit as `padding` or `mixed` with recoverable issues.
On the next pass that touches any of these pages, the augmentation MUST address
the listed defect — not add more prose. Fix-forward only; do not revert.

Atomic-commit + append-only TSV invariants forbid rewriting history.
These pages carry the debt until resolved.

## Padding (priority 1 — re-augment first)

- [ ] **surgeons-philosophy-and-operating-position** (iter 105, commit 8c0b324)
  - Defect: duplicated summary into body; vague sources; zero breadcrumbs.
  - Required fix: replace duplicative sections with specific ergonomic landmarks
    (distance eye-to-microscope, table-height rule, armrest geometry) from
    `cranial-approaches/general-principles.pdf`. Add `parent: principles-of-cranial-surgery`.
    Cite specific chapter/page.

- [ ] **3d-anatomy** (iter 107, commit 5ab8efc)
  - Defect: summary duplication; generic source.
  - Required fix: add concrete 3D-model landmark list for one approach
    (e.g. pterional) — bone removal boundaries, dural tacking points, vascular
    landmarks. Add `approach-to` breadcrumbs. Cite specific chapter.

- [ ] **principles-of-intraventricular-surgery** (iter 109, commit b13ce21)
  - Defect: manifest-orphan; zero breadcrumbs; tangential wikilinks.
  - Required fix: anchor to a specific PDF (e.g. intraventricular meningioma
    from `brain-tumors/`). Add `parent: principles-of-cranial-surgery` and
    `child` links to specific procedures. Prune 5 tangential wikilinks.

- [ ] **cranial-base-operative-corridor-selection** (iter 116, commit 1df6df8)
  - Defect: 23 wikilinks but zero breadcrumbs or new technical content.
  - Required fix: add corridor-selection decision tree (anterior/middle/posterior
    fossa targets → approach choice) with ≥2 typed `approach-to` breadcrumbs.
    Cite specific source chapter.

## Mixed (priority 2 — address when page is next on the iter target list)

- [ ] **dural-opening-and-closure** (iter 103) — only 1 breadcrumb; add dural-anatomy
  parent + technique children.
- [ ] **operating-room-setup-and-workflow** (iter 106) — zero breadcrumbs.
- [ ] **instrumentation** (iter 108) — zero breadcrumbs.
- [ ] **subarachnoid-dissection** (iter 110) — only 1 breadcrumb.
- [ ] **bifrontal-craniotomy** (iter 112) — only 1 breadcrumb; add `approach-to` targets.
- [ ] **trigeminal-neuralgia-mvd** (iter 114) — zero breadcrumbs.
- [ ] **imaging-sah-and-aneurysm** (iter 115) — zero breadcrumbs.
- [ ] **cranial-base-surgery-general-principles** (iter 118) — zero breadcrumbs.
- [ ] **cranial-base-preoperative-considerations** (iter 119) — zero breadcrumbs.

## Manifest orphans (priority 1b — anchor to source PDF)

- [ ] **operative-spinal-cord-anatomy** — add manifest entry pointing to
  `spinal-cord-surgery/*.pdf` used as source for iter 100.
- [ ] **extramedullary-spinal-cord-tumor-resection** — idem, iter 101 source.
- [ ] **intramedullary-spinal-cord-tumor-resection** — idem, iter 102 source.

## Resolution rule

When a flagged page is selected for a future iter:
1. Locate its entry here.
2. Implement the listed fix (not additional padding).
3. Mark `- [x]` and reference the new commit hash.
4. Keep the entry in the file (historical record).
