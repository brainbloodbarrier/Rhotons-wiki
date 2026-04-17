#!/usr/bin/env python3
"""
Cleanup junk images from NSAtlas Datalab extractions.

Removes website UI elements (logos, hamburger menus, icons) that were
embedded in the original PDFs. Two junk criteria:

  1. Images < 1 KB (always junk — icons/UI fragments)
  2. Images whose content (SHA-256) appears in 5+ different articles (repeated branding)

Usage:
    ./cleanup_images.py --dry-run    # preview without deleting
    ./cleanup_images.py              # delete junk + update markdown & metadata
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------- config
REPO = Path(__file__).resolve().parents[2].parent
CHAPTERS_DIR = REPO / "nsatlas-wiki" / "extractions" / "datalab" / "chapters"

SIZE_THRESHOLD = 1024  # bytes — images below this are always junk
FREQ_THRESHOLD = 5  # content hash in this many+ articles = repeated branding


# --------------------------------------------------------------------- helpers
def atomic_write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    if isinstance(data, str):
        tmp.write_text(data)
    else:
        tmp.write_bytes(data)
    tmp.replace(path)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def identify_junk(
    chapters_dir: Path,
) -> dict[str, dict[str, str]]:
    """Identify junk images using content hashing and size thresholds.

    Returns {article_id: {filename: reason}} for all junk instances.

    Uses SHA-256 of file bytes (not Datalab filenames, which are NOT
    content hashes — different images can share a filename across articles).
    """
    # Pass 1: build content-hash frequency map and per-file metadata
    # content_hash -> set of article_ids
    hash_freq: dict[str, set[str]] = {}
    # (article_id, filename) -> (content_hash, size)
    file_info: dict[tuple[str, str], tuple[str, int]] = {}

    for article_dir in sorted(chapters_dir.iterdir()):
        images_dir = article_dir / "images"
        if not images_dir.is_dir():
            continue
        article_id = article_dir.name
        for img in images_dir.iterdir():
            if not img.is_file():
                continue
            content_hash = sha256_file(img)
            size = img.stat().st_size
            file_info[(article_id, img.name)] = (content_hash, size)
            hash_freq.setdefault(content_hash, set()).add(article_id)

    # Identify repeated content hashes (5+ distinct articles)
    junk_hashes = {
        h for h, articles in hash_freq.items() if len(articles) >= FREQ_THRESHOLD
    }

    # Pass 2: mark junk per (article, filename)
    junk: dict[str, dict[str, str]] = {}
    for (article_id, fname), (content_hash, size) in file_info.items():
        reason = None
        if content_hash in junk_hashes:
            n = len(hash_freq[content_hash])
            reason = f"repeated content in {n} articles"
        elif size < SIZE_THRESHOLD:
            reason = f"< 1KB ({size} bytes)"
        if reason:
            junk.setdefault(article_id, {})[fname] = reason

    return junk


# --------------------------------------------------------- markdown cleanup
# Structural markers that stop alt-text consumption
_STRUCTURAL_RE = re.compile(
    r"^("
    r"\*\*Figure\s"  # **Figure N: ...
    r"|#{1,6}\s"  # headings
    r"|!\["  # another image
    r"|\{\d+\}-+$"  # page break {N}----
    r"|\|"  # table row
    r"|- "  # list item
    r"|\d+\.\s"  # ordered list item
    r")"
)


def clean_markdown(text: str, junk_filenames: set[str]) -> str:
    """Remove image references and trailing alt-text lines for junk images.

    Pattern emitted by Datalab for each image:

        ![alt text](hash_img.jpg)

        alt text repeated (sometimes with minor variation)

        alt text repeated again

        **Figure N: caption...**

    We remove the ![...](junk) line and subsequent plain-text lines
    (assumed to be duplicated alt-text). We stop at any structural marker
    (headings, **Figure**, other images, page breaks, etc.) to preserve
    caption lines that carry useful content.
    """
    lines = text.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        # Match ![...](filename)
        m = re.match(r"^!\[.*?\]\(([^)]+)\)", line)
        if m and m.group(1) in junk_filenames:
            # Skip this image line
            i += 1
            # Consume trailing blank lines and plain-text alt-text echoes
            while i < len(lines):
                candidate = lines[i]
                stripped = candidate.strip()
                # Blank line — skip
                if not stripped:
                    i += 1
                    continue
                # Structural marker — stop consuming
                if _STRUCTURAL_RE.match(candidate):
                    break
                # Plain text (alt-text echo) — skip
                i += 1
            continue
        out.append(line)
        i += 1

    # Collapse runs of 3+ blank lines to 2
    collapsed: list[str] = []
    blank_run = 0
    for line in out:
        if line.strip() == "":
            blank_run += 1
            if blank_run <= 2:
                collapsed.append(line)
        else:
            blank_run = 0
            collapsed.append(line)

    return "\n".join(collapsed)


# ------------------------------------------------------------------- main
def main() -> int:
    p = argparse.ArgumentParser(
        description="Cleanup junk images from NSAtlas Datalab extractions"
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview deletions without modifying files",
    )
    args = p.parse_args()

    if not CHAPTERS_DIR.is_dir():
        print(f"[FAIL] chapters dir not found: {CHAPTERS_DIR}", file=sys.stderr)
        return 1

    # junk: {article_id: {filename: reason}}
    junk = identify_junk(CHAPTERS_DIR)
    if not junk:
        print("[OK] No junk images found.")
        return 0

    # --- Process per article ---
    total_deleted = 0
    total_bytes_saved = 0
    articles_touched = 0
    by_reason: dict[str, int] = {}
    md_files_updated = 0

    for article_id in sorted(junk.keys()):
        article_dir = CHAPTERS_DIR / article_id
        images_dir = article_dir / "images"
        if not images_dir.is_dir():
            continue

        junk_in_article = junk[article_id]
        articles_touched += 1
        article_bytes = 0

        for fname in sorted(junk_in_article.keys()):
            img = images_dir / fname
            if not img.exists():
                continue
            reason = junk_in_article[fname]
            size = img.stat().st_size
            article_bytes += size

            cat = "< 1KB" if reason.startswith("< 1KB") else "repeated"
            by_reason[cat] = by_reason.get(cat, 0) + 1

            if args.dry_run:
                print(f"  [DEL] {article_id}/images/{fname}  ({size} B)  — {reason}")
            else:
                img.unlink()

            total_deleted += 1

        total_bytes_saved += article_bytes

        # --- Update chapter.md ---
        junk_filenames = set(junk_in_article.keys())
        chapter_md = article_dir / "chapter.md"
        if chapter_md.exists():
            original = chapter_md.read_text()
            cleaned = clean_markdown(original, junk_filenames)
            if cleaned != original:
                md_files_updated += 1
                if args.dry_run:
                    removed_lines = len(original.split("\n")) - len(cleaned.split("\n"))
                    print(
                        f"  [MD]  {article_id}/chapter.md  — {removed_lines} lines removed"
                    )
                else:
                    atomic_write(chapter_md, cleaned)

        # --- Update metadata.json ---
        meta_path = article_dir / "metadata.json"
        if meta_path.exists():
            meta = json.loads(meta_path.read_text())
            if not args.dry_run:
                remaining = len([f for f in images_dir.iterdir() if f.is_file()])
                meta["image_count"] = remaining
                atomic_write(meta_path, json.dumps(meta, indent=2))

    # --- Report ---
    print()
    mode = "[DRY-RUN] " if args.dry_run else ""
    total_junk_files = sum(len(v) for v in junk.values())
    print(f"{mode}Cleanup summary")
    print(f"  Junk instances identified : {total_junk_files}")
    print(f"  Total images deleted      : {total_deleted}")
    print(f"  Articles touched          : {articles_touched}")
    print(f"  chapter.md files updated  : {md_files_updated}")
    print(
        f"  Space saved               : {total_bytes_saved:,} bytes ({total_bytes_saved / 1024:.1f} KB)"
    )
    print()
    print("  By category:")
    for cat, count in sorted(by_reason.items()):
        print(f"    {cat:20s} : {count}")
    print()
    if args.dry_run:
        print("  No files were modified. Rerun without --dry-run to apply.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
