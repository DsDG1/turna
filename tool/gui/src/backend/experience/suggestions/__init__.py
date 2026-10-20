"""Experience suggestion builders (M6).

``local_suggestions`` is re-exported lazily via :pep:`562` module
``__getattr__`` instead of an eager ``from ... import local_suggestions``.

Why: the eager re-export made this package ``__init__`` import
``ambient``, and ``ambient`` imports the sibling collectors *through this
package* (``from src.backend.experience.suggestions import p0_validate``).
That is a module-level import cycle — the package imported its own
submodule, which imported the package back.

The lazy re-export breaks the cycle without changing any call site:
``from src.backend.experience.suggestions import local_suggestions`` still
works, it just resolves on first attribute access instead of at import
time. ``make guard-gui`` asserts zero module-level import cycles inside
``src/``.
"""
from __future__ import annotations

from typing import Any

__all__ = ["local_suggestions"]


def __getattr__(name: str) -> Any:
    if name == "local_suggestions":
        from src.backend.experience.suggestions.ambient import local_suggestions

        return local_suggestions
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
