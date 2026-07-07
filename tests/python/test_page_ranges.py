"""Tests for rhoton-wiki/tools/datalab/page_ranges.py.

Covers slugify (with the 60-char truncation) and the outline ``flatten``
generator. ``flatten`` does an ``isinstance(item, Destination)`` check against
the module-level ``Destination`` symbol, so we monkeypatch that symbol with a
lightweight stub class and feed stub instances — this exercises the recursion,
depth tracking, and unknown-node handling without pypdf internals.
"""

import pytest


# --------------------------------------------------------------------------- #
# slugify
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "text, expected",
    [
        ("1. The Cerebrum", "1-the-cerebrum"),
        ("The Supratentorial Arteries", "the-supratentorial-arteries"),
        ("  Padded  Title  ", "padded-title"),
        ("Cavernous/Sinus & Plexus", "cavernous-sinus-plexus"),
    ],
)
def test_slugify(page_ranges, text, expected):
    assert page_ranges.slugify(text) == expected


def test_slugify_truncates_to_60_chars(page_ranges):
    long_title = "a" * 100
    out = page_ranges.slugify(long_title)
    assert len(out) == 60
    assert out == "a" * 60


def test_slugify_truncates_after_slugifying(page_ranges):
    # Slugification happens before the [:60] slice.
    title = "word " * 30  # 150 chars -> "word-word-...", then cut to 60
    out = page_ranges.slugify(title)
    assert len(out) == 60


# --------------------------------------------------------------------------- #
# flatten
# --------------------------------------------------------------------------- #


class _StubDest:
    """Stands in for pypdf's Destination for isinstance checks in flatten."""

    def __init__(self, title):
        self.title = title


@pytest.fixture
def patched_flatten(page_ranges, monkeypatch):
    monkeypatch.setattr(page_ranges, "Destination", _StubDest)
    return page_ranges.flatten


def test_flatten_flat_list(patched_flatten):
    d1, d2 = _StubDest("Part 1"), _StubDest("1. The Cerebrum")
    out = list(patched_flatten([d1, d2]))
    assert out == [(0, "Part 1", d1), (0, "1. The Cerebrum", d2)]


def test_flatten_nested_children_increment_depth(patched_flatten):
    parent = _StubDest("Part 1")
    child = _StubDest("1. The Cerebrum")
    grandchild = _StubDest("Anterior Cerebral Artery")
    outline = [parent, [child, [grandchild]]]
    out = list(patched_flatten(outline))
    assert out == [
        (0, "Part 1", parent),
        (1, "1. The Cerebrum", child),
        (2, "Anterior Cerebral Artery", grandchild),
    ]


def test_flatten_unknown_node_yields_none_dest(patched_flatten):
    # A non-list, non-Destination node yields a typed placeholder + None dest.
    out = list(patched_flatten([42]))
    assert out == [(0, "<int>", None)]


def test_flatten_mixed_known_and_unknown(patched_flatten):
    d = _StubDest("Part 1")
    out = list(patched_flatten([d, "some-string"]))
    assert out == [(0, "Part 1", d), (0, "<str>", None)]


def test_flatten_empty(patched_flatten):
    assert list(patched_flatten([])) == []
