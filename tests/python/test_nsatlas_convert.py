"""Tests for pure helpers in nsatlas-wiki/tools/datalab/nsatlas_convert.py.

The NSAtlas client shares most helper shapes with the Rhoton client but keys
work off an ``articles`` inventory rather than ``parts``/``chapters``. Network
paths are out of scope.
"""

import pytest


@pytest.mark.parametrize(
    "cost, expected",
    [
        (None, None),
        ({}, None),
        ({"final_cost_cents": 13, "list_cost_cents": 17}, 13),
        ({"list_cost_cents": 17}, 17),
        (7, 7),
        (7.9, 7),
    ],
)
def test_extract_cost_cents(nsatlas_convert, cost, expected):
    assert nsatlas_convert.extract_cost_cents(cost) == expected


def test_avg_cents_per_page_empty(nsatlas_convert):
    assert nsatlas_convert.avg_cents_per_page({}) == 1.0


def test_avg_cents_per_page_averages(nsatlas_convert):
    m = {
        "jobs": {
            "a": {"status": "complete", "cost_cents": 30, "page_count": 10},  # 3.0
            "b": {"status": "complete", "cost_cents": 10, "page_count": 10},  # 1.0
        }
    }
    assert nsatlas_convert.avg_cents_per_page(m) == 2.0


def test_manifest_key_for(nsatlas_convert):
    assert nsatlas_convert.manifest_key_for("markdown") == "jobs"
    assert nsatlas_convert.manifest_key_for("json") == "jobs_json"


def test_manifest_key_for_unsupported_exits(nsatlas_convert):
    with pytest.raises(SystemExit):
        nsatlas_convert.manifest_key_for("csv")


@pytest.fixture
def inventory_data():
    return {
        "articles": [
            {"article_id": "cat--first", "title": "First"},
            {"article_id": "cat--second", "title": "Second"},
        ]
    }


def test_find_article_found(nsatlas_convert, inventory_data):
    a = nsatlas_convert.find_article(inventory_data, "cat--second")
    assert a["title"] == "Second"


def test_find_article_missing_exits(nsatlas_convert, inventory_data):
    with pytest.raises(SystemExit):
        nsatlas_convert.find_article(inventory_data, "cat--missing")


def test_ordered_articles_preserves_order(nsatlas_convert, inventory_data):
    out = nsatlas_convert.ordered_articles(inventory_data)
    assert [a["article_id"] for a in out] == ["cat--first", "cat--second"]


def test_hash8_length(nsatlas_convert):
    assert len(nsatlas_convert.hash8("x")) == 8


def test_atomic_write_roundtrip(nsatlas_convert, tmp_path):
    target = tmp_path / "sub" / "f.txt"
    nsatlas_convert.atomic_write(target, "data")
    assert target.read_text() == "data"
    assert not (tmp_path / "sub" / "f.txt.tmp").exists()
