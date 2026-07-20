"""Shared QSettings mock for tests.

Minimal dict-backed ``QSettings`` mock exposing the value/setValue/beginGroup/
endGroup surface used by the prompt-library tests. Tests needing a richer
surface (contains/remove, or a pre-seeded store) keep their own local helper.
"""
from __future__ import annotations

from unittest.mock import MagicMock


def make_qsettings(store: dict | None = None) -> MagicMock:
    """Return a dict-backed ``QSettings`` mock with value/setValue + groups."""
    data: dict[str, str] = {} if store is None else dict(store)
    qs = MagicMock()
    qs.value = lambda key, default="": data.get(key, default)
    qs.setValue = lambda key, value: data.__setitem__(key, value)
    qs.beginGroup = lambda _name: None
    qs.endGroup = lambda: None
    return qs