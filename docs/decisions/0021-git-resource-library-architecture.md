# ADR 0021: Git Resource Library Architecture

## Date
2026-07-20

## Status
Accepted

## Context
The `tool/gui` editor had a `GitLibraryDialog` that supported only one git remote at a time, with no persistent settings, no saved remote catalog, and no configuration for git binary path, clone root, or timeout. The dialog's URL, local directory, and language code had to be re-entered every session. The "资源库" (resource library) was thus a single-connection tool rather than a true library of named remotes.

Additionally, `docs/decisions/` did not exist despite CLAUDE.md referencing ADRs 0001-0020. This ADR establishes the directory and documents the git resource library architecture.

## Decision
1. **Saved remotes catalog** (`git_remote_catalog.py`): A lightweight `SavedRemote` dataclass (name, url, local_dir, lang, last_synced_at) persisted in QSettings as JSON. CRUD operations: `add_remote`, `remove_remote`, `update_remote`, `find_by_url`, `mark_synced`. Distinct from `Settings.recent_repos` (which tracks opened course directories, not git remote definitions).

2. **Settings integration** (`settings.py`): New `Settings` fields: `git_clone_root`, `git_bin`, `default_lang_code`, `lan_default_port`, `lan_bind_address`, `lan_token`, `git_timeout`, `assets_repo_root`. All persisted in QSettings under `git/*` keys with clamping (port 1-65535, timeout 5-600s).

3. **Settings dialog "Git 库" tab** (`settings_dialog.py`): A 7th tab with basic config (clone root, git bin, default lang, timeout, assets root), LAN defaults (port, bind address, token), SSH key path, saved remotes table (CRUD), and HTTPS credential management.

4. **GitLibrary config injection** (`git_library.py`): `GitLibrary.__init__` now accepts `git_bin`, `timeout`, `token`, `ssh_key_path`. Auth is injected via `http.extraheader=Authorization: Bearer <token>` for HTTPS and `GIT_SSH_COMMAND` env for SSH.

5. **Dialog auto-fill**: `GitLibraryDialog` accepts a `settings` param, auto-fills URL/dir/lang from Settings, and writes back saved remotes on successful connection.

## Consequences
- Users no longer re-enter remote URLs each session.
- The "资源库" dropdown can surface saved remotes for one-click access.
- Git binary path and timeout are configurable, supporting non-standard git installations.
- `assets_repo_root` is configurable, decoupling from the hardcoded `parents[4]` resolution.
- The `docs/decisions/` directory is now established for future ADRs.
