#!/usr/bin/env python3
"""Phase B of the datalab-augment pipeline: stage extracted figures into the vault.

Reads a figures-attribution.json produced by Phase A (map_chapters.py +
attribute_figures.py), copies each referenced JPG into the vault's
_attachments/figures/ directory under a deterministic filename, verifies the
copy via SHA-256, and writes a figures-manifest.json describing the staged
assets for downstream consumers.

Stdlib only (pathlib, json, hashlib, shutil, argparse, sys, os). No network.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any

# Repo-relative paths. All paths below are resolved against REPO_ROOT, which is
# the nearest ancestor directory containing a `rhoton-wiki/` folder. This keeps
# the script usable whether it is invoked from the tool directory or the repo
# root.
DEFAULT_ATTRIBUTION_REL = Path(
    "rhoton-wiki/extractions/datalab-augment/plan/figures-attribution.json"
)
MANIFEST_REL = Path("rhoton-wiki/extractions/datalab-augment/figures-manifest.json")
ATTACHMENTS_REL = Path("rhoton-wiki/vault/_attachments/figures")


def find_repo_root(start: Path) -> Path:
    """Walk upward from *start* until a directory containing rhoton-wiki/ is found."""
    current = start.resolve()
    for candidate in [current, *current.parents]:
        if (candidate / "rhoton-wiki").is_dir():
            return candidate
    # Fall back to the starting directory so downstream errors are clearer.
    return start.resolve()


def sha256_of_file(path: Path) -> str:
    """Return the hex SHA-256 digest of *path* using a streaming read."""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def resolve_source(source_path: str, repo_root: Path) -> Path:
    """Resolve a source path from the attribution JSON against the repo root."""
    p = Path(source_path)
    if not p.is_absolute():
        p = repo_root / p
    return p


def load_attribution(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        sys.stderr.write(
            f"[ERROR] figures-attribution.json not found at {path}\n"
            "        Run map_chapters.py and attribute_figures.py first "
            "(Phase A of datalab-augment).\n"
        )
        sys.exit(2)
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        sys.stderr.write(
            f"[ERROR] {path} must contain a JSON object keyed by source filename.\n"
        )
        sys.exit(2)
    return data


def group_by_chapter(
    attribution: dict[str, dict[str, Any]],
) -> dict[str, list[str]]:
    """Return {chapter_id: [source_filename, ...]} with deterministic order."""
    grouped: dict[str, list[str]] = {}
    for source_filename in sorted(attribution.keys()):
        entry = attribution[source_filename]
        chapter_id = entry.get("chapter_id")
        if not chapter_id:
            sys.stderr.write(f"[WARN] skipping {source_filename}: missing chapter_id\n")
            continue
        grouped.setdefault(chapter_id, []).append(source_filename)
    return grouped


def compute_destination_name(
    chapter_id: str,
    source_page: int,
    idx: int,
    sha8: str,
) -> str:
    return f"{chapter_id}-p{source_page}-fig-{idx:03d}-{sha8}.jpg"


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    path.parent.mkdir(parents=True, exist_ok=True)
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.rename(tmp, path)


def copy_and_verify(source: Path, destination: Path, source_sha: str) -> None:
    """Copy *source* to *destination* atomically and verify SHA-256 equality."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_suffix(destination.suffix + ".tmp")
    shutil.copy2(source, tmp)
    copied_sha = sha256_of_file(tmp)
    if copied_sha != source_sha:
        tmp.unlink(missing_ok=True)
        raise RuntimeError(
            f"SHA-256 mismatch after copy: {source} -> {tmp} "
            f"(expected {source_sha}, got {copied_sha})"
        )
    os.rename(tmp, destination)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Phase B: stage Datalab figures into the vault _attachments/figures/ "
            "directory and emit figures-manifest.json."
        )
    )
    parser.add_argument(
        "--fixture",
        type=Path,
        default=None,
        help="Path to an alternate figures-attribution.json (used by the e2e test fixture).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List copy operations without performing them.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    repo_root = find_repo_root(Path(__file__).parent)
    attribution_path = (
        args.fixture.resolve()
        if args.fixture is not None
        else (repo_root / DEFAULT_ATTRIBUTION_REL)
    )
    attribution = load_attribution(attribution_path)

    attachments_dir = repo_root / ATTACHMENTS_REL
    manifest_path = repo_root / MANIFEST_REL

    grouped = group_by_chapter(attribution)

    manifest: dict[str, dict[str, Any]] = {}
    copied = 0
    skipped = 0
    total = sum(len(v) for v in grouped.values())

    for chapter_id, source_filenames in grouped.items():
        for idx, source_filename in enumerate(source_filenames):
            entry = attribution[source_filename]
            source_path = resolve_source(entry["source_path"], repo_root)

            try:
                source_sha = sha256_of_file(source_path)
            except FileNotFoundError:
                sys.stderr.write(
                    f"[WARN] skipping {source_filename}: source not found at {source_path}\n"
                )
                skipped += 1
                continue
            sha8 = source_sha[:8]
            source_page = int(entry.get("source_page", 0))
            dest_name = compute_destination_name(chapter_id, source_page, idx, sha8)
            dest_path = attachments_dir / dest_name

            if args.dry_run:
                print(f"[DRY-RUN] {source_path} -> {dest_path}")
                continue

            try:
                copy_and_verify(source_path, dest_path, source_sha)
            except Exception as exc:  # noqa: BLE001 — surface any copy failure verbatim
                sys.stderr.write(f"[ERROR] failed to stage {source_filename}: {exc}\n")
                skipped += 1
                continue

            size = dest_path.stat().st_size
            manifest[dest_name] = {
                "source": str(source_path),
                "destination": str(dest_path),
                "size": size,
                "sha256": source_sha,
                "attribution": entry.get("assigned"),
                "caption": entry.get("caption"),
                "section_header": entry.get("section_header"),
                "source_page": source_page,
                "confidence": entry.get("confidence"),
            }
            copied += 1

    if args.dry_run:
        print(f"[DRY-RUN] would copy {total} figures; no manifest written")
        return 0

    atomic_write_json(manifest_path, manifest)
    skipped_note = f"; {skipped} skipped" if skipped else ""
    print(
        f"[OK] copied {copied} / {total} figures; manifest at {manifest_path}{skipped_note}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
