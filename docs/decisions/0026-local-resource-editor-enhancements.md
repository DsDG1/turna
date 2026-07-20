# ADR 0026: Local Resource Editor Enhancements

## Date
2026-07-20

## Status
Accepted

## Context
The `ResourceEditorDialog` (local resource library for vocab/expressions/grammar_points) had per-tab add/delete and CSV import/export, but lacked cross-tab search, batch operations, duplicate detection, resource pack import/export, and any way to identify cross-table duplicates between vocab and expressions.

## Decision
1. **Cross-tab unified search**: A search bar at the top of `ResourceEditorDialog` filters all three tabs simultaneously (case-insensitive substring match on any cell). `ResourceTableWidget.apply_filter(text)` hides non-matching rows.

2. **Multi-select batch delete**: Tables now use `ExtendedSelection` mode. A "批量删除" button deletes all selected rows at once with confirmation.

3. **Duplicate detection** (`CourseAdapter.detect_duplicates`): Scans vocab and expressions for matching normalized terms (lowercase, stripped). Returns a list of `{type, id, term, duplicate_in}` dicts. A "查重" button displays results.

4. **Resource pack export/import** (`CourseAdapter.export_resource_pack`/`import_resource_pack`): Exports all three resource lists as a single JSON file `{"vocab": [...], "expressions": [...], "grammar_points": [...]}`. Import supports merge (by id, skip duplicates) or replace mode.

## Consequences
- Large resource lists can be filtered quickly without per-tab searching.
- Batch delete reduces repetitive confirmation dialogs.
- Cross-table duplicates (e.g., "nasılsın?" appearing in both vocab and expressions) are surfaced.
- Resource packs enable sharing curated resource sets between courses or teams.
- The pack format is plain JSON, version-controllable in git.
