---
title: Enterprise-Grade Refactor Plan — pkm-obsidian-wiki
author: Sisyphus
created: 2026-04-17
status: shipped
scope: full repository reorganization + autoresearch formalization
reviewers: [momus, user]
---

# Enterprise-Grade Refactor Plan — SHIPPED

> **This plan is complete.** All phases (0–7) shipped. The full 944-line
> phase-by-phase specification has been truncated to this pointer per the
> housekeeping audit — the target architecture it described is now the live
> repository state. For the detailed history, see the git log:
>
> ```
> git log --oneline -- .sisyphus/plans/enterprise-refactor.md
> git log --follow -- .config/wikis.json lib/ .skills/autoresearch/
> ```

## What it did (executive summary)

Reorganized the skill-based multi-vault Obsidian framework from an organically
grown layout into an enterprise structure **without changing the UX** —
`/autoresearch` still runs as a local, terminal-only loop. Every wiki and skill
was preserved; the missing `autoresearch` skill was added; scripts, docs,
config, and directory layout were hardened.

## Phase ledger (all shipped — verified on disk)

| Phase | Deliverable | Evidence |
|---|---|---|
| 0 — Cleanup & Hygiene | Removed stray top-level scripts, empty dirs, bug artifacts | `autoresearch-{guard,verify}.sh`, `ONBOARDING.md` gone from root |
| 1 — Autoresearch as Skill | Formalized the loop as a real skill | `.skills/autoresearch/SKILL.md` |
| 2 — Multi-Wiki Configuration | Registry-driven wiki resolution | `.config/wikis.json` + `lib/resolve-wiki.sh` |
| 3 — Script Hardening | Parameterized, `lib/`-based scripts | `lib/autoresearch-{guard,verify}.sh` |
| 4 — setup.sh Hardening | Idempotent symlink install + `--verify` | `setup.sh` |
| 5 — Documentation Unification | Merged ~70%-overlap docs | `README.md` + `AGENTS.md` + `SETUP.md` |
| 6 — Enterprise Guard System | Link integrity, orphan, score-regression checks | `lib/autoresearch-guard.sh` |
| 7 — Crossmap Activation | Cross-wiki resolution layer | `crossmap.json` + `lib/crossmap-generate.sh` |

## Non-negotiable invariants (held throughout)

1. `/autoresearch` stayed a local, terminal-only loop — no network deps added.
2. Existing wiki page content remained byte-identical through Phases 0–6.
3. Every phase was independently revertable via `git revert`.
4. No secret material committed; `.env` never left gitignore.
5. The plan was executable phase-by-phase by a human or agent.
