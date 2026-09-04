"""Compat re-export: the module moved to ``src.backend.error_mapper``.

Backend modules (``ai_fix_batch`` / ``experience.context_bus`` / ``why``)
need these pure mappings, so the implementation lives under ``backend`` to
keep the dependency direction backend ← teacher-free. Teacher/UI callers
may keep importing from here during the transition.
"""
from __future__ import annotations

from src.backend.error_mapper import (  # noqa: F401
    humanize_problem,
    parse_path,
    problem_to_node_ref,
)

__all__ = ["humanize_problem", "parse_path", "problem_to_node_ref"]
