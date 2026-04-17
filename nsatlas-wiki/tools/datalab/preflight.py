#!/usr/bin/env python3
"""
Stage 0 — NSAtlas Datalab preflight. Read-only, no money spent.

Checks:
1. DATALAB_API_KEY present in .env (never prints it).
2. GET /api/v1/health returns {"status":"ok"}.
3. NSATLAS_SOURCES_DIR exists with PDFs.
4. Writes nsatlas-wiki/extractions/datalab/preflight.json.
"""

from __future__ import annotations

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import dotenv_values

REPO = Path(__file__).resolve().parents[2].parent
ENV = REPO / ".env"
OUT_DIR = REPO / "nsatlas-wiki" / "extractions" / "datalab"
OUT = OUT_DIR / "preflight.json"
HEALTH_URL = "https://www.datalab.to/api/v1/health"
MAX_BYTES = 209_715_200  # 200 MiB per-file cap


def die(code: int, msg: str) -> None:
    print(f"[PREFLIGHT FAIL] {msg}", file=sys.stderr)
    sys.exit(code)


def hash8(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:8]


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Load key
    if not ENV.exists():
        die(3, f".env missing at {ENV}")
    env = dotenv_values(ENV)
    key = env.get("DATALAB_API_KEY", "").strip()
    if not key:
        die(3, "DATALAB_API_KEY missing or empty in .env")
    key_fingerprint = hash8(key)

    # 2. Health check
    try:
        r = requests.get(HEALTH_URL, timeout=15)
    except requests.RequestException as e:
        die(3, f"health GET failed: {e}")
    if r.status_code != 200:
        die(3, f"health returned HTTP {r.status_code}: {r.text[:200]}")
    try:
        health = r.json()
    except ValueError:
        die(3, f"health returned non-JSON: {r.text[:200]}")

    # 3. Sources directory
    sources_dir = env.get("NSATLAS_SOURCES_DIR", "").strip()
    if not sources_dir:
        die(3, "NSATLAS_SOURCES_DIR missing in .env")
    src = Path(sources_dir)
    if not src.is_dir():
        die(3, f"NSATLAS_SOURCES_DIR not a directory: {src}")

    pdfs = list(src.rglob("*.pdf"))
    if not pdfs:
        die(3, f"no PDFs in {src}")

    # Check largest PDF against cap
    largest = max(pdfs, key=lambda p: p.stat().st_size)
    largest_size = largest.stat().st_size
    total_size = sum(p.stat().st_size for p in pdfs)

    # Pick smallest PDF for sample SHA
    smallest = min(pdfs, key=lambda p: p.stat().st_size)
    h = hashlib.sha256()
    with smallest.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    sample_sha = h.hexdigest()

    report = {
        "stage": 0,
        "pipeline": "nsatlas",
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "env_file": str(ENV),
        "key_fingerprint": key_fingerprint,
        "health": {
            "url": HEALTH_URL,
            "http_status": r.status_code,
            "body": health,
        },
        "sources": {
            "dir": str(src),
            "pdf_count": len(pdfs),
            "total_size_bytes": total_size,
            "total_size_mb": round(total_size / (1024 * 1024), 2),
            "largest_file": str(largest.name),
            "largest_size_mb": round(largest_size / (1024 * 1024), 2),
            "all_under_200mb_cap": largest_size <= MAX_BYTES,
            "sample_file": str(smallest.name),
            "sample_sha256": sample_sha,
        },
        "python": {
            "version": sys.version.split()[0],
            "requests": requests.__version__,
        },
        "result": "OK",
    }

    # Atomic write
    tmp = OUT.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(report, indent=2))
    tmp.replace(OUT)
    print(f"[PREFLIGHT OK] wrote {OUT}")
    print(f"  key fingerprint: {key_fingerprint}")
    print(f"  health: {health}")
    print(f"  PDFs: {len(pdfs)} files, {report['sources']['total_size_mb']} MB total")
    print(
        f"  largest: {largest.name} ({report['sources']['largest_size_mb']} MB)"
        + (" — OVER 200MB CAP" if largest_size > MAX_BYTES else "")
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
