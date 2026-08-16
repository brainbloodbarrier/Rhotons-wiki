# CLAUDE.md

Agent-facing instructions live in **[AGENTS.md](./AGENTS.md)** at the repo root. This file adds project-specific overrides for Claude Code autonomous mode.

## Modo Autônomo — Overrides deste projeto

Este projeto roda autoresearch loops longos. Regras específicas:

- **Sem confirmação por iteração.** O loop roda até completar ou falhar 3x.
- **Commits automáticos permitidos** em branches não-main durante autoresearch.
- **Guard roda sem prompt:** `lib/autoresearch-guard.sh` (via `/opt/homebrew/bin/bash`).
- **Bypass total de permissions** — configurado em `.claude/settings.local.json`.

### Reporting neste projeto

Além dos triggers globais (ver `~/CLAUDE.md`), reportar também quando:

- Guard retornou exit 1 (hard error estrutural — link quebrado / frontmatter)
- Nenhuma dimensão de qualidade avançou em N iterações seguidas (tema exausto)
- Manifest `.manifest.json` não pôde ser atualizado (conflito de estado)

## Contexto operacional

- **Multi-wiki:** `rhoton`, `ncx`, `nsatlas` — **wikis independentes, sem links cross-wiki**. Toda campanha declara o wiki alvo. Registry em `.config/wikis.json`.
- **Branch naming:** `autoresearch/<wiki>-campaign-N` (ver git log).
- **Métrica de qualidade:** `lib/autoresearch-guard.sh <wiki> --format=json | jq .quality` → `coverage` / `links_resolve` / `breadcrumb_density`. Sem score escalar, sem TSV — git history é o log.

### Definição de "falha" (trigger dos 3x)

- Guard exit 1 (hard error), OU
- Nenhuma dimensão de qualidade melhorou (ou alguma regrediu), OU
- `.manifest.json` não atualizável.
