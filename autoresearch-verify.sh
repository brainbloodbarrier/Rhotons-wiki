#!/bin/bash
VAULT="rhoton-wiki/vault"
PAGES=$(find "$VAULT" -name "*.md" -not -path "*/.obsidian/*" -not -name "index.md" -not -name "log.md" | wc -l | tr -d ' ')
LINKS=$(grep -r '\[\[' "$VAULT" --include="*.md" 2>/dev/null | wc -l | tr -d ' ')
WORDS=$(find "$VAULT" -name "*.md" -not -path "*/.obsidian/*" -exec cat {} + 2>/dev/null | wc -w | tr -d ' ')
SCORE=$(( (PAGES * 10) + (LINKS * 2) + (WORDS / 100) ))
echo "$SCORE"
