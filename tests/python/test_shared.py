"""Tests for rhoton-wiki/tools/datalab-augment/_shared.py.

Characterizes the tiny regex-YAML frontmatter parser, atomic JSON writer, and
HTML-to-text helper. Behaviour is pinned exactly, including quirks (e.g. inline
``[a, b]`` lists are NOT parsed as lists — only ``-`` block lists are).
"""

import json

import pytest


# --------------------------------------------------------------------------- #
# _strip_yaml_value
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "raw, expected",
    [
        ('"quoted"', "quoted"),
        ("'quoted'", "quoted"),
        ("bare", "bare"),
        ("  padded  ", "padded"),
        ('"mismatch\'', "\"mismatch'"),  # non-matching quotes left intact
        ('"', '"'),  # single char, too short to be a quoted pair
        ('""', ""),  # empty quoted string
        ("", ""),
    ],
)
def test_strip_yaml_value(shared, raw, expected):
    assert shared._strip_yaml_value(raw) == expected


# --------------------------------------------------------------------------- #
# _flat_yaml_fields / parse_frontmatter
# --------------------------------------------------------------------------- #


def _fm(body: str) -> str:
    """Wrap a YAML body in frontmatter delimiters with the required trailing NL."""
    return f"---\n{body}\n---\n"


def test_scalar_field(shared):
    fields = shared.parse_frontmatter(_fm("title: The Cerebrum"))
    assert fields == {"title": "The Cerebrum"}


def test_quoted_scalar_value(shared):
    fields = shared.parse_frontmatter(_fm('title: "Ch. 4 notes"'))
    assert fields == {"title": "Ch. 4 notes"}


def test_block_list_tags(shared):
    body = "tags:\n  - anatomy\n  - artery\ntitle: Foo"
    fields = shared.parse_frontmatter(_fm(body))
    assert fields == {"tags": ["anatomy", "artery"], "title": "Foo"}


def test_block_list_at_end_of_block(shared):
    body = "title: Foo\ntags:\n  - a\n  - b"
    fields = shared.parse_frontmatter(_fm(body))
    assert fields == {"title": "Foo", "tags": ["a", "b"]}


def test_inline_list_is_kept_as_string_not_parsed(shared):
    # The parser has no bracket handling — inline lists stay raw scalars.
    fields = shared.parse_frontmatter(_fm("tags: [a, b, c]"))
    assert fields == {"tags": "[a, b, c]"}


def test_quoted_values_inside_block_list(shared):
    body = 'aliases:\n  - "ACA"\n  - \'A1\''
    fields = shared.parse_frontmatter(_fm(body))
    assert fields == {"aliases": ["ACA", "A1"]}


def test_bare_dash_marker_is_skipped_in_list(shared):
    body = "tags:\n  -\n  - real"
    fields = shared.parse_frontmatter(_fm(body))
    assert fields == {"tags": ["real"]}


def test_missing_closing_delimiter_returns_none(shared):
    content = "---\ntitle: Foo\nno closing fence here\n"
    assert shared.parse_frontmatter(content) is None


def test_empty_string_returns_none(shared):
    assert shared.parse_frontmatter("") is None


def test_no_frontmatter_returns_none(shared):
    assert shared.parse_frontmatter("# Just a heading\n\nbody text") is None


def test_empty_frontmatter_block(shared):
    # ``---\n\n---\n`` — the regex needs a newline between the fences.
    fields = shared.parse_frontmatter("---\n\n---\n")
    assert fields == {}


def test_empty_scalar_without_following_list_stays_open(shared):
    # A trailing ``key:`` with nothing after produces an empty list value.
    fields = shared.parse_frontmatter(_fm("title: Foo\nsources:"))
    assert fields == {"title": "Foo", "sources": []}


# --------------------------------------------------------------------------- #
# atomic_write_json
# --------------------------------------------------------------------------- #


def test_atomic_write_json_roundtrip(shared, tmp_path):
    target = tmp_path / "out.json"
    data = {"b": 2, "a": 1}
    shared.atomic_write_json(target, data)
    assert json.loads(target.read_text()) == data


def test_atomic_write_json_sorted_keys_and_trailing_newline(shared, tmp_path):
    target = tmp_path / "out.json"
    shared.atomic_write_json(target, {"b": 2, "a": 1})
    text = target.read_text()
    assert text.endswith("\n")
    # sort_keys=True → "a" appears before "b"
    assert text.index('"a"') < text.index('"b"')


def test_atomic_write_json_creates_parent_dirs(shared, tmp_path):
    target = tmp_path / "nested" / "deep" / "out.json"
    shared.atomic_write_json(target, [1, 2, 3])
    assert target.exists()
    assert json.loads(target.read_text()) == [1, 2, 3]


def test_atomic_write_json_leaves_no_tmp_file(shared, tmp_path):
    target = tmp_path / "out.json"
    shared.atomic_write_json(target, {"x": 1})
    assert not (tmp_path / "out.json.tmp").exists()
    assert list(tmp_path.iterdir()) == [target]


# --------------------------------------------------------------------------- #
# html_to_text
# --------------------------------------------------------------------------- #


def test_html_to_text_none_and_empty(shared):
    assert shared.html_to_text(None) == ""
    assert shared.html_to_text("") == ""


def test_html_to_text_strips_tags(shared):
    assert shared.html_to_text("<p>Hello <b>world</b></p>") == "Hello world"


def test_html_to_text_collapses_whitespace(shared):
    assert shared.html_to_text("<p>a\n\n   b\t c</p>") == "a b c"


def test_html_to_text_harvests_img_alt(shared):
    html = '<div><img alt="anterior cerebral artery" src="x.jpg"></div>'
    assert shared.html_to_text(html) == "anterior cerebral artery"


def test_html_to_text_harvests_self_closing_img_alt(shared):
    html = '<img alt="cavernous sinus"/>'
    assert shared.html_to_text(html) == "cavernous sinus"


def test_html_to_text_img_without_alt_yields_nothing(shared):
    assert shared.html_to_text('<img src="x.jpg">') == ""


def test_html_to_text_alt_plus_text_combined(shared):
    html = '<img alt="label"> caption body'
    assert shared.html_to_text(html) == "label caption body"
