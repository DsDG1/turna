"""Git library dialog package — domain split of GitLibraryDialog.

``git_library_dialog.py`` keeps the dialog shell (assembly + delegation);
each feature domain lives in its own module here, taking the dialog as an
explicit context object (``dlg``), mirroring the ``dialogs/ai/`` split:

- ``git_worker_hub`` — shared async git-call plumbing (B5); also reused by
  ``textbook_library_dialog``.
- ``sync`` — connect / fetch / pull / push / copy-to-assets / resource sync.
- ``remotes`` — saved-remote catalog (double-click reconnect).
- ``branches`` — branch list / create / switch / delete.
- ``repo_browser`` — history / diff / file tree / reset / revert.
- ``lan_share`` — LAN server hosting + log polling.
- ``memo`` — team memo board (.collaboration_memo.json + pagination).

``GitLibraryDialog`` is re-exported lazily via :pep:`562` module
``__getattr__`` rather than eagerly. The eager import made this package
import ``git_library_dialog``, which imports the feature modules *from
this package* — a module-level import cycle. Lazy resolution keeps
``from src.dialogs.git_library import GitLibraryDialog`` working while
``make guard-gui`` sees zero module-level cycles in ``src/``.
"""
from __future__ import annotations

from typing import Any

__all__ = ["GitLibraryDialog"]


def __getattr__(name: str) -> Any:
    if name == "GitLibraryDialog":
        from src.dialogs.git_library_dialog import GitLibraryDialog

        return GitLibraryDialog
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
