#!/bin/bash
VAULT="rhoton-wiki/vault"
ERRORS=0
for f in $(find "$VAULT" -name "*.md" -not -path "*/.obsidian/*" -not -name "index.md" -not -name "log.md"); do
  HEAD=$(head -1 "$f")
  if [ "$HEAD" != "---" ]; then
    echo "MISSING FRONTMATTER: $f"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$f" | head -20)
  for field in title category tags; do
    echo "$FRONTMATTER" | grep -q "^${field}:" || {
      echo "MISSING $field: $f"
      ERRORS=$((ERRORS + 1))
    }
  done
done
exit $ERRORS
