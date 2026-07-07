"""Tests for rhoton-wiki/tools/datalab-augment/attribute_figures.py.

Covers the deterministic pieces: tokenizer, bbox center helper, and the
``process_chapter`` attribution flow driven with small synthetic json-pass
trees written to a temp CHAPTERS_ROOT (no network, no real vault).
"""

import json

import pytest


# --------------------------------------------------------------------------- #
# tokenize
# --------------------------------------------------------------------------- #


def test_tokenize_lowercases_and_splits(attribute_figures):
    assert attribute_figures.tokenize("Anterior Cerebral Artery") == {
        "anterior",
        "cerebral",
        "artery",
    }


def test_tokenize_drops_stopwords(attribute_figures):
    # "the" and "of" are stopwords and removed.
    assert attribute_figures.tokenize("The Segment of ACA") == {"segment", "aca"}


def test_tokenize_drops_single_char_tokens(attribute_figures):
    # "A" and standalone "3" are length<=1 → dropped; "a1" (length 2) kept.
    assert attribute_figures.tokenize("A1 segment 3") == {"a1", "segment"}


def test_tokenize_empty_and_punctuation(attribute_figures):
    assert attribute_figures.tokenize("") == set()
    assert attribute_figures.tokenize("--- , .") == set()


# --------------------------------------------------------------------------- #
# _bbox_center_y
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "bbox, expected",
    [
        ([0, 0, 10, 20], 10.0),
        ([0, 2, 3, 4], 3.0),
        (None, None),
        ([], None),
        ([1, 2], None),  # too short
    ],
)
def test_bbox_center_y(attribute_figures, bbox, expected):
    assert attribute_figures._bbox_center_y(bbox) == expected


# --------------------------------------------------------------------------- #
# process_chapter
# --------------------------------------------------------------------------- #


def _vault_page(attribute_figures, path, title):
    toks = attribute_figures.tokenize(title)
    return {
        "path": path,
        "title": title,
        "aliases": [],
        "tokens": toks,
        "title_tokens": toks,
    }


def _write_chapter_json(attribute_figures, tmp_path, chapter_id, data):
    """Write a synthetic json-pass/chapter.json and point CHAPTERS_ROOT at tmp."""
    jp = tmp_path / chapter_id / "json-pass"
    jp.mkdir(parents=True)
    (jp / "chapter.json").write_text(json.dumps(data))


def test_process_chapter_high_confidence_match(attribute_figures, tmp_path, monkeypatch):
    monkeypatch.setattr(attribute_figures, "CHAPTERS_ROOT", tmp_path)
    chapter_id = "p2c02-the-supratentorial-arteries"
    data = {
        "children": [
            {
                "id": "page0",
                "page": 0,
                "children": [
                    {
                        "id": "h1",
                        "block_type": "SectionHeader",
                        "page": 0,
                        "bbox": [0, 0, 10, 5],
                        "html": "<p>ANTERIOR CEREBRAL ARTERY</p>",
                    },
                    {
                        "id": "fig1",
                        "block_type": "Picture",
                        "page": 0,
                        "bbox": [0, 10, 10, 30],
                        "images": {"fig1_img.jpg": "b64data"},
                        "html": '<img alt="anterior cerebral artery">',
                        "section_hierarchy": {"1": "h1"},
                    },
                    {
                        "id": "cap1",
                        "block_type": "Caption",
                        "page": 0,
                        "bbox": [0, 31, 10, 35],
                        "html": "<p>Figure 2-1. The anterior cerebral artery.</p>",
                    },
                ],
            }
        ]
    }
    _write_chapter_json(attribute_figures, tmp_path, chapter_id, data)
    vault_pages = [
        _vault_page(attribute_figures, "entities/aca.md", "Anterior Cerebral Artery"),
        _vault_page(attribute_figures, "entities/vein.md", "Basal Vein of Rosenthal"),
    ]
    attributions = {}
    seen, attributed, excluded = attribute_figures.process_chapter(
        chapter_id, "The Supratentorial Arteries", vault_pages, attributions
    )
    assert seen == 1
    assert attributed == 1
    assert excluded == 0
    rec = attributions["fig1_img.jpg"]
    assert rec["assigned"] == "entities/aca.md"
    assert rec["confidence"] == "high"
    assert rec["candidates"][0]["score"] == 1.0
    assert rec["chapter_id"] == chapter_id
    assert rec["section_header"] == "ANTERIOR CEREBRAL ARTERY"
    # displayed caption merges own_text (img alt) with the nearest caption.
    assert "anterior cerebral artery" in rec["caption"]
    assert "Figure 2-1" in rec["caption"]


