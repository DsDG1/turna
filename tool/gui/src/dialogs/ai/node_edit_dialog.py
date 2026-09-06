"""K-05 node AI edit dialog — production entry for course-tree AI editing.

Wraps the shared :class:`~src.dialogs.ai_generator_dialog.SectionAiDialog`
engine in edit mode (instruction-based rewrite plus optional wish-chat
revision of an existing section). The former monolithic ``AiGeneratorDialog``
keeps only the workshop generation facade; this module is the single import
point for the tree edit path (ai_refactor_contract §1f).
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import QWidget

from src.dialogs.ai.section_ai_dialog import SectionAiDialog


class NodeAiEditDialog(SectionAiDialog):
    """AI edit dialog for a section / unit / lesson node.

    On accept, ``section_json()`` returns the edited section dict with the
    original node id preserved; the caller validates and applies it through
    the undo stack.
    """

    def __init__(
        self,
        adapter,
        parent: QWidget | None = None,
        scope: str = "section",
        scope_id: str = "",
        existing_section: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(
            adapter,
            parent,
            edit_mode={
                "scope": scope,
                "scope_id": scope_id,
                "existing_section": existing_section or {},
            },
        )
