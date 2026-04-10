---
name: quiz-mode
description: >
  Generate flashcards and self-test questions from the Rhoton Wiki for exam prep.
  Trigger on: "quiz", "flashcards", "test me", "viva", "study mode", "anki", 
  "perforator quiz", "approach quiz", "test my knowledge".
---

# Quiz Mode — Flashcard & Exam Generator

Generate study materials from the Rhoton Neuroanatomy Wiki for surgical anatomy review.

## Before You Start

1. Read `.env` for `OBSIDIAN_VAULT_PATH`
2. Read `index.md` for full page inventory
3. Check `_quizzes/` for existing generated quizzes

## Modes

### 1. Flashcard Mode (default)
Generate Anki-compatible front/back cards.

**Sources per card:**
- `summary:` field → quick-recall card (Q: "What is [title]?" A: summary)
- `## Surgical Significance` → clinical card (Q: "Surgical importance of [title]?" A: key points)
- `## Relations` / `## Related Pages` → connection card (Q: "What structures relate to [title]?" A: linked entities)
- Breadcrumbs `parent:` → hierarchy card (Q: "What contains [title]?" A: parent)

**Output:** `_quizzes/flashcards-{topic}.md` + `_quizzes/anki-export.csv`

**Anki CSV format:**
```
front<TAB>back<TAB>tags
```

### 2. Viva Mode
Generate oral exam chains across multiple pages.

**Example questions:**
- "Trace CN VI from its nucleus to the orbit, naming every structure it passes through."
- "Describe the arterial supply of the internal capsule and the clinical consequence of each vessel's occlusion."
- "List the cisterns traversed during a pterional approach to the basilar apex."

**Generation method:**
1. Pick a seed page
2. Follow `parent:`, `branch-of:`, `traverses:`, `approach-to:` Breadcrumbs relations
3. Chain 3-5 pages into a multi-hop question
4. Answer synthesized from the chain

### 3. Approach Quiz
Given a lesion location → select the approach.

**Method:**
1. Read all `references/` pages (surgical approaches)
2. Use `approach-to:` relations to build target→approach map
3. Generate: "A patient has a [lesion] at [location]. Which approach do you choose and why?"

### 4. Perforator Quiz
Given an artery → name perforators, territories, sacrifice consequence.

**Method:**
1. Read `synthesis/perforating-arteries.md` as master reference
2. For each major artery, generate:
   - "Name the perforating branches of [artery]"
   - "What territory does [perforator] supply?"
   - "What deficit results from [perforator] sacrifice?"

## Tag-Based Filtering

User can specify topic: `/quiz posterior-fossa` → only pages tagged `posterior-fossa`.

Filter logic:
```
pages = [p for p in vault if topic_tag in p.tags]
```

## Difficulty Scaling

| Level | Depth | Example |
|-------|-------|---------|
| 1 | Single page recall | "What are the segments of the ICA?" |
| 2 | Two-hop connection | "Which perforators arise from P1 and what do they supply?" |
| 3 | Multi-page synthesis | "Trace the venous drainage from the thalamus to the internal jugular vein" |

## Output Files

- `_quizzes/flashcards-{topic}.md` — Obsidian-viewable cards
- `_quizzes/anki-export.csv` — Importable to Anki
- `_quizzes/viva-{topic}.md` — Oral exam questions with model answers
