"""Undoable edit commands for the course editor (B2).

Each QUndoCommand mutates the in-memory course tree (via the pure helpers in
``lesson_content``) and emits a ``changed`` signal on redo/undo so the
teacher views re-render. The MainWindow owns the QUndoStack; detail widgets
push commands onto it instead of mutating dicts directly.

Commands are coarse-grained to cover the common error-prone edits: item
add/delete, item move, sub-lesson/stage delete, and field updates. Field
edits coalesce by tracking the previous value so a single "edit prompt"
produces one undoable step.

Tree-level commands (new/delete section/unit/lesson, AI import/edit) and
metadata commands (name/description/prerequisites) are also defined here so
the whole editor shares one undo stack.

The package is split by domain — ``item_commands`` (items, sub-lessons,
stages, listening phases), ``tree_commands`` (sections/units/lessons
structure + bulk operations), ``ai_commands`` (AI import/edit/merge with
resource rollback) and ``meta_commands`` (node attributes, prerequisites,
experience patches). This module re-exports the full public surface so
``from src.application.commands import X`` keeps working unchanged.
"""
from __future__ import annotations

from src.application.commands.ai_commands import (
    AiEditLessonCommand,
    AiEditSectionCommand,
    AiEditUnitCommand,
    AppendLessonsToUnitCommand,
    AppendUnitsToSectionCommand,
    ImportAiSectionCommand,
    MergeAiSectionCommand,
)
from src.application.commands.item_commands import (
    AddItemCommand,
    AddListeningPhaseCommand,
    AddStageCommand,
    AddSubLessonCommand,
    DeleteItemCommand,
    DeleteListeningPhaseCommand,
    DeleteStageCommand,
    DeleteSubLessonCommand,
    MoveItemCommand,
    MoveListeningPhaseCommand,
    MoveStageCommand,
    MoveSubLessonCommand,
    RenameListeningPhaseCommand,
    RenameStageCommand,
    RenameSubLessonCommand,
    UpdateFieldCommand,
)
from src.application.commands.meta_commands import (
    ApplyBatchPatchCommand,
    ApplyFieldPatchCommand,
    ApplyItemPatchCommand,
    ApplyLessonPatchCommand,
    ApplySectionPatchCommand,
    ReplaceItemCommand,
    SoftHygieneCommand,
    UpdateLessonLinkedGrammarCommand,
    UpdateLessonMetaCommand,
    UpdateLessonPrereqsCommand,
    UpdateSectionMetaCommand,
    UpdateSectionPrereqsCommand,
    UpdateUnitMetaCommand,
    UpdateUnitPrereqsCommand,
)
from src.application.commands.tree_commands import (
    AppendLessonCommand,
    AppendUnitCommand,
    BulkApplyPresetCommand,
    BulkDeleteLessonsCommand,
    BulkDuplicateLessonsCommand,
    BulkMoveLessonsCommand,
    DeleteLessonCommand,
    DeleteSectionCommand,
    DeleteUnitCommand,
    DuplicateLessonCommand,
    MoveLessonCommand,
    MoveSectionCommand,
    MoveUnitCommand,
    NewLessonCommand,
    NewUnitCommand,
    ReparentLessonCommand,
    ReparentUnitCommand,
)

__all__ = [
    # item-level
    "AddItemCommand",
    "AddListeningPhaseCommand",
    "AddStageCommand",
    "AddSubLessonCommand",
    "DeleteItemCommand",
    "DeleteListeningPhaseCommand",
    "DeleteStageCommand",
    "DeleteSubLessonCommand",
    "MoveItemCommand",
    "MoveListeningPhaseCommand",
    "MoveStageCommand",
    "MoveSubLessonCommand",
    "RenameListeningPhaseCommand",
    "RenameStageCommand",
    "RenameSubLessonCommand",
    "UpdateFieldCommand",
    # tree-level
    "AppendLessonCommand",
    "AppendUnitCommand",
    "BulkApplyPresetCommand",
    "BulkDeleteLessonsCommand",
    "BulkDuplicateLessonsCommand",
    "BulkMoveLessonsCommand",
    "DeleteLessonCommand",
    "DeleteSectionCommand",
    "DeleteUnitCommand",
    "DuplicateLessonCommand",
    "MoveLessonCommand",
    "MoveSectionCommand",
    "MoveUnitCommand",
    "NewLessonCommand",
    "NewUnitCommand",
    "ReparentLessonCommand",
    "ReparentUnitCommand",
    # AI import/edit/merge
    "AiEditLessonCommand",
    "AiEditSectionCommand",
    "AiEditUnitCommand",
    "AppendLessonsToUnitCommand",
    "AppendUnitsToSectionCommand",
    "ImportAiSectionCommand",
    "MergeAiSectionCommand",
    # metadata / experience patches
    "ApplyBatchPatchCommand",
    "ApplyFieldPatchCommand",
    "ApplyItemPatchCommand",
    "ApplyLessonPatchCommand",
    "ApplySectionPatchCommand",
    "ReplaceItemCommand",
    "SoftHygieneCommand",
    "UpdateLessonLinkedGrammarCommand",
    "UpdateLessonMetaCommand",
    "UpdateLessonPrereqsCommand",
    "UpdateSectionMetaCommand",
    "UpdateSectionPrereqsCommand",
    "UpdateUnitMetaCommand",
    "UpdateUnitPrereqsCommand",
]
