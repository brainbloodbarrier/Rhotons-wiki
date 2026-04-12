#!/usr/bin/env python3
"""Phase A: deterministic chapter -> vault page mapping.

Walks every curated vault page under rhoton-wiki/vault/{concepts,entities,
synthesis,references}/, parses YAML frontmatter with a regex (no yaml dep),
pulls the ``sources`` field, finds legacy ``Ch.N`` citations (comma lists and
en-dash ranges), and translates them to canonical 20-chapter IDs via a
hardcoded LEGACY_MAP.

Emits four JSON files under rhoton-wiki/extractions/datalab-augment/plan/:

  - chapter-to-pages.json     canonical chapter id -> list[vault_path]
  - legacy-chapter-map.json   audit dump of LEGACY_MAP
  - legacy-chapter-orphans.json citations that failed to map
  - coverage-gaps.json        per-chapter gap flags + candidate_new_pages

Writes use a *.tmp -> os.rename atomic pattern so partial runs never leave
half-written JSON on disk.

This script is READ-ONLY over rhoton-wiki/vault/ and
rhoton-wiki/extractions/datalab/. It never modifies those trees.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

# Resolve repo-relative paths from this file's location:
#   rhoton-wiki/tools/datalab-augment/map_chapters.py -> rhoton-wiki/
SCRIPT_DIR = Path(__file__).resolve().parent
RHOTON_ROOT = SCRIPT_DIR.parent.parent  # rhoton-wiki/
VAULT_ROOT = RHOTON_ROOT / "vault"
DATALAB_ROOT = RHOTON_ROOT / "extractions" / "datalab"
PLAN_DIR = RHOTON_ROOT / "extractions" / "datalab-augment" / "plan"
PAGE_RANGES_PATH = DATALAB_ROOT / "page-ranges.json"

VAULT_CATEGORIES = ("concepts", "entities", "synthesis", "references")

# Legacy 15-chapter printing -> canonical 20-chapter IDs.
# Ch.10-15 sit in the posterior-fossa part and map by best-effort primary
# assignment; downstream consumers must assume one legacy chapter may bleed
# across more than one canonical chapter (e.g. Ch.14-15 ranges split).
LEGACY_MAP = {
    "Ch.1": "p2c01-the-cerebrum",
    "Ch.2": "p2c02-the-supratentorial-arteries",
    "Ch.3": "p2c03-aneurysms",
    "Ch.4": "p2c04-the-cerebral-veins",
    "Ch.5": "p2c05-the-lateral-and-third-ventricles",
    "Ch.6": "p2c06-the-anterior-and-middle-cranial-base",
    "Ch.7": "p2c07-the-orbit",
    "Ch.8": "p2c08-the-sellar-region",
    "Ch.9": "p2c09-the-cavernous-sinus-the-cavernous-venous-plexus-and-the-caro",
    "Ch.10": "p3c10-the-posterior-fossa-cisterns",
    "Ch.11": "p3c01-cerebellum-and-fourth-ventricle",
    "Ch.12": "p3c02-the-cerebellar-arteries",
    "Ch.13": "p3c03-the-posterior-fossa-veins",
    "Ch.14": "p3c06-the-foramen-magnum",
    "Ch.15": "p3c04-the-cerebellopontine-angle-and-posterior-fossa-cranial-nerve",
}

GAP_THRESHOLD = 5  # chapters with < this many mapped pages are flagged as gaps

# Regex finds ``Ch.`` followed by digits, commas, spaces, and ASCII hyphen or
# en-dash. We'll tokenise the captured group ourselves so ranges and lists are
# handled uniformly.
CITATION_RE = re.compile(r"Ch\.\s*([0-9][0-9,\s\-\u2013]*)")

# YAML frontmatter fence: ``---\n...\n---``.
FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def load_canonical_chapter_ids() -> list[str]:
    """Read the authoritative 20-chapter list from page-ranges.json."""
    if not PAGE_RANGES_PATH.exists():
        print(f"ERROR: {PAGE_RANGES_PATH} does not exist", file=sys.stderr)
        sys.exit(1)
    with PAGE_RANGES_PATH.open() as f:
        data = json.load(f)
    chapter_ids: list[str] = []
    for part in data.get("parts", []):
        for chapter in part.get("chapters", []):
            cid = chapter.get("chapter_id")
            if cid:
                chapter_ids.append(cid)
    if not chapter_ids:
        print("ERROR: no chapter_ids parsed from page-ranges.json", file=sys.stderr)
        sys.exit(1)
    return chapter_ids


def parse_frontmatter(content: str) -> dict | None:
    """Extract the raw YAML block from a markdown file or None."""
    m = FRONTMATTER_RE.match(content)
    if not m:
        return None
    return _flat_yaml_fields(m.group(1))


def _flat_yaml_fields(block: str) -> dict:
    """Very small YAML-lite parser: top-level ``key: value`` and list fields.

    Only covers what vault pages use — scalar values and multi-line list
    fields where each line starts with ``-``. We don't need real YAML here.
    """
    fields: dict[str, object] = {}
    current_key: str | None = None
    current_list: list[str] | None = None

    def is_top_level(line: str) -> bool:
        if not line or line[0] in (" ", "\t"):
            return False
        return ":" in line

    for raw in block.split("\n"):
        line = raw.rstrip()
        if current_list is not None:
            stripped = line.lstrip()
            if stripped.startswith("- "):
                current_list.append(_strip_yaml_value(stripped[2:]))
                continue
            if stripped.startswith("-") and len(stripped) == 1:
                continue
            if not line.strip():
                continue
            if is_top_level(line):
                fields[current_key] = current_list  # type: ignore[index]
                current_key = None
                current_list = None
            else:
                # Indented continuation of something unusual; skip.
                continue
        if is_top_level(line):
            key, _, value = line.partition(":")
            key = key.strip()
            value = value.strip()
            if value == "":
                # Could be start of list or nested scalar.
                current_key = key
                current_list = []
            else:
                fields[key] = _strip_yaml_value(value)

    if current_key is not None and current_list is not None:
        fields[current_key] = current_list
    return fields


def _strip_yaml_value(value: str) -> str:
    """Strip wrapping quotes and trailing whitespace from a YAML scalar."""
    v = value.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    return v


def extract_chapter_numbers(citation_text: str) -> tuple[list[int], bool]:
    """Parse the captured content after ``Ch.`` into a list of chapter ints.

    Returns (chapter_nums, ok). ``ok`` is False if any token in the citation
    failed to parse — the caller should treat the whole citation as orphaned.
    """
    # Normalise en-dash to ASCII hyphen.
    text = citation_text.replace("\u2013", "-")
    # Strip trailing punctuation/garbage (we only want the leading numeric chunk).
    # CITATION_RE already gave us mostly clean input, but values like
    # "9 — The Cavernous Sinus" were captured only up to trailing whitespace.
    # Split on commas, then on hyphens for range expansion.
    nums: list[int] = []
    for piece in text.split(","):
        piece = piece.strip()
        if not piece:
            continue
        if "-" in piece:
            try:
                start_s, end_s = piece.split("-", 1)
                start = int(start_s.strip())
                end = int(end_s.strip())
                if end < start:
                    return [], False
                for n in range(start, end + 1):
                    nums.append(n)
            except ValueError:
                return [], False
        else:
            try:
                nums.append(int(piece))
            except ValueError:
                return [], False
    return nums, True


def map_chapter_numbers(
    chapter_nums: list[int],
) -> tuple[list[str], list[int]]:
    """Translate legacy chapter ints to canonical chapter IDs.

    Returns (canonical_ids, unmapped_nums). Unmapped ints accumulate so
    orphaning decisions can use them for the ``reason`` string.
    """
    canonical: list[str] = []
    unmapped: list[int] = []
    for n in chapter_nums:
        key = f"Ch.{n}"
        cid = LEGACY_MAP.get(key)
        if cid is None:
            unmapped.append(n)
        else:
            if cid not in canonical:
                canonical.append(cid)
    return canonical, unmapped


def walk_vault_pages() -> list[Path]:
    """Yield every markdown file under the four canonical vault categories."""
    pages: list[Path] = []
    for cat in VAULT_CATEGORIES:
        catdir = VAULT_ROOT / cat
        if not catdir.exists():
            print(
                f"warning: vault category {cat!r} not found at {catdir}",
                file=sys.stderr,
            )
            continue
        for entry in sorted(catdir.iterdir()):
            if entry.is_file() and entry.suffix == ".md":
                pages.append(entry)
    return pages


def sources_field(fields: dict) -> list[str]:
    """Return the ``sources`` frontmatter entry as a list of strings."""
    raw = fields.get("sources")
    if raw is None:
        return []
    if isinstance(raw, list):
        return [str(s) for s in raw]
    return [str(raw)]


def slugify(text: str) -> str:
    """Produce a kebab-case slug from a heading string."""
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    text = text.strip("-")
    return text


def strip_html(html: str) -> str:
    """Strip HTML tags for slugifying section headers from chapter.json."""
    return re.sub(r"<[^>]+>", "", html).strip()


def candidate_new_pages_for(chapter_id: str) -> list[str]:
    """Walk the chapter's json-pass block tree and collect top-10 unique
    section-header slugs as candidate new page names."""
    jp = DATALAB_ROOT / "chapters" / chapter_id / "json-pass" / "chapter.json"
    if not jp.exists():
        print(
            f"warning: no json-pass file for {chapter_id} at {jp}",
            file=sys.stderr,
        )
        return []
    try:
        with jp.open() as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        print(
            f"warning: could not parse {jp}: {e}",
            file=sys.stderr,
        )
        return []

    seen: set[str] = set()
    slugs: list[str] = []
    for page in data.get("children", []):
        for leaf in page.get("children", []):
            if leaf.get("block_type") != "SectionHeader":
                continue
            raw = leaf.get("html") or leaf.get("markdown") or ""
            text = strip_html(raw)
            if not text:
                continue
            slug = slugify(text)
            if not slug or slug in seen:
                continue
            seen.add(slug)
            slugs.append(slug)
            if len(slugs) == 10:
                return slugs
    return slugs


def atomic_write_json(path: Path, data: object) -> None:
    """Write JSON via *.tmp then os.rename for atomicity."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.rename(tmp, path)


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #


