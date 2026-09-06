"""AI course-generation dialog package.

Canonical location for AI dialog components:
- ``SectionAiDialog``: shared dialog engine (in section_ai_dialog.py)
- ``NodeAiEditDialog``: production entry for course-tree AI editing
- ``AiGeneratorDialog``: workshop course-generation UI facade
"""
from src.dialogs.ai.section_ai_dialog import SectionAiDialog, AiGeneratorDialog
from src.dialogs.ai.node_edit_dialog import NodeAiEditDialog

__all__ = [
    "AiGeneratorDialog",
    "NodeAiEditDialog",
    "SectionAiDialog",
]