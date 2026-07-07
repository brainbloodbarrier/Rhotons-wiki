"""Shared pytest fixtures and module loaders for the deterministic Python tooling.

The tool directories are hyphenated (``datalab-augment``) and several tools are
named identically across wikis (two ``preflight.py`` files, several
``atomic_write`` helpers), so we cannot rely on normal package imports. Instead
we load each target module by file path via importlib under a unique alias.

Some sibling modules (``map_chapters.py``, ``attribute_figures.py``) do
``from _shared import ...`` at import time, expecting ``_shared`` to be
importable by name from ``sys.path[0]``. We satisfy that by adding the
augment tool directory to ``sys.path`` and registering the loaded ``_shared``
module under the bare name ``_shared`` in ``sys.modules`` before loading its
siblings.

None of these modules do real work at import time — each gates its side effects
behind ``if __name__ == "__main__":`` — so importing them is safe.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
AUGMENT_DIR = REPO_ROOT / "rhoton-wiki" / "tools" / "datalab-augment"
RHOTON_DATALAB_DIR = REPO_ROOT / "rhoton-wiki" / "tools" / "datalab"
NSATLAS_DATALAB_DIR = REPO_ROOT / "nsatlas-wiki" / "tools" / "datalab"


def _load(alias: str, path: Path, *, register_bare: str | None = None):
    """Load a module from an explicit file path under a unique alias.

    If ``register_bare`` is given, the module is also registered under that
    bare name in ``sys.modules`` so sibling ``from <bare> import ...`` lines
    resolve to the same object.
    """
    spec = importlib.util.spec_from_file_location(alias, path)
    if spec is None or spec.loader is None:  # pragma: no cover - defensive
        raise ImportError(f"could not build spec for {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[alias] = module
    if register_bare:
        sys.modules[register_bare] = module
    spec.loader.exec_module(module)
    return module


# ``_shared`` must be importable as the bare name before its siblings load,
# and the augment dir must be on sys.path for the sibling `from _shared import`.
sys.path.insert(0, str(AUGMENT_DIR))
_rhoton_shared = _load("rhoton_shared", AUGMENT_DIR / "_shared.py", register_bare="_shared")
_rhoton_map_chapters = _load("rhoton_map_chapters", AUGMENT_DIR / "map_chapters.py")
_rhoton_attribute_figures = _load(
    "rhoton_attribute_figures", AUGMENT_DIR / "attribute_figures.py"
)
_rhoton_page_ranges = _load("rhoton_page_ranges", RHOTON_DATALAB_DIR / "page_ranges.py")
_rhoton_datalab_convert = _load(
    "rhoton_datalab_convert", RHOTON_DATALAB_DIR / "datalab_convert.py"
)
_nsatlas_convert = _load("nsatlas_convert", NSATLAS_DATALAB_DIR / "nsatlas_convert.py")
_nsatlas_cleanup_images = _load(
    "nsatlas_cleanup_images", NSATLAS_DATALAB_DIR / "cleanup_images.py"
)
_nsatlas_inventory = _load(
    "nsatlas_inventory", NSATLAS_DATALAB_DIR / "nsatlas_inventory.py"
)


@pytest.fixture
def shared():
    return _rhoton_shared


@pytest.fixture
def map_chapters():
    return _rhoton_map_chapters


@pytest.fixture
def attribute_figures():
    return _rhoton_attribute_figures


@pytest.fixture
def page_ranges():
    return _rhoton_page_ranges


@pytest.fixture
def datalab_convert():
    return _rhoton_datalab_convert


@pytest.fixture
def nsatlas_convert():
    return _nsatlas_convert


@pytest.fixture
def cleanup_images():
    return _nsatlas_cleanup_images


@pytest.fixture
def inventory():
    return _nsatlas_inventory
