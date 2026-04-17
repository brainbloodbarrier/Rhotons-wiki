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