def test_process_chapter_unattributed_when_no_overlap(
    attribute_figures, tmp_path, monkeypatch
):
    monkeypatch.setattr(attribute_figures, "CHAPTERS_ROOT", tmp_path)
    chapter_id = "p2c02-the-supratentorial-arteries"
    data = {
        "children": [
            {
                "id": "page0",
                "page": 0,
                "children": [
                    {
                        "id": "h1",
                        "block_type": "SectionHeader",
                        "page": 0,
                        "bbox": [0, 0, 10, 5],
                        "html": "<p>ANTERIOR CEREBRAL ARTERY</p>",
                    },
                    {
                        "id": "fig1",
                        "block_type": "Picture",
                        "page": 0,
                        "bbox": [0, 10, 10, 30],
                        "images": {"fig1_img.jpg": "b64"},
                        "html": "",
                        "section_hierarchy": {"1": "h1"},
                    },
                ],
            }
        ]
    }
    _write_chapter_json(attribute_figures, tmp_path, chapter_id, data)
    # Vault page shares no tokens with "anterior cerebral artery".
    vault_pages = [
        _vault_page(attribute_figures, "entities/orbit.md", "Optic Foramen Boundaries")
    ]
    attributions = {}
    seen, attributed, excluded = attribute_figures.process_chapter(
        chapter_id, "The Supratentorial Arteries", vault_pages, attributions
    )
    assert seen == 1
    assert attributed == 0
    rec = attributions["fig1_img.jpg"]
    assert rec["assigned"] is None
    assert rec["confidence"] == "unattributed"
    assert rec["candidates"] == []


def test_process_chapter_excludes_inference_failed(
    attribute_figures, tmp_path, monkeypatch
):
    monkeypatch.setattr(attribute_figures, "CHAPTERS_ROOT", tmp_path)
    chapter_id = "p2c02-the-supratentorial-arteries"
    data = {
        "children": [
            {
                "id": "page0",
                "page": 0,
                "children": [
                    {
                        "id": "fig1",
                        "block_type": "Picture",
                        "page": 0,
                        "bbox": [0, 10, 10, 30],
                        "images": {"bad.jpg": "b64"},
                        "html": '<img alt="anterior cerebral artery">',
                        "inference_failed": True,
                    },
                ],
            }
        ]
    }
    _write_chapter_json(attribute_figures, tmp_path, chapter_id, data)
    vault_pages = [
        _vault_page(attribute_figures, "entities/aca.md", "Anterior Cerebral Artery")
    ]
    attributions = {}
    seen, attributed, excluded = attribute_figures.process_chapter(
        chapter_id, "Arteries", vault_pages, attributions
    )
    assert seen == 0
    assert attributed == 0
    assert excluded == 1
    assert attributions == {}


def test_process_chapter_skips_blocks_without_images(
    attribute_figures, tmp_path, monkeypatch
):
    monkeypatch.setattr(attribute_figures, "CHAPTERS_ROOT", tmp_path)
    chapter_id = "p2c01-the-cerebrum"
    data = {
        "children": [
            {
                "id": "page0",
                "page": 0,
                "children": [
                    {
                        "id": "t1",
                        "block_type": "Text",
                        "page": 0,
                        "html": "<p>Just prose, no images.</p>",
                    }
                ],
            }
        ]
    }
    _write_chapter_json(attribute_figures, tmp_path, chapter_id, data)
    attributions = {}
    seen, attributed, excluded = attribute_figures.process_chapter(
        chapter_id, "The Cerebrum", [], attributions
    )
    assert (seen, attributed, excluded) == (0, 0, 0)
    assert attributions == {}


def test_process_chapter_missing_json_returns_zeros(
    attribute_figures, tmp_path, monkeypatch
):
    monkeypatch.setattr(attribute_figures, "CHAPTERS_ROOT", tmp_path)
    attributions = {}
    result = attribute_figures.process_chapter(
        "does-not-exist", "Nope", [], attributions
    )
    assert result == (0, 0, 0)
    assert attributions == {}
