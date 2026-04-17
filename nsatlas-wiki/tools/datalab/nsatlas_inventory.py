#!/usr/bin/env python3
"""
NSAtlas PDF inventory generator.

Walks NSATLAS_SOURCES_DIR, reads page counts via pypdf, emits inventory.json.

Usage:
    python3 nsatlas_inventory.py
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from dotenv import dotenv_values

try:
    from pypdf import PdfReader
except ImportError:
    print("[FAIL] pypdf not installed — pip install pypdf", file=sys.stderr)
    sys.exit(3)

REPO = Path(__file__).resolve().parents[2].parent  # repo root
ENV = REPO / ".env"
OUT_DIR = REPO / "nsatlas-wiki" / "extractions" / "datalab"
OUT = OUT_DIR / "inventory.json"


def slug_to_title(slug: str) -> str:
    """Convert kebab-case slug to Title Case, preserving common abbreviations."""
    abbrevs = {"3d", "avm", "csf", "avf", "ct", "mri", "evd"}
    words = slug.split("-")
    titled = []
    for w in words:
        if w.lower() in abbrevs:
            titled.append(w.upper())
        else:
            titled.append(w.capitalize())
    return " ".join(titled)


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    env = dotenv_values(ENV)
    sources_dir = env.get("NSATLAS_SOURCES_DIR", "").strip()
    if not sources_dir:
        print("[FAIL] NSATLAS_SOURCES_DIR missing in .env", file=sys.stderr)
        return 3
    src = Path(sources_dir)
    if not src.is_dir():
        print(f"[FAIL] NSATLAS_SOURCES_DIR not a directory: {src}", file=sys.stderr)
        return 3

    pdfs = sorted(src.rglob("*.pdf"))
    if not pdfs:
        print(f"[FAIL] no PDFs found in {src}", file=sys.stderr)
        return 3

    articles = []
    errors = []
    total_pages = 0

    for pdf_path in pdfs:
        rel = pdf_path.relative_to(src)
        parts = list(rel.parts)

        # Top-level category is always the first directory
        category = parts[0] if len(parts) > 1 else "uncategorized"
        slug = pdf_path.stem

        # article_id: flatten subcategories → {top-category}--{slug}
        article_id = f"{category}--{slug}"

        # Page count via pypdf
        try:
            reader = PdfReader(str(pdf_path))
            page_count = len(reader.pages)
        except Exception as e:
            print(f"  [warn] could not read {pdf_path.name}: {e}", file=sys.stderr)
            errors.append({"file": str(pdf_path), "error": str(e)})
            page_count = 0

        total_pages += page_count
        size_bytes = pdf_path.stat().st_size

        articles.append(
            {
                "article_id": article_id,
                "title": slug_to_title(slug),
                "category": category,
                "slug": slug,
                "subcategory": "/".join(parts[1:-1]) if len(parts) > 2 else None,
                "pdf_path": str(pdf_path),
                "pdf_size_bytes": size_bytes,
                "page_count": page_count,
            }
        )

    # Sort by category then slug for deterministic ordering
    articles.sort(key=lambda a: (a["category"], a["slug"]))

    inventory = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source_dir": str(src),
        "total_articles": len(articles),
        "total_pages": total_pages,
        "total_size_bytes": sum(a["pdf_size_bytes"] for a in articles),
        "total_size_mb": round(
            sum(a["pdf_size_bytes"] for a in articles) / (1024 * 1024), 2
        ),
        "categories": sorted(set(a["category"] for a in articles)),
        "errors": errors,
        "articles": articles,
    }

    # Atomic write
    tmp = OUT.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(inventory, indent=2))
    tmp.replace(OUT)

    print(f"[INVENTORY OK] wrote {OUT}")
    print(f"  articles: {len(articles)}")
    print(f"  total pages: {total_pages}")
    print(f"  total size: {inventory['total_size_mb']} MB")
    print(f"  categories: {len(inventory['categories'])}")
    if errors:
        print(f"  errors: {len(errors)} (check inventory.json)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
