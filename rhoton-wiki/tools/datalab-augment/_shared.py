#!/usr/bin/env python3
"""Shared helpers for the datalab-augment Phase A/B scripts.

Single source of truth for utilities that were previously copy-pasted across
map_chapters.py, attribute_figures.py, and stage_figures.py:

  - YAML-lite frontmatter parsing (parse_frontmatter / _flat_yaml_fields /
    _strip_yaml_value) — a deliberately tiny parser covering only the scalar
    and ``-`` list fields vault pages actually use, with no yaml dependency.
  - atomic_write_json — *.tmp + os.rename so a partial run never leaves
    half-written JSON on disk.
  - html_to_text — HTMLParser-based tag stripping that also harvests
    ``<img alt="...">`` text, the richer of the two HTML strippers that used
    to live here (the regex variant in map_chapters was dropped in favor of
    this one).

Stdlib only. These scripts are invoked directly (``python map_chapters.py``),
so siblings import this module by name via sys.path[0].
"""

from __future__ import annotations

import json
import os
import re
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)


# --------------------------------------------------------------------------- #
# YAML-lite frontmatter
# --------------------------------------------------------------------------- #


def _strip_yaml_value(value: str) -> str:
    """Strip wrapping quotes and trailing whitespace from a YAML scalar."""
    v = value.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ('"', "'"):
        return v[1:-1]
    return v


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
            if stripped == "-":
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


def parse_frontmatter(content: str) -> dict | None:
    """Extract the raw YAML block from a markdown file or None."""
    m = FRONTMATTER_RE.match(content)
    if not m:
        return None
    return _flat_yaml_fields(m.group(1))


# --------------------------------------------------------------------------- #
# Atomic JSON write
# --------------------------------------------------------------------------- #


def atomic_write_json(path: Path, data: Any) -> None:
    """Write JSON via *.tmp then os.rename for atomicity."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.rename(tmp, path)


# --------------------------------------------------------------------------- #
# HTML helpers
# --------------------------------------------------------------------------- #


class _TextExtractor(HTMLParser):
    """Strip tags, collect text content, and harvest img alt attributes.

    Picture/Figure blocks in Datalab's json-pass output embed the most
    informative caption material in ``<img alt="...">`` rather than inline
    text, so we pull those attributes out as if they were regular text.
    """

    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "img":
            for key, value in attrs:
                if key == "alt" and value:
                    self.parts.append(value)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_data(self, data: str) -> None:
        self.parts.append(data)

    def text(self) -> str:
        return " ".join(" ".join(self.parts).split())


def html_to_text(html: str | None) -> str:
    """Strip HTML to plain text, harvesting img alt attributes as content.

    Falls back to a regex tag-strip if HTMLParser chokes on malformed input.
    """
    if not html:
        return ""
    parser = _TextExtractor()
    try:
        parser.feed(html)
        parser.close()
    except Exception:  # noqa: BLE001 — malformed HTML shouldn't crash the run
        return re.sub(r"<[^>]+>", " ", html).strip()
    return parser.text()
