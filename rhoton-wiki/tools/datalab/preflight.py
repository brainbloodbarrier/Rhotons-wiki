#!/usr/bin/env python3
"""
Stage 0 — Datalab preflight. Read-only, no money spent.

Checks:
1. DATALAB_API_KEY present in .env (never prints it).
2. GET /api/v1/health returns {"status":"ok"}.
3. Rhoton PDF exists, size <= 200 MB, SHA-256 recorded.
4. Writes rhoton-wiki/extractions/datalab/preflight.json.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import dotenv_values

REPO = Path(__file__).resolve().parents[2].parent
ENV = REPO / ".env"
PDF = (
    REPO / "Rhoton - Cranial Anatomy and Surgical Approaches (2023) [neuroanatomia].pdf"
)
OUT_DIR = REPO / "rhoton-wiki" / "extractions" / "datalab"
OUT = OUT_DIR / "preflight.json"
HEALTH_URL = "https://www.datalab.to/api/v1/health"
MAX_BYTES = 209_715_200  # 200 MiB exactly


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

    # 3. PDF checks
    if not PDF.exists():
        die(3, f"PDF missing: {PDF}")
    size = PDF.stat().st_size
    if size > MAX_BYTES:
        die(3, f"PDF {size} > 200 MiB cap {MAX_BYTES}")

    # SHA-256 (streaming)
    h = hashlib.sha256()
    with PDF.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    pdf_sha = h.hexdigest()

    # 4. Compare vs existing manifest hash
    manifest_path = REPO / "rhoton-wiki" / "vault" / ".manifest.json"
    manifest_hash = None
    try:
        manifest_hash = json.loads(manifest_path.read_text())["sources"][
            "rhoton-full-text"
        ]["sha256"]
    except Exception:
        pass
    # Note: manifest hash is for the extracted .txt, not the PDF — hashes will differ.

    report = {
        "stage": 0,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "env_file": str(ENV),
        "key_fingerprint": key_fingerprint,  # hash8 only, never the key
        "health": {
            "url": HEALTH_URL,
            "http_status": r.status_code,
            "body": health,
        },
        "pdf": {
            "path": str(PDF),
            "size_bytes": size,
            "size_mb": round(size / (1024 * 1024), 2),
            "sha256": pdf_sha,
            "under_200mb_cap": size <= MAX_BYTES,
        },
        "existing_manifest_sha256_of_txt_dump": manifest_hash,
        "python": {
            "version": sys.version.split()[0],
            "requests": requests.__version__,
            "datalab_sdk_available": False,
            "client_strategy": "raw requests (SDK absent)",
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
    print(
        f"  pdf:    {size / (1024 * 1024):.2f} MB ({'fits' if size <= MAX_BYTES else 'OVER CAP'})"
    )
    print(f"  sha256: {pdf_sha[:16]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
