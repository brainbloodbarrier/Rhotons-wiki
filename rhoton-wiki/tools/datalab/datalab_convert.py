#!/usr/bin/env python3
"""
Datalab Convert API client for Rhoton 2023 extraction.

Stage 2 — pilot:
    ./datalab_convert.py pilot --chapter p3c10-the-posterior-fossa-cisterns

Stage 3 — full run (sequential, budget-guarded) [TBD]:
    DATALAB_BUDGET_CENTS=2000 ./datalab_convert.py run

Never logs the API key. All failures non-silent. No 4xx retries except 429.
Downloads artifacts immediately on `complete` (1-hour result expiry).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import dotenv_values

# --------------------------------------------------------------------- config
REPO = Path("/Users/fax/obsidian-wiki")
PDF = (
    REPO / "Rhoton - Cranial Anatomy and Surgical Approaches (2023) [neuroanatomia].pdf"
)
ENV = REPO / ".env"
OUT_DIR = REPO / "rhoton-wiki" / "extractions" / "datalab"
CHAPTERS_DIR = OUT_DIR / "chapters"
RANGES = OUT_DIR / "page-ranges.json"
AUDIT = OUT_DIR / "audit.log"
MANIFEST = OUT_DIR / "manifest.json"

API_BASE = "https://www.datalab.to/api/v1"
CONVERT_URL = f"{API_BASE}/convert"

POLL_INTERVAL_S = 2.0
POLL_TIMEOUT_S = 1800  # 30 min hard cap per job
UPLOAD_TIMEOUT_S = 600  # 10 min for the big upload itself
MAX_429_RETRIES = 6
MAX_5XX_RETRIES = 5
MAX_NET_RETRIES = 5  # transient network / SSL errors during upload


# --------------------------------------------------------------------- helpers
def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def hash8(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:8]


def audit(event: str, **fields) -> None:
    """Append one JSON line to audit.log. Never include the API key or bodies."""
    AUDIT.parent.mkdir(parents=True, exist_ok=True)
    line = {"t": now_iso(), "event": event, **fields}
    with AUDIT.open("a") as f:
        f.write(json.dumps(line) + "\n")


def load_key() -> str:
    env = dotenv_values(ENV)
    key = (env.get("DATALAB_API_KEY") or "").strip()
    if not key:
        print("[FAIL] DATALAB_API_KEY missing in .env", file=sys.stderr)
        sys.exit(3)
    return key


def load_ranges() -> dict:
    if not RANGES.exists():
        print(f"[FAIL] missing {RANGES} — run page_ranges.py first", file=sys.stderr)
        sys.exit(3)
    return json.loads(RANGES.read_text())


def find_chapter(ranges: dict, chapter_id: str) -> dict:
    for p in ranges["parts"]:
        for c in p["chapters"]:
            if c["chapter_id"] == chapter_id:
                return {**c, "part_num": p["part_num"]}
    print(
        f"[FAIL] chapter_id {chapter_id!r} not found in page-ranges.json",
        file=sys.stderr,
    )
    sys.exit(3)


def ordered_chapters(ranges: dict) -> list[dict]:
    out = []
    for p in ranges["parts"]:
        for c in p["chapters"]:
            out.append({**c, "part_num": p["part_num"]})
    return out


def extract_cost_cents(cost) -> int | None:
    """
    Datalab returns cost_breakdown like {'list_cost_cents': 17, 'final_cost_cents': 13}.
    Prefer final, fall back to other plausible shapes, handle scalars.
    """
    if cost is None:
        return None
    if isinstance(cost, dict):
        for k in (
            "final_cost_cents",
            "total_cost_cents",
            "total_cents",
            "cents",
            "total",
            "list_cost_cents",
        ):
            v = cost.get(k)
            if isinstance(v, (int, float)):
                return int(v)
        return None
    if isinstance(cost, (int, float)):
        return int(cost)
    return None


def avg_cents_per_page(manifest: dict) -> float:
    completed = [
        j
        for j in manifest.get("jobs", {}).values()
        if j.get("status") == "complete"
        and isinstance(j.get("cost_cents"), (int, float))
        and isinstance(j.get("page_count"), int)
        and j.get("page_count")
    ]
    if not completed:
        return 1.0  # conservative pre-data guess
    return sum(j["cost_cents"] / j["page_count"] for j in completed) / len(completed)


def atomic_write(path: Path, data: bytes | str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    if isinstance(data, str):
        tmp.write_text(data)
    else:
        tmp.write_bytes(data)
    tmp.replace(path)


def load_manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"created_at": now_iso(), "jobs": {}}


def save_manifest(m: dict) -> None:
    m["updated_at"] = now_iso()
    atomic_write(MANIFEST, json.dumps(m, indent=2))


# ------------------------------------------------------------- submit + poll
def submit_convert(
    session: requests.Session,
    key: str,
    chapter: dict,
    *,
    mode: str = "accurate",
    output_format: str = "markdown",
    paginate: bool = True,
    save_checkpoint: bool = True,
) -> dict:
    """
    POST a multipart convert request. Returns parsed JSON submit response.
    Retries on 429/5xx with exponential backoff. Aborts on other 4xx.
    """
    page_range = chapter["page_range_param"]
    data = {
        "mode": mode,
        "output_format": output_format,
        "page_range": page_range,
        "paginate": "true" if paginate else "false",
        "save_checkpoint": "true" if save_checkpoint else "false",
    }
    headers = {"X-API-Key": key}
    audit(
        "submit_start",
        chapter_id=chapter["chapter_id"],
        page_range=page_range,
        mode=mode,
        output_format=output_format,
        paginate=paginate,
        save_checkpoint=save_checkpoint,
        key_fp=hash8(key),
    )

    attempt_429 = 0
    attempt_5xx = 0
    attempt_net = 0
    while True:
        # Reopen the file on every attempt — multipart reads it fresh each time
        with PDF.open("rb") as fp:
            files = {"file": (PDF.name, fp, "application/pdf")}
            try:
                r = session.post(
                    CONVERT_URL,
                    headers=headers,
                    data=data,
                    files=files,
                    timeout=UPLOAD_TIMEOUT_S,
                )
            except requests.RequestException as e:
                attempt_net += 1
                audit(
                    "submit_network_error",
                    error=str(e),
                    attempt=attempt_net,
                )
                if attempt_net > MAX_NET_RETRIES:
                    print(
                        f"[FAIL] submit network retry budget exhausted: {e}",
                        file=sys.stderr,
                    )
                    sys.exit(4)
                wait = min(2**attempt_net * 5, 60)
                print(
                    f"  [net-err] {type(e).__name__}: backoff {wait}s "
                    f"(attempt {attempt_net}/{MAX_NET_RETRIES})",
                    flush=True,
                )
                time.sleep(wait)
                continue

        audit("submit_response", http=r.status_code, body_bytes=len(r.content))

        if r.status_code == 200:
            try:
                return r.json()
            except ValueError:
                print(
                    f"[FAIL] submit returned non-JSON: {r.text[:300]}", file=sys.stderr
                )
                sys.exit(4)

        if r.status_code == 429:
            attempt_429 += 1
            if attempt_429 > MAX_429_RETRIES:
                print("[FAIL] 429 retry budget exhausted", file=sys.stderr)
                sys.exit(4)
            wait = min(2**attempt_429 * 5, 120)
            print(f"  [429] waiting {wait}s (attempt {attempt_429}/{MAX_429_RETRIES})")
            audit("submit_429_backoff", attempt=attempt_429, wait_s=wait)
            time.sleep(wait)
            continue

        if 500 <= r.status_code < 600:
            attempt_5xx += 1
            if attempt_5xx > MAX_5XX_RETRIES:
                print(
                    f"[FAIL] 5xx retry budget exhausted: last={r.status_code}",
                    file=sys.stderr,
                )
                sys.exit(4)
            wait = min(2**attempt_5xx, 60)
            print(
                f"  [{r.status_code}] waiting {wait}s (attempt {attempt_5xx}/{MAX_5XX_RETRIES})"
            )
            audit(
                "submit_5xx_backoff",
                http=r.status_code,
                attempt=attempt_5xx,
                wait_s=wait,
            )
            time.sleep(wait)
            continue

        # Any other 4xx — abort
        print(f"[FAIL] HTTP {r.status_code} on submit: {r.text[:500]}", file=sys.stderr)
        audit("submit_failed", http=r.status_code, body_head=r.text[:300])
        sys.exit(4)


def poll(session: requests.Session, key: str, check_url: str, request_id: str) -> dict:
    """
    Poll check_url every POLL_INTERVAL_S until terminal state or POLL_TIMEOUT_S.
    Returns the final parsed response dict. Exits on failure.
    """
    headers = {"X-API-Key": key}
    deadline = time.time() + POLL_TIMEOUT_S
    attempt_5xx = 0
    iters = 0
    while True:
        if time.time() > deadline:
            print(f"[FAIL] poll timeout after {POLL_TIMEOUT_S}s", file=sys.stderr)
            audit("poll_timeout", request_id=request_id)
            sys.exit(4)

        try:
            r = session.get(check_url, headers=headers, timeout=30)
        except requests.RequestException as e:
            print(f"  [poll network error] {e}", file=sys.stderr)
            audit("poll_network_error", error=str(e))
            time.sleep(POLL_INTERVAL_S)
            continue

        iters += 1
        if r.status_code == 200:
            try:
                body = r.json()
            except ValueError:
                print(f"[FAIL] poll non-JSON: {r.text[:300]}", file=sys.stderr)
                sys.exit(4)
            status = body.get("status")
            if iters % 15 == 1:  # print every ~30s
                elapsed = int(POLL_TIMEOUT_S - (deadline - time.time()))
                print(f"  [poll #{iters}] status={status} elapsed={elapsed}s")
            if status == "complete":
                audit("poll_complete", request_id=request_id, iters=iters)
                return body
            if status == "failed":
                print(
                    f"[FAIL] job failed: {body.get('error', 'unknown')}",
                    file=sys.stderr,
                )
                audit(
                    "poll_failed",
                    request_id=request_id,
                    body_head=json.dumps(body)[:300],
                )
                atomic_write(
                    OUT_DIR / f"error-{request_id}.json", json.dumps(body, indent=2)
                )
                sys.exit(4)
            time.sleep(POLL_INTERVAL_S)
            continue

        if 500 <= r.status_code < 600:
            attempt_5xx += 1
            if attempt_5xx > MAX_5XX_RETRIES:
                print(
                    f"[FAIL] poll 5xx budget exhausted: {r.status_code}",
                    file=sys.stderr,
                )
                sys.exit(4)
            wait = min(2**attempt_5xx, 30)
            audit("poll_5xx", http=r.status_code, attempt=attempt_5xx, wait_s=wait)
            time.sleep(wait)
            continue

        print(f"[FAIL] HTTP {r.status_code} on poll: {r.text[:300]}", file=sys.stderr)
        sys.exit(4)


# ---------------------------------------------------------- artifact writer
def save_artifacts(chapter: dict, result: dict) -> Path:
    """
    Persist response.json (metadata-only, no base64 images), chapter.md,
    metadata.json, and all extracted images. Return chapter dir.
    """
    cdir = CHAPTERS_DIR / chapter["chapter_id"]
    images_dir = cdir / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    # Save a stripped response (no markdown body, no image base64 blobs)
    stripped = {
        k: v
        for k, v in result.items()
        if k not in ("markdown", "images", "html", "json", "chunks")
    }
    atomic_write(cdir / "response.json", json.dumps(stripped, indent=2))

    markdown = result.get("markdown") or ""
    atomic_write(cdir / "chapter.md", markdown)

    metadata = {
        "chapter_id": chapter["chapter_id"],
        "chapter_title": chapter["title"],
        "part_num": chapter["part_num"],
        "chapter_num": chapter["num"],
        "page_range": chapter["page_range_param"],
        "expected_page_count": chapter["page_count"],
        "api_page_count": result.get("page_count"),
        "parse_quality_score": result.get("parse_quality_score"),
        "cost_breakdown": result.get("cost_breakdown"),
        "checkpoint_id": result.get("checkpoint_id"),
        "request_id": result.get("request_id"),
        "markdown_bytes": len(markdown.encode()),
        "markdown_sha256": hashlib.sha256(markdown.encode()).hexdigest(),
        "image_count": 0,
        "saved_at": now_iso(),
    }

    images = result.get("images") or {}
    for name, b64 in images.items():
        # Defensive filename sanitation
        safe_name = name.replace("/", "_").replace("..", "_")
        try:
            blob = base64.b64decode(b64)
        except Exception:
            print(f"  [warn] could not decode image {name}", file=sys.stderr)
            continue
        (images_dir / safe_name).write_bytes(blob)
        metadata["image_count"] += 1

    atomic_write(cdir / "metadata.json", json.dumps(metadata, indent=2))
    return cdir


# ------------------------------------------------------------------ pilot
def stage_pilot(chapter_id: str, dry_run: bool = False) -> int:
    key = load_key()
    ranges = load_ranges()
    chapter = find_chapter(ranges, chapter_id)

    print(f"[PILOT] chapter={chapter_id}")
    print(f"        title={chapter['title']}")
    print(
        f"        pages={chapter['page_range_param']}  ({chapter['page_count']} pages)"
    )
    print(
        f"        mode=accurate  format=markdown  paginate=true  save_checkpoint=true"
    )
    print()

    if dry_run:
        print("[DRY-RUN] would POST to:", CONVERT_URL)
        print("[DRY-RUN] headers: {'X-API-Key': '<redacted>'}  key_fp:", hash8(key))
        payload = {
            "mode": "accurate",
            "output_format": "markdown",
            "page_range": chapter["page_range_param"],
            "paginate": "true",
            "save_checkpoint": "true",
        }
        print("[DRY-RUN] multipart data fields:")
        for k, v in payload.items():
            print(f"           {k} = {v!r}")
        size_mb = PDF.stat().st_size / (1024 * 1024)
        print(f"[DRY-RUN] file: {PDF.name}  ({size_mb:.2f} MB)")
        print(f"[DRY-RUN] expected pages billed: {chapter['page_count']}")
        print(f"[DRY-RUN] would write to: {CHAPTERS_DIR / chapter['chapter_id']}")
        print()
        print("[DRY-RUN] NO network call made. Exit 0.")
        return 0

    session = requests.Session()
    t0 = time.time()
    print("[SUBMIT] uploading PDF (184 MB) + options...")
    submit = submit_convert(session, key, chapter)
    upload_s = time.time() - t0

    if not submit.get("success", False):
        print(f"[FAIL] submit returned success=false: {submit}", file=sys.stderr)
        audit("submit_success_false", body=submit)
        return 4

    request_id = submit.get("request_id", "")
    check_url = submit.get("request_check_url", "")
    if not request_id or not check_url:
        print(
            f"[FAIL] missing request_id or request_check_url: {submit}", file=sys.stderr
        )
        return 4
    print(f"[SUBMIT OK] request_id={request_id}  upload={upload_s:.1f}s")
    print(f"[POLL]  cadence={POLL_INTERVAL_S}s  timeout={POLL_TIMEOUT_S}s")

    t1 = time.time()
    result = poll(session, key, check_url, request_id)
    poll_s = time.time() - t1

    # Ensure fields land in the result even if API omits them
    result.setdefault("request_id", request_id)

    print(
        f"[COMPLETE] poll={poll_s:.1f}s  quality={result.get('parse_quality_score')}  "
        f"pages={result.get('page_count')}  cost={result.get('cost_breakdown')}"
    )

    cdir = save_artifacts(chapter, result)
    print(f"[SAVED] {cdir}")

    # Pilot report
    cost = result.get("cost_breakdown") or {}
    total_cents = extract_cost_cents(cost)

    pages_pilot = result.get("page_count") or chapter["page_count"]
    cents_per_page = (
        (total_cents / pages_pilot)
        if (total_cents is not None and pages_pilot)
        else None
    )
    TOTAL_CHAPTER_PAGES = 1551  # from page-ranges.json after bug fix
    est_full_cents = (
        (cents_per_page * TOTAL_CHAPTER_PAGES) if cents_per_page is not None else None
    )

    report_md = [
        f"# Pilot report — {chapter['chapter_id']}",
        "",
        f"- Chapter: {chapter['title']}",
        f"- Page range: {chapter['page_range_param']} ({chapter['page_count']} pages)",
        f"- Request ID: `{request_id}`",
        f"- Upload time: {upload_s:.1f}s",
        f"- Poll time: {poll_s:.1f}s",
        f"- API page_count: {result.get('page_count')}",
        f"- Parse quality score: {result.get('parse_quality_score')}",
        f"- Cost breakdown (raw): `{json.dumps(cost)}`",
        f"- Derived total cents: {total_cents}",
        f"- Cents/page: {cents_per_page}",
        f"- Extrapolated full-book cost ({TOTAL_CHAPTER_PAGES} ch pages): **{est_full_cents}** cents"
        + (f" ≈ ${est_full_cents / 100:.2f}" if est_full_cents is not None else ""),
        f"- Markdown bytes: {len((result.get('markdown') or '').encode())}",
        f"- Images extracted: {len(result.get('images') or {})}",
        "",
        "## Human review gate",
        "",
        "1. Open `rhoton-wiki/extractions/datalab/chapters/"
        + chapter["chapter_id"]
        + "/chapter.md` in Obsidian.",
        "2. Visually verify figure captions, tables, and anatomic labels are preserved.",
        "3. If the cost extrapolation is acceptable, append the exact line",
        "",
        "   `PILOT APPROVED`",
        "",
        "   to the end of this file. Stage 3 (run) refuses to start without it.",
        "",
    ]
    atomic_write(OUT_DIR / "pilot-report.md", "\n".join(report_md))

    # Update manifest
    m = load_manifest()
    m["jobs"][chapter["chapter_id"]] = {
        "status": "complete",
        "request_id": request_id,
        "submitted_at": datetime.fromtimestamp(t0, tz=timezone.utc).isoformat(
            timespec="seconds"
        ),
        "completed_at": now_iso(),
        "page_count": result.get("page_count"),
        "parse_quality_score": result.get("parse_quality_score"),
        "cost_cents": total_cents,
        "chapter_dir": str(cdir),
        "checkpoint_id": result.get("checkpoint_id"),
    }
    save_manifest(m)

    print()
    print(f"[PILOT DONE] report: {OUT_DIR / 'pilot-report.md'}")
    print(
        "Next: open the chapter.md in Obsidian, review, then append 'PILOT APPROVED' to pilot-report.md"
    )
    return 0


# ------------------------------------------------------------------ full run
PILOT_GATE_TOKEN = "PILOT APPROVED"


def process_chapter(
    session: requests.Session, key: str, chapter: dict, manifest: dict
) -> tuple[int | None, dict]:
    """
    Submit + poll + save + record manifest for a single chapter.
    Returns (cost_cents, result). Exits on hard failure (no auto-retry of 4xx).
    """
    t0 = time.time()
    submit = submit_convert(session, key, chapter)
    upload_s = time.time() - t0

    if not submit.get("success", False):
        print(
            f"[FAIL] submit returned success=false: {submit}",
            file=sys.stderr,
        )
        audit("submit_success_false", body=submit)
        sys.exit(4)

    request_id = submit.get("request_id", "")
    check_url = submit.get("request_check_url", "")
    if not request_id or not check_url:
        print(f"[FAIL] missing request_id/check_url: {submit}", file=sys.stderr)
        sys.exit(4)

    print(
        f"  submit_ok request_id={request_id} upload={upload_s:.1f}s",
        flush=True,
    )

    t1 = time.time()
    result = poll(session, key, check_url, request_id)
    result.setdefault("request_id", request_id)
    poll_s = time.time() - t1

    cdir = save_artifacts(chapter, result)
    total_cents = extract_cost_cents(result.get("cost_breakdown"))

    manifest["jobs"][chapter["chapter_id"]] = {
        "status": "complete",
        "request_id": request_id,
        "submitted_at": datetime.fromtimestamp(t0, tz=timezone.utc).isoformat(
            timespec="seconds"
        ),
        "completed_at": now_iso(),
        "page_count": result.get("page_count"),
        "parse_quality_score": result.get("parse_quality_score"),
        "cost_cents": total_cents,
        "cost_breakdown_raw": result.get("cost_breakdown"),
        "chapter_dir": str(cdir),
        "checkpoint_id": result.get("checkpoint_id"),
        "upload_seconds": round(upload_s, 1),
        "poll_seconds": round(poll_s, 1),
    }
    save_manifest(manifest)
    return total_cents, result


def stage_run(dry_run: bool = False, budget_cents: int | None = None) -> int:
    key = load_key()
    ranges = load_ranges()

    # Gate 1: PILOT APPROVED — require the token on a line of its own
    # (not inside the instructions block, which also contains the literal phrase).
    pr = OUT_DIR / "pilot-report.md"
    if not pr.exists():
        print(f"[FAIL] pilot-report.md missing at {pr}", file=sys.stderr)
        return 3
    approved = any(
        line.strip() == PILOT_GATE_TOKEN for line in pr.read_text().splitlines()
    )
    if not approved:
        print(
            f"[FAIL] pilot-report.md has no standalone '{PILOT_GATE_TOKEN}' line. "
            f"Review the pilot chapter.md and append the line exactly — "
            f"no backticks, no quotes, no other chars.",
            file=sys.stderr,
        )
        return 3

    # Gate 2: budget
    if budget_cents is None:
        env_b = os.environ.get("DATALAB_BUDGET_CENTS")
        if env_b is None:
            print(
                "[FAIL] pass --budget-cents N or set DATALAB_BUDGET_CENTS env var",
                file=sys.stderr,
            )
            return 3
        try:
            budget_cents = int(env_b)
        except ValueError:
            print(
                f"[FAIL] DATALAB_BUDGET_CENTS not an int: {env_b!r}",
                file=sys.stderr,
            )
            return 3
    if budget_cents <= 0:
        print(f"[FAIL] budget_cents must be > 0, got {budget_cents}", file=sys.stderr)
        return 3

    manifest = load_manifest()
    chapters = ordered_chapters(ranges)

    cumulative = sum(
        (j.get("cost_cents") or 0)
        for j in manifest.get("jobs", {}).values()
        if j.get("status") == "complete"
    )
    avg_cpp = avg_cents_per_page(manifest)

    print(f"[RUN] budget        = {budget_cents} c (${budget_cents / 100:.2f})")
    print(f"[RUN] already spent = {cumulative} c")
    print(f"[RUN] remaining     = {budget_cents - cumulative} c")
    print(
        f"[RUN] avg c/page    = {avg_cpp:.3f} (from {len(manifest.get('jobs', {}))} job(s))"
    )
    print(f"[RUN] chapters      = {len(chapters)}  dry_run={dry_run}")
    print()

    session = requests.Session()

    for chapter in chapters:
        cid = chapter["chapter_id"]
        existing = manifest.get("jobs", {}).get(cid, {})
        if existing.get("status") == "complete":
            print(
                f"[SKIP] {cid}  (manifest shows complete, cost={existing.get('cost_cents')} c)"
            )
            continue

        est = int(round(chapter["page_count"] * avg_cpp))
        projected = cumulative + est
        print(
            f"[NEXT] {cid}  range={chapter['page_range_param']}  pages={chapter['page_count']}  est={est} c  projected_total={projected} c / {budget_cents} c"
        )

        if projected > budget_cents:
            print(
                f"\n[BUDGET HALT] {cid} would push spend to {projected} c > cap {budget_cents} c",
                file=sys.stderr,
            )
            audit(
                "budget_halt",
                chapter_id=cid,
                cumulative=cumulative,
                est=est,
                projected=projected,
                budget=budget_cents,
            )
            return 2

        if dry_run:
            print(f"  [DRY-RUN] no submit")
            cumulative += est  # running total for report accuracy
            continue

        try:
            total_cents, result = process_chapter(session, key, chapter, manifest)
        except SystemExit:
            raise
        except Exception as e:
            print(f"[FAIL] {cid} unhandled exception: {e}", file=sys.stderr)
            audit("run_exception", chapter_id=cid, error=str(e))
            return 4

        cumulative += total_cents or 0
        avg_cpp = avg_cents_per_page(manifest)
        print(
            f"[OK]   {cid}  cost={total_cents} c  cumulative={cumulative} c / {budget_cents} c  new_avg_cpp={avg_cpp:.3f}"
        )
        print()

    print(f"[RUN DONE] spent {cumulative} c / budget {budget_cents} c")
    return 0


# --------------------------------------------------------------------- CLI
def main() -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="stage", required=True)

    pp = sub.add_parser("pilot", help="Stage 2 — extract one small chapter")
    pp.add_argument("--chapter", required=True, help="chapter_id from page-ranges.json")
    pp.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the payload and exit without calling the API",
    )

    rp = sub.add_parser("run", help="Stage 3 — full sequential run, budget-guarded")
    rp.add_argument(
        "--dry-run",
        action="store_true",
        help="List chapters, show projected costs, do not submit",
    )
    rp.add_argument(
        "--budget-cents",
        type=int,
        default=None,
        help="Hard spend cap in cents (overrides DATALAB_BUDGET_CENTS env)",
    )

    args = p.parse_args()
    if args.stage == "pilot":
        return stage_pilot(args.chapter, dry_run=args.dry_run)
    if args.stage == "run":
        return stage_run(dry_run=args.dry_run, budget_cents=args.budget_cents)
    return 2


if __name__ == "__main__":
    sys.exit(main())
