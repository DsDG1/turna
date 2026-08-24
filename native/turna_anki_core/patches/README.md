# Turna patches against pinned Anki

All patches replay through `build-android/apply_patches.sh` (called by
`build.sh`, `host-test.sh`, and `verify_pin.sh`). `verify_pin.sh` additionally
fails if the `anki/` working tree differs from the pinned commit anywhere
outside the files covered by these patches. Do not edit `anki/` as a mixed
Turna tree.

## 0001-export-progress-state

- File: `anki/rslib/src/lib.rs`
- Change: `pub use progress::ProgressState;`
- Why: CollectionBuilder already accepts a shared `ProgressState` so a
  second thread can set `want_abort` during `import_apkg`. The type was
  public inside a private module, so the external bridge could not
  construct it. One-line re-export, no behavior change.
- Delete when: upstream re-exports `ProgressState` or offers another
  abort handle on Collection.

## 0002-export-clear-study-queues

- File: `anki/rslib/src/scheduler/queue/mod.rs`
- Change: `clear_study_queues` `pub(crate)` → `pub` (+ doc line).
- Why: the bridge answers off-queue cards (`from_queue = false`,
  `bridge/src/ops.rs` answer path) and must drop the in-memory study
  queues so the next fetch rebuilds them, mirroring what `transact()`
  does for queue answers. Upstream only exposes this to in-crate callers.
- Delete when: upstream makes the queue-invalidation reachable after an
  off-queue answer (e.g. via `OpChanges` from `answer_card`).

## 0003-export-encode-iri-paths

- File: `anki/rslib/src/text.rs`
- Change: `encode_iri_paths` `pub(crate)` → `pub`.
- Why: the bridge's display path (`bridge/src/display.rs`) re-encodes
  media paths for the sandboxed reviewer iframe the same way the Qt
  client does. Pure visibility change, no behavior change.
- Delete when: upstream exposes an HTML-escaping helper for embedders
  or the bridge stops re-encoding paths itself.

If a later task needs an upstream change:

1. Add a numbered `.patch` produced with `git -C anki diff -- <file>`
   (or `format-patch`), one logical change per patch.
2. Document reason, upstream issue/PR, and the deletion condition here.
3. Replay only through `apply_patches.sh`. Do not edit `anki/` as a
   mixed Turna tree.
4. Record the patch in `README.md` and the phase result report.
