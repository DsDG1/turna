# ADR 0025: Textbook Library and Git Integration

## Date
2026-07-20

## Status
Accepted

## Context
The textbook project library (`TextbookLibraryDialog`) and the git resource library (`GitLibraryDialog`) were isolated systems. Users could not import a textbook source file from a git repository, nor publish a completed textbook project's section JSON back to a git remote. There was also no way to synchronize a course's local resource lists (vocab/expressions/grammar_points) with a git-backed shared resource pool.

## Decision
1. **"从 Git 库导入教材…" button** (`TextbookLibraryDialog`): Lists saved remotes, clones/pulls the selected remote, opens a file picker scoped to the clone directory, and creates a new `TextbookProject` with the selected `.md/.txt/.pdf` file as the source.

2. **"发布到 Git 库…" button** (`TextbookLibraryDialog`): Loads the selected project, clones/pulls the target remote, exports the project's section JSON files into `sections/<id>.json`, updates `index.json`, and commits+pushes with a descriptive message.

3. **Resource pool sync** (`CourseAdapter.sync_resources_with_git`): Bidirectional merge of `vocab.json`/`expressions.json`/`grammar_points.json` between the local course and a git clone directory. Merges by id (skips duplicates), writes back to both sides, returns a human-readable summary.

4. **"同步资源池" button** (`GitLibraryDialog` Tab 1): Invokes `sync_resources_with_git` with the current clone dir and language code.

## Consequences
- Textbook sources can be version-controlled in git and imported directly.
- Finished courses can be published to git without manual file copying.
- Shared resource pools enable team collaboration on vocab/expressions/grammar.
- The sync is non-destructive (merge by id, never deletes existing entries).
