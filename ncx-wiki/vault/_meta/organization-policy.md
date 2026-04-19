---
title: Organization Policy
category: _meta
tags:
  - meta
  - ncx
created: 2026-04-18
updated: 2026-04-18
summary: >-
  Taxonomic rules for NCX vault growth. Defines when to create folders,
  when to split, when to merge, and how to resolve borderline pages.
---

# Organization Policy — NCX Wiki

This policy governs folder organization as the NCX vault grows from its current 59 pages toward the planned 78-textbook corpus. It exists to prevent two opposite failure modes: (a) 1-page folders that fragment navigation, and (b) monolithic folders that hide subclusters.

## 1. Decision flow for a new page

1. Is there an existing folder with ≥5 pages in the same thematic cluster? → that folder
2. Is the topic transversal across multiple subspecialties? → `synthesis/`
3. Is it an operative tool (approach, bypass, technique)? → `procedures/`
4. Is it an anatomical concept with no primary pathology? → `concepts/`
5. Is it a clinical pathology? → `pathology/` (until split threshold)
6. Is it a classification/scale/score? → `classifications/`

## 2. Threshold for creating a new folder

**Do not create a new folder until 5 pages in the same cluster are confirmed.** Below 5, place pages in the closest existing folder and use **tags** for thematic grouping. This rule applies even to new subspecialties (spine, functional, pediatric).

Rationale: the rhoton-wiki (155 pages) uses only 3 content folders (`concepts/`, `entities/`, `references/`). The nsatlas-wiki (83 pages) uses 6. NCX is more heterogeneous but follows the same principle — 1-to-2 page folders create friction without benefit.

## 3. Threshold for splitting an existing folder

**Split when a folder reaches 15 pages AND a coherent subset of 8+ pages** would benefit from independent grouping.

Apply to `pathology/` (24 pages today):

| Cluster within pathology/ | Current count | 8+ threshold |
|---|---|---|
| cerebrovascular (aneurysms + AVMs + cavernoma) | 16 | **reached** |
| neuro-oncology (meningioma, GBM, VS, PitNET) | 4 | pending |
| CSF/developmental (hydrocephalus, NPH, Chiari) | 3 | pending |
| functional/CN (trigeminal neuralgia, herniation) | 2 | pending |

Only the cerebrovascular cluster has reached 8. The others would be shallow if split now.

**Decision:** defer split. Trigger the `pathology/` → `pathology/ + cerebrovascular/` split when the neuro-oncology cluster reaches 8 pages — this way both resulting folders meet the ≥8 threshold simultaneously.

## 4. Borderline pages ("meningioma is also skull-base")

**Folder = primary clinical framing. Secondary context = tag + wikilink.**

Meningioma lives in `pathology/` (primary: tumoral pathology). Its skull-base context is captured via:
- `skull-base-surgery` tag in frontmatter
- `[[cerebellopontine-angle]]` or similar wikilinks when relevant

Never duplicate a page. Never create file aliases for organizational reasons.

## 5. Tag vs folder — when each suffices

| Situation | Tag | Folder |
|---|---|---|
| Cross-cutting theme appearing in multiple folders | yes | no |
| Clinical theme with <5 own pages | yes | no |
| Clinical theme with 5-14 own pages | yes + folder candidate | evaluate |
| Clinical theme with 15+ own pages (split cluster ≥8) | both | create folder |

## 6. Watch-list folders (1 page today)

Folders with 1 page stay on watch-list: `entities/`, `coluna/`, `skull-base/`, `pharmacology/`, `neurocirurgia-funcional/`. **Do not merge now** — each has a distinct identity and the vault will grow toward 78 sources. Merging would force a re-split later. Revisit if still at 1 page after Campaign 2.

## 7. Manifest and wikilinks

`wiki_page` in `.manifest.json` uses path relative to the vault root (e.g., `pathology/acoa-aneurysm.md`). When moving a page:
1. Move the file.
2. Update `wiki_page` in the manifest.
3. Update `index.md` category counts.

Obsidian resolves wikilinks by basename, not path — `[[acoa-aneurysm]]` survives folder moves. Only the manifest and index need updates.

## 8. Current application (2026-04-18)

| Folder | Pages | Decision | Reason |
|---|---|---|---|
| `pathology/` | 24 | **Keep unified** (split deferred) | Cerebrovascular cluster ready; others too shallow |
| `concepts/` | 13 | Keep | Healthy size |
| `procedures/` | 8 | Keep | Intentional mix (approaches + bypasses) |
| `synthesis/` | 4 | Keep | Does not fragment by definition |
| `classifications/` | 3 | Keep | Watch-list |
| `critical-care/` | 2 | Keep | Watch-list (Wijdicks will feed) |
| `entities/`, `coluna/`, `skull-base/`, `pharmacology/`, `neurocirurgia-funcional/` | 1 each | **Watch-list** | Distinct identity; do not merge |

**Conclusion:** no physical reorganization now. Trigger to revisit: `pathology/` reaches 30 pages OR `neuro-oncology` cluster reaches 8 — whichever first.

## 9. Future migration plan (when trigger fires)

Split `pathology/` → `pathology/ + cerebrovascular/`:

1. **Commit 1** — create `cerebrovascular/` folder and move ~16 files (7 aneurysms + 7 AVMs + 1 cavernoma; optionally trigeminal neuralgia if a functional cluster also reached 8).
2. **Commit 2** — update `.manifest.json`: rename `wiki_page: pathology/X.md` → `cerebrovascular/X.md` for each moved file.
3. **Commit 3** — update `index.md`: add a row for the new `cerebrovascular` folder, correct the `pathology` count.
4. **Verification:** `lib/autoresearch-guard.sh ncx` exits 0; score preserved (basename-based wikilinks survive); `grep -r "pathology/acoa" ncx-wiki/vault/` empty (no path-qualified links).

## 10. Enforcement

- **Agents**: read this file before creating any folder or moving pages in the NCX vault.
- **Human reviewer**: cite this document when rejecting a PR that violates thresholds.
- **Amendments**: propose a PR touching this file; commit message `policy(ncx): …`.
