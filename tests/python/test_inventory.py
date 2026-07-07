"""Tests for the pure helper in nsatlas-wiki/tools/datalab/nsatlas_inventory.py.

Only ``slug_to_title`` is deterministic and offline; ``main`` needs pypdf and a
sources directory, so it is not exercised here.
"""

import pytest


@pytest.mark.parametrize(
    "slug, expected",
    [
        ("occipital-craniotomy", "Occipital Craniotomy"),
        ("3d-avm-resection", "3D AVM Resection"),  # 3d and avm are abbrevs
        ("ct-guided-biopsy", "CT Guided Biopsy"),
        ("csf-leak", "CSF Leak"),
        ("cranial", "Cranial"),  # single word
        ("mri-and-ct", "MRI And CT"),  # mixed abbrevs preserve order
    ],
)
def test_slug_to_title(inventory, slug, expected):
    assert inventory.slug_to_title(slug) == expected


def test_slug_to_title_preserves_word_order(inventory):
    assert inventory.slug_to_title("posterior-fossa-approach") == (
        "Posterior Fossa Approach"
    )
