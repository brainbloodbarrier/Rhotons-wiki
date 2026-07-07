"""Tests for nsatlas-wiki/tools/datalab/cleanup_images.py.

Covers the pure helpers: content hashing, junk identification (size + repeated
content thresholds), and the markdown cleaner that strips junk image refs and
their trailing alt-text echoes.
"""

import hashlib


# --------------------------------------------------------------------------- #
# sha256_file
# --------------------------------------------------------------------------- #


def test_sha256_file(cleanup_images, tmp_path):
    f = tmp_path / "x.bin"
    f.write_bytes(b"hello world")
    assert cleanup_images.sha256_file(f) == hashlib.sha256(b"hello world").hexdigest()


# --------------------------------------------------------------------------- #
# identify_junk
# --------------------------------------------------------------------------- #


def _make_image(chapters_dir, article_id, name, content: bytes):
    images = chapters_dir / article_id / "images"
    images.mkdir(parents=True, exist_ok=True)
    (images / name).write_bytes(content)


def test_identify_junk_small_files(cleanup_images, tmp_path):
    # A sub-1KB file is always junk; a large unique file is kept.
    _make_image(tmp_path, "art1", "tiny.jpg", b"x" * 500)
    _make_image(tmp_path, "art1", "big.jpg", b"y" * 2000)
    junk = cleanup_images.identify_junk(tmp_path)
    assert "tiny.jpg" in junk["art1"]
    assert junk["art1"]["tiny.jpg"].startswith("< 1KB")
    assert "big.jpg" not in junk.get("art1", {})


def test_identify_junk_repeated_content_across_5_articles(cleanup_images, tmp_path):
    logo = b"z" * 4000  # large enough to dodge the size rule
    for i in range(5):
        _make_image(tmp_path, f"art{i}", "logo.jpg", logo)
    junk = cleanup_images.identify_junk(tmp_path)
    # Present in 5 articles → flagged as repeated branding in every article.
    for i in range(5):
        assert "logo.jpg" in junk[f"art{i}"]
        assert "repeated content in 5 articles" in junk[f"art{i}"]["logo.jpg"]


def test_identify_junk_repeated_below_threshold_kept(cleanup_images, tmp_path):
    logo = b"z" * 4000
    for i in range(4):  # only 4 articles → below FREQ_THRESHOLD of 5
        _make_image(tmp_path, f"art{i}", "logo.jpg", logo)
    junk = cleanup_images.identify_junk(tmp_path)
    assert junk == {}


def test_identify_junk_empty_dir(cleanup_images, tmp_path):
    assert cleanup_images.identify_junk(tmp_path) == {}


# --------------------------------------------------------------------------- #
# clean_markdown
# --------------------------------------------------------------------------- #


def test_clean_markdown_removes_junk_image_and_alt_echoes(cleanup_images):
    text = (
        "Intro paragraph.\n"
        "\n"
        "![logo](logo.jpg)\n"
        "\n"
        "logo alt echo\n"
        "\n"
        "## Real Heading\n"
        "\n"
        "Body content.\n"
    )
    out = cleanup_images.clean_markdown(text, {"logo.jpg"})
    assert "logo.jpg" not in out
    assert "logo alt echo" not in out
    assert "## Real Heading" in out
    assert "Body content." in out


def test_clean_markdown_keeps_non_junk_image(cleanup_images):
    text = "![keep](keep.jpg)\n\nsome caption\n"
    out = cleanup_images.clean_markdown(text, {"logo.jpg"})
    assert "![keep](keep.jpg)" in out


def test_clean_markdown_stops_at_figure_marker(cleanup_images):
    text = "![logo](logo.jpg)\n\n**Figure 1: real caption**\n"
    out = cleanup_images.clean_markdown(text, {"logo.jpg"})
    # The junk image line is gone but the Figure caption is preserved.
    assert "logo.jpg" not in out
    assert "**Figure 1: real caption**" in out


def test_clean_markdown_collapses_blank_runs(cleanup_images):
    text = "a\n\n\n\n\nb\n"
    out = cleanup_images.clean_markdown(text, set())
    # A run of 5 blank lines collapses to 2 blank lines (three newlines).
    assert out == "a\n\n\nb\n"
    # No run of 4+ newlines (i.e. never more than 2 consecutive blank lines).
    assert "\n\n\n\n" not in out
