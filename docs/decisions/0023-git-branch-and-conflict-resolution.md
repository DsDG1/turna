# ADR 0023: Git Branch Management and Conflict Resolution

## Date
2026-07-20

## Status
Accepted

## Context
The `GitLibrary` backend only supported `pull --ff-only`, which fails on diverged histories. There was no branch selector, no remote picker, and no conflict resolution UI. Users seeing a "pull failed" error had no in-app path to resolve it.

## Decision
1. **Branch management API** (`GitLibrary`): Added `list_branches`, `current_branch`, `create_branch`, `switch_branch`, `delete_branch`, `list_remotes_all`, `add_remote`, `remove_remote`, `push_to`, `pull_from`.

2. **Conflict resolution API**: Added `merge`, `merge_abort`, `stash`, `stash_pop`, `reset_to` (hard/soft/mixed), `revert`, `has_conflicts`, `pull_rebase` (already existed).

3. **Branch selector UI** (`GitLibraryDialog` Tab 1): A `QComboBox` listing local branches with "新建/切换/删除" buttons. Refreshes on state change.

4. **Conflict resolution dialog**: When `pull --ff-only` fails, `_on_pull_conflict` shows a three-option dialog:
   - **Yes = Rebase** (recommended, keeps linear history)
   - **No = Stash + Pull + Pop** (preserve local changes)
   - **Cancel = Abort**

5. **Push diff preview**: "查看待推送改动 (diff)" button shows `git diff HEAD --stat` before pushing.

6. **History context menu**: Right-click on a commit in the history table offers "Reset --hard/soft to <ref>" and "Revert <ref>".

## Consequences
- Users can manage branches without leaving the editor.
- Diverged histories no longer require manual terminal intervention.
- Pre-push diff preview reduces accidental pushes.
- Reset/revert provide history manipulation with confirmation dialogs.
