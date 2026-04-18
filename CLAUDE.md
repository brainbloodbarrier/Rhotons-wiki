# CLAUDE.md

Agent-facing instructions live in **[AGENTS.md](./AGENTS.md)** at the repo root. This file adds project-specific overrides for Claude Code autonomous mode.

## Modo Autônomo — Overrides deste projeto

Este projeto roda autoresearch loops de 100+ iterações. Regras específicas:

- **Sem confirmação por iteração.** O loop roda até completar ou falhar 3x.
- **Commits automáticos permitidos** em branches não-main durante autoresearch.
- **Guard scripts rodam sem prompt:** `lib/autoresearch-guard.sh`, `lib/autoresearch-verify.sh`.
- **Bypass total de permissions** — configurado em `.claude/settings.local.json`.

### Reporting neste projeto

Além dos triggers globais (ver `~/CLAUDE.md`), reportar também quando:

- Score de autoresearch **caiu** entre iterações (regressão)
- Guard script retornou exit 1 (violação de qualidade)
- Manifest `.manifest.json` não pôde ser atualizado (conflito de estado)

## Contexto operacional

- **Multi-wiki:** `rhoton`, `ncx`, `nsatlas`. Toda campanha deve declarar o wiki alvo. Registry em `.config/wikis.json`.
- **Branch naming:** `autoresearch/<wiki>-campaign-N` (ver git log).
- **Results log:** `.autoresearch/<wiki>/results.tsv` — append uma linha por iteração.
- **Score formula:** `pages*10 + wikilinks*2 + words/100` (via `lib/autoresearch-verify.sh <wiki>`).

### Definição de "falha" (trigger dos 3x)

- Guard script exit 1, OU
- Delta de score negativo, OU
- `.manifest.json` não atualizável.
