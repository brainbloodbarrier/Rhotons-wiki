#!/usr/bin/env python3
"""Phase A: deterministic figure -> vault page attribution.

For every image Datalab extracted under
rhoton-wiki/extractions/datalab/chapters/*/images/*.jpg, look up its source
block in the matching json-pass/chapter.json, find the nearest caption and
enclosing section header, then score vault pages by token-overlap (Jaccard)
against the caption + header + chapter title. The top-3 candidates are
emitted along with a confidence bucket.

Output: rhoton-wiki/extractions/datalab-augment/plan/figures-attribution.json

Writes use *.tmp -> os.rename so partial runs never leave half-written JSON.
This script is READ-ONLY over rhoton-wiki/vault/ and
rhoton-wiki/extractions/datalab/.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from _shared import atomic_write_json, html_to_text, parse_frontmatter

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

SCRIPT_DIR = Path(__file__).resolve().parent
RHOTON_ROOT = SCRIPT_DIR.parent.parent
VAULT_ROOT = RHOTON_ROOT / "vault"
DATALAB_ROOT = RHOTON_ROOT / "extractions" / "datalab"
CHAPTERS_ROOT = DATALAB_ROOT / "chapters"
PAGE_RANGES_PATH = DATALAB_ROOT / "page-ranges.json"
PLAN_DIR = RHOTON_ROOT / "extractions" / "datalab-augment" / "plan"
OUTPUT_PATH = PLAN_DIR / "figures-attribution.json"

VAULT_CATEGORIES = ("concepts", "entities", "synthesis", "references")

# Minimal stopword list — intentionally small so anatomy-heavy captions keep
# their signal tokens.
STOPWORDS = frozenset(
    {
        "the",
        "a",
        "an",
        "of",
        "and",
        "or",
        "in",
        "on",
        "with",
        "to",
        "for",
        "is",
        "are",
        "from",
    }
)

HIGH_THRESHOLD = 0.6
MEDIUM_THRESHOLD = 0.3
LOW_THRESHOLD = 0.1

TOKEN_RE = re.compile(r"[a-z0-9]+")


# --------------------------------------------------------------------------- #
# Frontmatter / vault loader
# --------------------------------------------------------------------------- #


def tokenize(text: str) -> set[str]:
    if not text:
        return set()
    tokens = TOKEN_RE.findall(text.lower())
    return {t for t in tokens if t not in STOPWORDS and len(t) > 1}


def load_vault_pages() -> list[dict]:
    """Load vault pages into dicts: {path, title, aliases, tokens}."""
    pages: list[dict] = []
    for cat in VAULT_CATEGORIES:
        catdir = VAULT_ROOT / cat
        if not catdir.exists():
            print(
                f"warning: vault category {cat!r} not found at {catdir}",
                file=sys.stderr,
            )
            continue
        for entry in sorted(catdir.iterdir()):
            if not (entry.is_file() and entry.suffix == ".md"):
                continue
            try:
                content = entry.read_text()
            except OSError as e:
                print(f"warning: could not read {entry}: {e}", file=sys.stderr)
                continue
            fields = parse_frontmatter(content)
            if not fields:
                continue
            title = str(fields.get("title", "")).strip()
            aliases_raw = fields.get("aliases", [])
            if isinstance(aliases_raw, str):
                aliases = [aliases_raw]
            elif isinstance(aliases_raw, list):
                aliases = [str(a) for a in aliases_raw]
            else:
                aliases = []
            rel = entry.relative_to(VAULT_ROOT).as_posix()
            text = " ".join([title, *aliases, entry.stem.replace("-", " ")])
            tokens = tokenize(text)
            title_tokens = tokenize(title)
            if not tokens:
                continue
            pages.append(
                {
                    "path": rel,
                    "title": title,
                    "aliases": aliases,
                    "tokens": tokens,
                    "title_tokens": title_tokens or tokens,
                }
            )
    return pages


# --------------------------------------------------------------------------- #
# Chapter metadata
# --------------------------------------------------------------------------- #


def load_chapter_titles() -> dict[str, str]:
    """chapter_id -> canonical chapter title, from page-ranges.json."""
    if not PAGE_RANGES_PATH.exists():
        print(f"ERROR: {PAGE_RANGES_PATH} not found", file=sys.stderr)
        sys.exit(1)
    with PAGE_RANGES_PATH.open() as f:
        data = json.load(f)
    out: dict[str, str] = {}
    for part in data.get("parts", []):
        for chapter in part.get("chapters", []):
            cid = chapter.get("chapter_id")
            title = chapter.get("title", "")
            if cid:
                out[cid] = title
    return out


# --------------------------------------------------------------------------- #
# Per-chapter figure walking
# --------------------------------------------------------------------------- #


def _bbox_center_y(bbox: list[float] | None) -> float | None:
    if not bbox or len(bbox) < 4:
        return None
    return (bbox[1] + bbox[3]) / 2.0


def process_chapter(
    chapter_id: str,
    chapter_title: str,
    vault_pages: list[dict],
    attributions: dict[str, dict],
) -> tuple[int, int, int]:
    """Return (figures_seen, figures_attributed, figures_excluded)."""
    chapter_dir = CHAPTERS_ROOT / chapter_id
    images_dir = chapter_dir / "images"
    jp = chapter_dir / "json-pass" / "chapter.json"
    if not jp.exists():
        print(
            f"warning: missing json-pass/chapter.json for {chapter_id}",
            file=sys.stderr,
        )
        return 0, 0, 0

    try:
        with jp.open() as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        print(f"warning: could not parse {jp}: {e}", file=sys.stderr)
        return 0, 0, 0

    # Build id -> block lookup so section_hierarchy IDs resolve.
    id_to_block: dict[str, dict] = {}
    for page in data.get("children", []):
        if page.get("id"):
            id_to_block[page["id"]] = page
        for leaf in page.get("children", []):
            if leaf.get("id"):
                id_to_block[leaf["id"]] = leaf

    # Flatten every leaf block across all pages so we can search for caption
    # neighbours that live on the *adjacent* page. Rhoton figures frequently
    # span two facing pages: the image panels on one page, the caption on the
    # next. Keeping leaves globally also lets us track running section state
    # across page boundaries.
    all_leaves: list[dict] = []
    for page in data.get("children", []):
        all_leaves.extend(page.get("children", []))

    # Pre-index captions by page number for O(1) neighbour lookup.
    captions_by_page: dict[int, list[dict]] = {}
    for leaf in all_leaves:
        if leaf.get("block_type") in ("Caption", "FigureCaption"):
            page_num = leaf.get("page")
            if page_num is not None:
                captions_by_page.setdefault(page_num, []).append(leaf)

    figures_seen = 0
    figures_attributed = 0
    figures_excluded = 0

    running_section_text: str | None = None
    for leaf in all_leaves:
        bt = leaf.get("block_type")
        if bt == "SectionHeader":
            running_section_text = html_to_text(leaf.get("html"))
            continue
        images = leaf.get("images") or {}
        if not images:
            continue
        if leaf.get("inference_failed"):
            figures_excluded += 1
            continue

        # Normalise image filename list.
        if isinstance(images, dict):
            image_files = list(images.keys())
        elif isinstance(images, list):
            image_files = list(images)
        else:
            image_files = []
        if not image_files:
            figures_excluded += 1
            continue

        figures_seen += len(image_files)

        # The Picture/Figure block's own html already contains the img alt
        # attribute plus a <div class="img-description"> label block with
        # rich anatomical terminology — that is our primary caption signal.
        own_text = html_to_text(leaf.get("html"))

        # Still try to locate a nearest Caption/FigureCaption block. Search
        # the same page first, then the next page, then the previous page.
        # This handles the common two-page Rhoton figure layout.
        source_page = leaf.get("page")
        fig_mid = _bbox_center_y(leaf.get("bbox"))
        best_caption: dict | None = None
        best_dy: float | None = None
        candidate_pages: list[int] = []
        if source_page is not None:
            candidate_pages = [
                source_page,
                source_page + 1,
                source_page - 1,
            ]
        for cand_page_num in candidate_pages:
            for cand in captions_by_page.get(cand_page_num, []):
                c_mid = _bbox_center_y(cand.get("bbox"))
                if fig_mid is None or c_mid is None:
                    # Without bbox geometry we still accept the first match
                    # on the same page as a last resort.
                    if best_caption is None and cand_page_num == source_page:
                        best_caption = cand
                    continue
                # Same-page captions score zero base penalty; off-page captions
                # get a large synthetic penalty so on-page matches always win.
                page_penalty = 0.0 if cand_page_num == source_page else 100000.0
                dy = abs(c_mid - fig_mid) + page_penalty
                if best_dy is None or dy < best_dy:
                    best_dy = dy
                    best_caption = cand
        caption_text = html_to_text(best_caption.get("html")) if best_caption else ""
        # Expose the richer own_text + caption as the reported caption so
        # downstream consumers can inspect both sources.
        displayed_caption = " ".join(t for t in (own_text, caption_text) if t)

        # Resolve section headers from section_hierarchy.  We collect ALL
        # levels (not just deepest) because they contain the sub-chapter
        # structure that maps to vault page titles (e.g. Level 2 might say
        # "ANTERIOR CEREBRAL ARTERY" which matches the vault page exactly).
        # The deepest level is exposed as the reported ``section_header``.
        section_texts: list[str] = []
        section_text = ""
        sh = leaf.get("section_hierarchy") or {}
        if isinstance(sh, dict) and sh:
            for level_key in sorted(sh.keys(), key=lambda k: int(k)):
                target_id = sh[level_key]
                block = id_to_block.get(target_id)
                if block is not None:
                    t = html_to_text(block.get("html"))
                    if t:
                        section_texts.append(t)
            if section_texts:
                section_text = section_texts[-1]  # deepest for display
        if not section_text and running_section_text:
            section_text = running_section_text
            section_texts = [running_section_text]

        # Build per-level figure token sets for Jaccard scoring. Each
        # section hierarchy level (e.g. "ANTERIOR CEREBRAL ARTERY" at level
        # 2, "A1 Segment" at level 4) is scored independently against every
        # vault page. The per-page max across all levels is kept. This avoids
        # dilution: a level-2 header that perfectly matches a page title gives
        # Jaccard ~1.0 even if level-4 header introduces noise.
        fig_token_sets: list[set[str]] = []
        for st in section_texts:
            t = tokenize(st)
            if t:
                fig_token_sets.append(t)

        # Score every vault page. For each page, compute Jaccard against
        # every per-level figure token set AND against both the page's full
        # tokens (title+aliases+stem) and title-only tokens. Take the max.
        scored: list[tuple[float, dict]] = []
        for page_meta in vault_pages:
            p_full = page_meta["tokens"]
            p_title = page_meta["title_tokens"]
            best = 0.0
            for ft in fig_token_sets:
                for pt in (p_full, p_title):
                    inter = ft & pt
                    if inter:
                        score = len(inter) / max(1, len(ft | pt))
                        if score > best:
                            best = score
            if best <= 0:
                continue
            scored.append((best, page_meta))
        scored.sort(key=lambda it: it[0], reverse=True)
        top3 = [
            {"page": meta["path"], "score": round(score, 4)}
            for score, meta in scored[:3]
        ]

        if top3:
            top_score = top3[0]["score"]
            if top_score >= HIGH_THRESHOLD:
                assigned = top3[0]["page"]
                confidence = "high"
                figures_attributed += 1
            elif top_score >= MEDIUM_THRESHOLD:
                assigned = top3[0]["page"]
                confidence = "medium"
                figures_attributed += 1
            elif top_score >= LOW_THRESHOLD:
                assigned = top3[0]["page"]
                confidence = "low"
                figures_attributed += 1
            else:
                assigned = None
                confidence = "unattributed"
        else:
            assigned = None
            confidence = "unattributed"

        # Emit one entry per source filename (typical case: one image per
        # block, but handle multi-image blocks defensively).
        for fn in image_files:
            abs_src = images_dir / fn
            if fn in attributions:
                # Same filename seen twice in JSON (shouldn't normally
                # happen). Keep the higher-scoring record.
                existing = attributions[fn]
                existing_score = (
                    existing["candidates"][0]["score"]
                    if existing.get("candidates")
                    else -1.0
                )
                new_score = top3[0]["score"] if top3 else -1.0
                if new_score <= existing_score:
                    continue
            attributions[fn] = {
                "source_path": str(abs_src),
                "chapter_id": chapter_id,
                "source_page": source_page,
                "bbox": leaf.get("bbox"),
                "caption": displayed_caption,
                "section_header": section_text,
                "candidates": top3,
                "assigned": assigned,
                "confidence": confidence,
            }

    return figures_seen, figures_attributed, figures_excluded


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #


def main() -> int:
    if not CHAPTERS_ROOT.exists():
        print(f"ERROR: {CHAPTERS_ROOT} does not exist", file=sys.stderr)
        return 1

    vault_pages = load_vault_pages()
    print(f"Loaded {len(vault_pages)} vault pages with parseable frontmatter")

    chapter_titles = load_chapter_titles()
    print(f"Loaded {len(chapter_titles)} chapter titles from page-ranges.json")

    attributions: dict[str, dict] = {}
    total_seen = 0
    total_attributed = 0
    total_excluded = 0

    for chapter_id in sorted(chapter_titles.keys()):
        title = chapter_titles[chapter_id]
        seen, attributed, excluded = process_chapter(
            chapter_id, title, vault_pages, attributions
        )
        total_seen += seen
        total_attributed += attributed
        total_excluded += excluded
        if seen:
            print(f"  {chapter_id}: seen={seen} attributed={attributed}")

    atomic_write_json(OUTPUT_PATH, attributions)

    high = sum(1 for v in attributions.values() if v["confidence"] == "high")
    medium = sum(1 for v in attributions.values() if v["confidence"] == "medium")
    low = sum(1 for v in attributions.values() if v["confidence"] == "low")
    unattr = sum(1 for v in attributions.values() if v["confidence"] == "unattributed")

    print(
        "\n=== attribute_figures.py summary ===\n"
        f"  chapters processed:     {len(chapter_titles)}\n"
        f"  figures seen:           {total_seen}\n"
        f"  figures written:        {len(attributions)}\n"
        f"  figures excluded:       {total_excluded}\n"
        f"  high confidence:        {high}\n"
        f"  medium confidence:      {medium}\n"
        f"  low confidence:         {low}\n"
        f"  unattributed:           {unattr}\n"
        f"  output written to:      {OUTPUT_PATH.relative_to(RHOTON_ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
