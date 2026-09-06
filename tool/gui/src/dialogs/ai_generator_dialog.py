"""Compatibility shim re-exporting symbols from ``src.dialogs.ai.section_ai_dialog``.

Moved to ``src/dialogs/ai/section_ai_dialog.py`` as part of Step 1 refactoring.
This file is kept for backwards compatibility with existing tests and call sites.
New code should import directly from ``src.dialogs.ai.section_ai_dialog``
or ``src.dialogs.ai.node_edit_dialog``.
"""
from __future__ import annotations

from src.application.ai_request_worker import (
    AiRequestWorker,
    AttachmentRecord as _AttachmentRecord,
)
from src.dialogs.ai.section_ai_dialog import (
    AiGeneratorDialog,
    SectionAiDialog,
    _escape_html,
    _record_cache_stats,
)

__all__ = [
    "AiGeneratorDialog",
    "AiRequestWorker",
    "SectionAiDialog",
]
