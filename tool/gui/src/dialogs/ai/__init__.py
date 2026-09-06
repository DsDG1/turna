"""AI course-generation dialog package.

The large monolithic ``AiGeneratorDialog`` was split (guiplan2 P5) into focused
widgets under this package. ``src/dialogs/ai_generator_dialog.py`` remains as a
facade that re-exports ``AiGeneratorDialog`` and ``AiRequestWorker`` so existing
imports (and test patches) keep working unchanged.

Dialog roles (ai_refactor_contract §1f):

- ``AiGeneratorDialog`` — workshop course-generation UI (generation only).
- ``node_edit_dialog.NodeAiEditDialog`` — production entry for course-tree AI
  editing; wraps the shared ``SectionAiDialog`` engine in edit mode.
"""