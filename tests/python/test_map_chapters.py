"""Tests for rhoton-wiki/tools/datalab-augment/map_chapters.py.

Focus: chapter-number extraction (lists, ranges, en-dashes, false positives),
legacy->canonical mapping, slugify, sources_field, and the CITATION_RE surface.
"""

import pytest


# --------------------------------------------------------------------------- #
# extract_chapter_numbers
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "text, expected",
    [
        ("4", ([4], True)),
        ("2,3,5", ([2, 3, 5], True)),
        ("2, 3, 5", ([2, 3, 5], True)),  # spaces tolerated
        ("2-5", ([2, 3, 4, 5], True)),
        ("2 - 5", ([2, 3, 4, 5], True)),  # spaces around hyphen
        ("14-15", ([14, 15], True)),
        ("1,3-5,9", ([1, 3, 4, 5, 9], True)),
        ("2–5", ([2, 3, 4, 5], True)),  # en-dash normalised to hyphen
        ("", ([], True)),  # empty parses cleanly to no numbers
    ],
)
def test_extract_chapter_numbers_ok(map_chapters, text, expected):
    assert map_chapters.extract_chapter_numbers(text) == expected


@pytest.mark.parametrize(
    "text",
    [
        "5-2",  # reversed range → failure
        "abc",  # non-numeric
        "4,foo",  # one bad token poisons the whole citation
        "2-",  # incomplete range → ValueError on int("")
        "1-2-3",  # split("-", 1) → "1","2-3" → int("2-3") fails
    ],
)
def test_extract_chapter_numbers_failure(map_chapters, text):
    nums, ok = map_chapters.extract_chapter_numbers(text)
    assert ok is False
    assert nums == []


# --------------------------------------------------------------------------- #
# map_chapter_numbers
# --------------------------------------------------------------------------- #


def test_map_chapter_numbers_basic(map_chapters):
    canonical, unmapped = map_chapters.map_chapter_numbers([1, 2])
    assert canonical == ["p2c01-the-cerebrum", "p2c02-the-supratentorial-arteries"]
    assert unmapped == []


def test_map_chapter_numbers_dedupes(map_chapters):
    canonical, unmapped = map_chapters.map_chapter_numbers([1, 1, 1])
    assert canonical == ["p2c01-the-cerebrum"]
    assert unmapped == []


def test_map_chapter_numbers_out_of_range(map_chapters):
    canonical, unmapped = map_chapters.map_chapter_numbers([16, 99])
    assert canonical == []
    assert unmapped == [16, 99]


def test_map_chapter_numbers_partial(map_chapters):
    canonical, unmapped = map_chapters.map_chapter_numbers([1, 16])
    assert canonical == ["p2c01-the-cerebrum"]
    assert unmapped == [16]


def test_legacy_map_ch10_maps_to_part3(map_chapters):
    canonical, unmapped = map_chapters.map_chapter_numbers([10])
    assert canonical == ["p3c10-the-posterior-fossa-cisterns"]
    assert unmapped == []


# --------------------------------------------------------------------------- #
# CITATION_RE surface
# --------------------------------------------------------------------------- #


def test_citation_re_matches_dot_forms(map_chapters):
    text = "See Ch. 4 and Ch.5-6 for detail"
    groups = [m.group(1).strip() for m in map_chapters.CITATION_RE.finditer(text)]
    assert groups == ["4", "5-6"]


def test_citation_re_ignores_word_chapters(map_chapters):
    # "Chapters 2-5" has no literal "Ch." so it is never captured.
    assert not map_chapters.CITATION_RE.findall("Chapters 2-5 discuss this")


def test_citation_re_requires_a_digit(map_chapters):
    assert not map_chapters.CITATION_RE.findall("Ch. and other notes")


def test_citation_pipeline_multiple_hits(map_chapters):
    citation = "Ch.1, Ch.10"
    all_nums = []
    for m in map_chapters.CITATION_RE.finditer(citation):
        nums, ok = map_chapters.extract_chapter_numbers(m.group(1))
        assert ok
        all_nums.extend(nums)
    assert all_nums == [1, 10]


# --------------------------------------------------------------------------- #
# slugify
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "text, expected",
    [
        ("The Cerebrum", "the-cerebrum"),
        ("A1 Segment!", "a1-segment"),
        ("  Multiple   Spaces  ", "multiple-spaces"),
        ("---leading-trailing---", "leading-trailing"),
        ("Cavernous/Sinus (region)", "cavernous-sinus-region"),
        ("café", "caf"),  # non-ascii chars are dropped, not transliterated
    ],
)
def test_slugify(map_chapters, text, expected):
    assert map_chapters.slugify(text) == expected


# --------------------------------------------------------------------------- #
# sources_field
# --------------------------------------------------------------------------- #


def test_sources_field_missing(map_chapters):
    assert map_chapters.sources_field({}) == []


def test_sources_field_none(map_chapters):
    assert map_chapters.sources_field({"sources": None}) == []


def test_sources_field_list(map_chapters):
    assert map_chapters.sources_field({"sources": ["Ch.1", "Ch.2"]}) == ["Ch.1", "Ch.2"]


def test_sources_field_scalar_wrapped(map_chapters):
    assert map_chapters.sources_field({"sources": "Ch.4"}) == ["Ch.4"]


def test_sources_field_non_string_coerced(map_chapters):
    assert map_chapters.sources_field({"sources": 5}) == ["5"]
