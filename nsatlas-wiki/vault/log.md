---
title: NSAtlas Wiki Log
category: meta
tags:
  - meta
  - nsatlas
created: 2026-04-13
updated: 2026-04-18
summary: >-
  Chronological log of wiki operations.
---

# Operation Log

## 2026-04-13

- **Scaffold created:** vault structure, autoresearch scripts, manifest, taxonomy, index
- **Source material:** 107 PDFs, ~1400 pages, ~95 unique articles
- **Baseline score:** 0
- **Iteration 1:** `cranial-approaches/general-principles.pdf` → `approaches/cranial-approaches-general-principles.md` | 11 figures, 6 operative principles, approach comparison table | Score: 32→92 (+60)

## 2026-04-15

- **Bypass procedures from Lawton (2018):** 4 pages created in `procedures/`
  - `ec-ic-bypass.md` -- STA-MCA, STA-ACA, OA-PICA, STA-PCA/SCA; flash fluorescence technique
  - `interposition-graft-bypass.md` -- RAG/SVG grafts, cervical donors, tunneling technique
  - `reimplantation-bypass.md` -- IC-IC reimplantation in 4 anatomic triangles (Sylvian, falco-frontal, tentorial-oculomotor, vago-accessory)
  - `in-situ-bypass.md` -- side-to-side bypass at 4 parallelism sites (MCA, ACA, PCA/SCA, PICA)
- **Source:** Lawton - Seven Bypasses: Tenets and Techniques for Revascularization (2018)
- **Dense cross-linking:** 15+ wikilinks per page, inter-page references between all 4 bypass types

## 2026-04-18 — Extractions disposition audit (C2 closeout)

Audit of `extractions/datalab/chapters/` — 100 chapters extracted via Datalab, cross-referenced against current vault state. All chapters categorized below.

### Vaultized (83 chapters) — COMPLETE

| Extraction category | Count | Vault location |
|---|---|---|
| `cranial-approaches--*` | 17 | `approaches/` (+1 via `cranial-base-surgery--anterior-petrosectomy`) |
| `principles-of-cranial-surgery--*` | 20 | `principles/` |
| `operative-neuroanatomy--*` | 6 | `concepts/` |
| `cranial-base-surgery--*` | 6 | `approaches/` (anterior-petrosectomy), `references/` (4), `pathology/` (1) |
| `csf-diversion-procedures--*` | 7 | `procedures/` |
| `spinal-cord-surgery--*` | 6 | `procedures/` |
| `neuroradiology--*` | 5 | `references/` (3), `pathology/` (2) |
| `cranial-nerve-compression-syndromes--*` | 5 | `pathology/` |
| `epilepsy-surgery--*` | 4 | `procedures/` |
| `emergency-neurosurgery-and-trauma--*` | 3 | `procedures/` |
| `brain-tumors--*` | 2 | `references/` |
| `cerebrovascular-surgery--*` | 1 | `references/cerebrovascular-microscope-technique.md` |
| `microsurgical-mastery--*` | 1 | `procedures/microsurgical-mastery.md` |

### Pending / deferred (11) — held for Campaign 3 (C3)

| Extraction prefix | Count | Destination |
|---|---|---|
| `non-technical-skills-in-neurosurgery--*` | 11 | Pending C3. Candidates for a new `professional/` category if C3 ingests them. Topics: burnout, emotional intelligence, ethics, leadership, OR etiquette, resilience, situation awareness, surgical decision-making, teamwork, what makes a great resident. Valuable soft-skills content; held because scope of nsatlas was primarily technical through C1-C2. |

### Discarded (12) — out of scope or stale

| Extraction prefix | Count | Rationale |
|---|---|---|
| `medical-student-guide-for-matching-in-neurosurgery--*` | 10 | Out of scope — medical-student residency application guidance, not neurosurgical technique. Vaultizing would dilute the technical focus of the atlas. |
| `preface--*` | 1 | Book front-matter; no technical content. |
| `trending-articles-in-neurosurgical-journals--*` | 1 | Time-bound content (October 2023 snapshot); would be stale by design. |

### Rationale for the split

The 83 "vaultized" chapters represent the technical backbone of the atlas (approaches, principles, operative anatomy, disease-specific chapters, procedures). They map 1-to-1 against real pages in the vault — note `approaches/` also contains Lawton bypass pages from a separate source (not counted here). The 11 "pending" non-technical-skills chapters are operational/soft-skills and could form a coherent `professional/` section in C3 — held rather than discarded because the content has enduring value. The 12 discarded chapters are either out of technical scope (matching guide), metadata (preface), or designed to decay (trending articles). Total: 83 + 11 + 12 = 106 extraction directories.

### C3 decision (2026-04-18)

- Extractions directory **retained** on disk for now. A purge decision for the 77 already-vaultized chapters + images belongs to a separate hygiene issue (compare to rhoton's `extractions/datalab/chapters/` purge discussion in #28) — the Datalab API call was expensive, keeping the raw extraction as canonical source is cheap insurance.
- C3 will pick up the 11 non-technical-skills chapters if and when the user wants a `professional/` section.

Closes #33 (nsatlas extractions disposition documented).
