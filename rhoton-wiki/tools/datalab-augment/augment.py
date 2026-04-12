#!/usr/bin/env python3
"""
Datalab-augment CLI skeleton. Logic is implemented in sibling scripts:
- map_chapters.py   (Phase A — chapter mapping)
- attribute_figures.py (Phase A — figure attribution)
- stage_figures.py  (Phase B — figure staging)
- llm_merge.py      (Phase C/E — LLM merge, future)
- validate.py       (Phase F — post-merge validation, future)

This file is the top-level entry point once all phases land.
"""

from __future__ import annotations

import argparse
import sys


PHASES = {
    "map": "Phase A — deterministic chapter-to-page mapping",
    "figures": "Phase B — figure staging to vault/_attachments/figures/",
    "dry-run": "Phase C — LLM merge dry-run (no vault writes)",
    "apply": "Phase E — live apply on wiki/datalab-augment branch",
    "validate": "Phase F — post-merge validation and final report",
}


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="augment.py",
        description="Rhoton Wiki — Datalab → Vault augmentation pipeline",
    )
    subs = parser.add_subparsers(dest="phase", required=True)
    for name, desc in PHASES.items():
        subs.add_parser(name, help=desc)
    args = parser.parse_args()
    print(f"[TBD] phase {args.phase!r} not yet implemented", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
