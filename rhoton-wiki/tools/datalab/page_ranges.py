#!/usr/bin/env python3
"""
Stage 1 — Derive PDF page ranges per chapter from the Rhoton 2023 outline.

Walks the /Outlines tree, collects top-level part markers and their chapter
children, resolves destinations to 0-indexed page numbers, and writes
rhoton-wiki/extractions/datalab/page-ranges.json plus a human-readable .md.

Read-only. No network.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from pypdf import PdfReader
from pypdf.generic import Destination

REPO = Path("/Users/fax/obsidian-wiki")
PDF = (
    REPO / "Rhoton - Cranial Anatomy and Surgical Approaches (2023) [neuroanatomia].pdf"
)
OUT_DIR = REPO / "rhoton-wiki" / "extractions" / "datalab"
OUT_JSON = OUT_DIR / "page-ranges.json"
OUT_MD = OUT_DIR / "page-ranges.md"


def slugify(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:60]


def flatten(outline, depth: int = 0):
    """
    Yield (depth, title, page_0idx) for every Destination in the outline tree.
    pypdf outlines are a list where nested lists represent children.
    """
    for item in outline:
        if isinstance(item, list):
            yield from flatten(item, depth + 1)
        elif isinstance(item, Destination):
            yield depth, item.title, item
        else:
            # Unknown node type — skip but note it
            yield depth, f"<{type(item).__name__}>", None


def main() -> int:
    if not PDF.exists():
        print(f"[FAIL] PDF missing: {PDF}", file=sys.stderr)
        return 3

    reader = PdfReader(str(PDF))
    total_pages = len(reader.pages)

    # Flatten the outline tree to a list of (depth, title, dest)
    entries = list(flatten(reader.outline))

    # Resolve each destination to a 0-indexed page number
    resolved = []
    for depth, title, dest in entries:
        if dest is None:
            continue
        try:
            page_idx = reader.get_destination_page_number(dest)
        except Exception as e:
            print(f"  [warn] could not resolve '{title}': {e}", file=sys.stderr)
            continue
        resolved.append(
            {"depth": depth, "title": str(title).strip(), "page_0idx": page_idx}
        )

    # Dump the full outline for inspection (top-level entries only)
    print(f"Outline entries resolved: {len(resolved)} / total pages: {total_pages}")
    top = [e for e in resolved if e["depth"] <= 1 and e["page_0idx"] is not None]
    print(f"Top-level (depth<=1) entries: {len(top)}")
    for e in top[:80]:
        print(f"  depth={e['depth']:<2} p={e['page_0idx']:<5} {e['title'][:80]}")

    # Persist raw outline too — might need for debugging later
    (OUT_DIR / "outline-raw.json").write_text(
        json.dumps({"total_pages": total_pages, "entries": resolved}, indent=2)
    )

    # Heuristic chapter extraction:
    # - "Part 1" / "Part 2" / "Part 3" live at depth 0 or 1
    # - Chapters inside each part are one depth level deeper
    # - Chapter titles typically start with a digit+dot: "1. The Cerebrum"
    chapter_re = re.compile(r"^\s*(\d+)\.\s+(.+)")

    # Find candidate chapters — any entry whose title matches "N. Title"
    candidates = []
    for i, e in enumerate(resolved):
        m = chapter_re.match(e["title"])
        if m:
            candidates.append(
                {**e, "num": int(m.group(1)), "clean_title": m.group(2).strip()}
            )

    # Walk the resolved list sequentially and assign each chapter to its parent Part
    # by tracking the last seen Part marker
    parts = []
    current_part = None
    part_idx = 0
    for e in resolved:
        t = e["title"]
        if re.match(r"^\s*PART\s+\d+", t, re.IGNORECASE) or re.match(
            r"^\s*Part\s+\d+", t
        ):
            part_idx += 1
            current_part = {
                "part_num": part_idx,
                "title": t.strip(),
                "start_page": e["page_0idx"],
                "chapters": [],
            }
            parts.append(current_part)
        elif current_part is not None and chapter_re.match(t):
            m = chapter_re.match(t)
            current_part["chapters"].append(
                {
                    "num": int(m.group(1)),
                    "title": m.group(2).strip(),
                    "start_page_0idx": e["page_0idx"],
                }
            )

    # If no Part markers found, fall back: group by chapter number resets
    if not parts:
        print(
            "[info] no Part markers in outline — falling back to chapter-number reset grouping"
        )
        current_part = None
        seen_num = 0
        for c in candidates:
            if c["num"] <= seen_num:
                part_idx += 1
                current_part = {
                    "part_num": part_idx,
                    "title": f"Part {part_idx}",
                    "start_page": c["page_0idx"],
                    "chapters": [],
                }
                parts.append(current_part)
            if current_part is None:
                part_idx += 1
                current_part = {
                    "part_num": part_idx,
                    "title": f"Part {part_idx}",
                    "start_page": c["page_0idx"],
                    "chapters": [],
                }
                parts.append(current_part)
            current_part["chapters"].append(
                {
                    "num": c["num"],
                    "title": c["clean_title"],
                    "start_page_0idx": c["page_0idx"],
                }
            )
            seen_num = c["num"]

    # Compute end_page_0idx per chapter using the next TOP-LEVEL outline entry
    # (depth<=1) as the hard boundary. This correctly excludes Part headers and
    # the Subject Index that follows the last chapter.
    top_level_pages = sorted(
        {
            e["page_0idx"]
            for e in resolved
            if e["depth"] <= 1 and e["page_0idx"] is not None
        }
    )

    for p in parts:
        for c in p["chapters"]:
            # Find the next top-level page strictly greater than this chapter's start
            nxt = None
            for sp in top_level_pages:
                if sp > c["start_page_0idx"]:
                    nxt = sp
                    break
            end = (nxt - 1) if nxt is not None else (total_pages - 1)
            c["end_page_0idx"] = end
            c["page_count"] = end - c["start_page_0idx"] + 1
            c["chapter_id"] = f"p{p['part_num']}c{c['num']:02d}-{slugify(c['title'])}"
            c["page_range_param"] = f"{c['start_page_0idx']}-{c['end_page_0idx']}"

    # Build final report
    total_chapters = sum(len(p["chapters"]) for p in parts)
    pages_covered = sum(c["page_count"] for p in parts for c in p["chapters"])
    report = {
        "stage": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "pdf": str(PDF),
        "total_pages": total_pages,
        "parts": parts,
        "summary": {
            "parts_count": len(parts),
            "chapters_count": total_chapters,
            "pages_covered_by_chapters": pages_covered,
            "front_matter_pages": parts[0]["chapters"][0]["start_page_0idx"]
            if parts and parts[0]["chapters"]
            else None,
        },
    }

    tmp = OUT_JSON.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(report, indent=2))
    tmp.replace(OUT_JSON)

    # Human-readable markdown
    lines = [
        f"# Rhoton 2023 — Chapter → PDF Page Ranges",
        f"",
        f"- PDF: `{PDF.name}`",
        f"- Total PDF pages: {total_pages}",
        f"- Parts: {len(parts)}",
        f"- Chapters: {total_chapters}",
        f"- Pages covered: {pages_covered} ({pages_covered / total_pages * 100:.1f}%)",
        f"- Generated: {report['generated_at']}",
        f"",
    ]
    for p in parts:
        lines.append(f"## Part {p['part_num']} — {p['title']}")
        lines.append("")
        lines.append(
            "| # | Chapter | Pages (0-idx) | Count | `page_range` param | Chapter ID |"
        )
        lines.append("|---|---|---|---|---|---|")
        for c in p["chapters"]:
            lines.append(
                f"| {c['num']} | {c['title']} | {c['start_page_0idx']}-{c['end_page_0idx']} | "
                f"{c['page_count']} | `{c['page_range_param']}` | `{c['chapter_id']}` |"
            )
        lines.append("")
    OUT_MD.write_text("\n".join(lines))

    print(f"\n[OK] wrote {OUT_JSON}")
    print(f"[OK] wrote {OUT_MD}")
    print(
        f"  parts: {len(parts)}  chapters: {total_chapters}  pages covered: {pages_covered}/{total_pages}"
    )
    for p in parts:
        print(f"  Part {p['part_num']}: {len(p['chapters'])} chapters")
    return 0


if __name__ == "__main__":
    sys.exit(main())
