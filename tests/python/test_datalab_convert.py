"""Tests for pure helpers in rhoton-wiki/tools/datalab/datalab_convert.py.

Only deterministic, offline helpers are exercised — cost extraction, manifest
math, hashing, chapter lookup/ordering, atomic write. The submit/poll network
paths are intentionally out of scope.
"""

import hashlib

import pytest


# --------------------------------------------------------------------------- #
# hash8 / now_iso
# --------------------------------------------------------------------------- #


def test_hash8_matches_sha256_prefix(datalab_convert):
    assert datalab_convert.hash8("secret-key") == hashlib.sha256(
        b"secret-key"
    ).hexdigest()[:8]


def test_hash8_is_deterministic_and_length8(datalab_convert):
    h = datalab_convert.hash8("abc")
    assert len(h) == 8
    assert h == datalab_convert.hash8("abc")
    assert h != datalab_convert.hash8("abd")


def test_now_iso_is_utc_isoformat(datalab_convert):
    s = datalab_convert.now_iso()
    assert s.endswith("+00:00")
    # Round-trips through fromisoformat without raising.
    from datetime import datetime

    datetime.fromisoformat(s)


# --------------------------------------------------------------------------- #
# extract_cost_cents
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "cost, expected",
    [
        (None, None),
        ({}, None),
        ({"unrelated": 5}, None),
        ({"final_cost_cents": 13, "list_cost_cents": 17}, 13),  # prefers final
        ({"list_cost_cents": 17}, 17),
        ({"total_cost_cents": 8}, 8),
        ({"total_cents": 6}, 6),
        ({"cents": 4}, 4),
        ({"total": 9, "list_cost_cents": 17}, 9),  # "total" beats "list_cost_cents"
        (13, 13),  # bare int
        (13.9, 13),  # float truncated to int
        ({"final_cost_cents": 12.7}, 12),  # dict float truncated
    ],
)
def test_extract_cost_cents(datalab_convert, cost, expected):
    assert datalab_convert.extract_cost_cents(cost) == expected


# --------------------------------------------------------------------------- #
# avg_cents_per_page
# --------------------------------------------------------------------------- #


def test_avg_cents_per_page_empty_returns_one(datalab_convert):
    assert datalab_convert.avg_cents_per_page({}) == 1.0
    assert datalab_convert.avg_cents_per_page({"jobs": {}}) == 1.0


def test_avg_cents_per_page_single_job(datalab_convert):
    m = {"jobs": {"c1": {"status": "complete", "cost_cents": 20, "page_count": 10}}}
    assert datalab_convert.avg_cents_per_page(m) == 2.0


def test_avg_cents_per_page_averages_per_job(datalab_convert):
    m = {
        "jobs": {
            "c1": {"status": "complete", "cost_cents": 20, "page_count": 10},  # 2.0
            "c2": {"status": "complete", "cost_cents": 12, "page_count": 3},  # 4.0
        }
    }
    assert datalab_convert.avg_cents_per_page(m) == 3.0


def test_avg_cents_per_page_skips_incomplete_and_zero_pages(datalab_convert):
    m = {
        "jobs": {
            "done": {"status": "complete", "cost_cents": 20, "page_count": 10},
            "pending": {"status": "submitted", "cost_cents": 99, "page_count": 1},
            "zero": {"status": "complete", "cost_cents": 5, "page_count": 0},
            "nocost": {"status": "complete", "page_count": 4},
        }
    }
    # Only the "done" job counts.
    assert datalab_convert.avg_cents_per_page(m) == 2.0


# --------------------------------------------------------------------------- #
# manifest_key_for
# --------------------------------------------------------------------------- #


def test_manifest_key_for_markdown(datalab_convert):
    assert datalab_convert.manifest_key_for("markdown") == "jobs"


def test_manifest_key_for_json(datalab_convert):
    assert datalab_convert.manifest_key_for("json") == "jobs_json"


def test_manifest_key_for_unsupported_exits(datalab_convert):
    with pytest.raises(SystemExit):
        datalab_convert.manifest_key_for("html")


# --------------------------------------------------------------------------- #
# find_chapter / ordered_chapters
# --------------------------------------------------------------------------- #


@pytest.fixture
def ranges():
    return {
        "parts": [
            {
                "part_num": 2,
                "chapters": [
                    {"chapter_id": "p2c01-a", "num": 1, "title": "A"},
                    {"chapter_id": "p2c02-b", "num": 2, "title": "B"},
                ],
            },
            {
                "part_num": 3,
                "chapters": [
                    {"chapter_id": "p3c10-c", "num": 10, "title": "C"},
                ],
            },
        ]
    }


def test_find_chapter_returns_with_part_num(datalab_convert, ranges):
    ch = datalab_convert.find_chapter(ranges, "p2c02-b")
    assert ch["chapter_id"] == "p2c02-b"
    assert ch["part_num"] == 2
    assert ch["title"] == "B"


def test_find_chapter_missing_exits(datalab_convert, ranges):
    with pytest.raises(SystemExit):
        datalab_convert.find_chapter(ranges, "nope")


def test_ordered_chapters_flattens_in_order(datalab_convert, ranges):
    out = datalab_convert.ordered_chapters(ranges)
    assert [c["chapter_id"] for c in out] == ["p2c01-a", "p2c02-b", "p3c10-c"]
    assert [c["part_num"] for c in out] == [2, 2, 3]


# --------------------------------------------------------------------------- #
# atomic_write
# --------------------------------------------------------------------------- #


def test_atomic_write_str(datalab_convert, tmp_path):
    target = tmp_path / "a" / "f.txt"
    datalab_convert.atomic_write(target, "hello")
    assert target.read_text() == "hello"
    assert not (tmp_path / "a" / "f.txt.tmp").exists()


def test_atomic_write_bytes(datalab_convert, tmp_path):
    target = tmp_path / "f.bin"
    datalab_convert.atomic_write(target, b"\x00\x01\x02")
    assert target.read_bytes() == b"\x00\x01\x02"


def test_manifest_and_subdir_constants(datalab_convert):
    assert datalab_convert.MANIFEST_KEYS == {"markdown": "jobs", "json": "jobs_json"}
    assert datalab_convert.SUBDIRS == {"markdown": "", "json": "json-pass"}
