# Turna patches against pinned Anki

## 0001-export-progress-state

- File: `anki/rslib/src/lib.rs`
- Change: `pub use progress::ProgressState;`
- Why: CollectionBuilder already accepts a shared `ProgressState` so a
  second thread can set `want_abort` during `import_apkg`. The type was
  public inside a private module, so the external bridge could not
  construct it. One-line re-export, no behavior change.
- Delete when: upstream re-exports `ProgressState` or offers another
  abort handle on Collection.

If a later P0 task needs an upstream change:

1. Add a numbered `.patch` produced with `git -C anki format-patch`.
2. Document reason, upstream issue/PR, and the deletion condition.
3. Replay only through a script. Do not edit `anki/` as a mixed Turna tree.
4. Record the patch in `README.md` and the Phase 0 result report.
