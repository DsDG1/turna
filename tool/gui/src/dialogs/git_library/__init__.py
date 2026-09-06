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
"""
from src.dialogs.git_library_dialog import GitLibraryDialog

__all__ = ["GitLibraryDialog"]