def main() -> int:
    canonical_chapter_ids = load_canonical_chapter_ids()
    print(
        f"Loaded {len(canonical_chapter_ids)} canonical chapter IDs from "
        f"{PAGE_RANGES_PATH.relative_to(RHOTON_ROOT)}"
    )

    pages = walk_vault_pages()
    print(
        f"Discovered {len(pages)} vault pages across {len(VAULT_CATEGORIES)} categories"
    )

    # chapter_id -> list[vault_path (relative to vault root)]
    chapter_to_pages: dict[str, list[str]] = {cid: [] for cid in canonical_chapter_ids}
    orphans: dict[str, dict[str, str]] = {}
    citation_hits = 0
    citation_misses = 0

    for page_path in pages:
        try:
            content = page_path.read_text()
        except OSError as e:
            print(f"warning: could not read {page_path}: {e}", file=sys.stderr)
            continue
        fields = parse_frontmatter(content)
        if not fields:
            continue

        rel_path = page_path.relative_to(VAULT_ROOT).as_posix()

        citations = sources_field(fields)
        assigned_chapters_for_page: list[str] = []
        for citation in citations:
            for m in CITATION_RE.finditer(citation):
                raw_nums = m.group(1)
                nums, ok = extract_chapter_numbers(raw_nums)
                if not ok or not nums:
                    orphans[rel_path] = {
                        "original_citation": "Ch." + raw_nums.strip(),
                        "reason": "could not parse chapter numbers from citation",
                    }
                    citation_misses += 1
                    continue
                canonical, unmapped = map_chapter_numbers(nums)
                if unmapped:
                    orphans[rel_path] = {
                        "original_citation": "Ch." + raw_nums.strip(),
                        "reason": (
                            f"chapter numbers {unmapped!r} outside LEGACY_MAP "
                            "(not auto-resolved)"
                        ),
                    }
                    citation_misses += 1
                    continue
                citation_hits += 1
                for cid in canonical:
                    if cid not in assigned_chapters_for_page:
                        assigned_chapters_for_page.append(cid)

        for cid in assigned_chapters_for_page:
            chapter_to_pages[cid].append(rel_path)

    # Deduplicate + sort each chapter's page list for stable output.
    for cid in chapter_to_pages:
        chapter_to_pages[cid] = sorted(set(chapter_to_pages[cid]))

    # Coverage gaps
    coverage_gaps: dict[str, dict] = {}
    gap_count = 0
    for cid in canonical_chapter_ids:
        mapped_pages = len(chapter_to_pages[cid])
        is_gap = mapped_pages < GAP_THRESHOLD
        candidates = candidate_new_pages_for(cid) if is_gap else []
        if is_gap:
            gap_count += 1
        coverage_gaps[cid] = {
            "mapped_pages": mapped_pages,
            "is_gap": is_gap,
            "candidate_new_pages": candidates,
        }

    # Emit outputs atomically.
    atomic_write_json(PLAN_DIR / "chapter-to-pages.json", chapter_to_pages)
    atomic_write_json(PLAN_DIR / "legacy-chapter-map.json", LEGACY_MAP)
    atomic_write_json(PLAN_DIR / "legacy-chapter-orphans.json", orphans)
    atomic_write_json(PLAN_DIR / "coverage-gaps.json", coverage_gaps)

    # Summary
    total_mapped = sum(len(v) for v in chapter_to_pages.values())
    print(
        "\n=== map_chapters.py summary ===\n"
        f"  canonical chapters:     {len(canonical_chapter_ids)}\n"
        f"  vault pages scanned:    {len(pages)}\n"
        f"  citations resolved:     {citation_hits}\n"
        f"  citations orphaned:     {citation_misses}\n"
        f"  page-chapter edges:     {total_mapped}\n"
        f"  gap chapters:           {gap_count}/{len(canonical_chapter_ids)}\n"
        f"  outputs written to:     {PLAN_DIR.relative_to(RHOTON_ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
