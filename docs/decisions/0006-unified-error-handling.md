# ADR 0006: Unified error handling

- **Status**: Accepted
- **Date**: 2026-07-10
- **Related**: Robustness roadmap Phase 2, ADR 0005

## Context

Error handling was scattered across the codebase as ad-hoc `try/catch + debugPrint`:
- `LessonViewModel._onLessonCompleted` had six independent try/catch blocks (XP award, gem award ×2, lesson-completion record, milestone check, study-stats record), each swallowing errors into `debugPrint`.
- `CourseRepository._decodePracticeItems` silently swallowed JSON corruption and returned an empty list, so a corrupted grammar-point `practiceItems` column was invisible.
- `lib/core/logger.dart` had dead code (`logsPermissions`) and its `EnableLogging` filter always returned `true`, so the full log level (including verbose debug prints) ran in release builds.
- No global error boundary: uncaught framework/platform errors were only visible in debug consoles and disappeared in release.

There was no shared `Result`/`Either` type to make the failure channel explicit in signatures.

## Decision

1. Add a lightweight, dependency-free `Result<T>` sealed type (`lib/core/result.dart`) with `Success`/`Failure` variants, a `Result.guard` async factory, `map`/`flatMap`/`fold`, and a `logFailure(label)` helper. Chosen over a package (e.g. `dartz`) to keep the offline-first dependency surface minimal.

2. Collapse `LessonViewModel._onLessonCompleted`'s six try/catch blocks into one `_runSideEffect(label, action)` helper that routes failures through the `logger` with a contextual label. Each side-effect remains independently resilient (one failing does not abort the others), preserving the prior semantics — but the boilerplate is gone and failures are observable instead of `debugPrint`-only.

3. `CourseRepository._decodePracticeItems` now logs the corruption with the owning grammar-point id before degrading to an empty list, turning a silent swallow into an observable degradation. The caller passes `owner: 'grammar point ${row.id}'` for context.

4. Install global error handlers in `main.dart` before `WidgetsFlutterBinding.ensureInitialized()`: `FlutterError.onError` records framework errors (and still presents them) via the logger; `PlatformDispatcher.instance.onError` captures isolate/async-gap errors and returns `true` to suppress the default crash print. Errors are logged locally only — never sent to a remote backend (consistent with the offline-first principle).

5. Rewrite `lib/core/logger.dart`: remove the dead `logsPermissions` variable; the filter now emits all levels in debug/test but suppresses below `Level.warning` in release (`kReleaseMode`), so production logs are not flooded with routine noise.

`onUnknownRoute` was investigated for `MaterialApp.router` but `auto_route` 9.2.2's `config()` does not expose it; the global handlers cover framework-level route errors, so this was left to auto_route's default placeholder.

## Phase 17 update — persistence-layer error unification

The persistence layer still had ad-hoc output that was either release-silent or bypassed the `logger`:

- `StudyLogRepository` used `assert(() { print(...); }())` in `readAllDailyStats` / `_enqueueWrite` — assertions are stripped in release, so the degradations were **invisible in production**.
- `LessonLinkStore` used bare `print()` (fires in all modes, but not through the logger and not level-filtered).
- `SrsProvider` / `GrammarReviewProvider` used `debugPrint` for decode failures and had **no** error handling on `_persist` at all — a prefs write failure would propagate to callers like `reviewWord`.

These were unified to `logger.w` (observable in release via the `warning+` filter):

- `StudyLogRepository`: `readAllDailyStats`, `_enqueueWrite`, and a new `_readLogs` try-catch (corrupted logs degrade to an empty list instead of throwing).
- `LessonLinkStore`: `readAll` and `_enqueue`.
- `SrsProvider` / `GrammarReviewProvider`: `state` decode + a new `_persist` try-catch (in-memory cache is updated before the write, so synchronous callers still see the new state; a write failure is logged and retried on the next mutation).
- `CourseRepository._toLesson`: a new try-catch degrades corrupted `contentJson` to `const LessonContent()` (mirroring the existing `_decodePracticeItems` / `_decodeStringList` pattern) instead of crashing `section()` / `lessonById()`.

`AppPrefs.printBefore` was also tightened: it now logs only the key by default, and emits the value only under a second-level `Very.verbose` debug switch (`lib/core/verbose.dart`). Release builds reach none of this because callers gate on `kDebugMode` first (and the `_ReleaseAwareFilter` suppresses `.d` in release), so production logs emit zero prefs values.

## Consequences

- Lesson-completion side-effect failures are now tagged and logged at `warning` rather than printed as debug strings.
- Corrupted `practiceItems` is observable in logs with the grammar-point id, aiding diagnosis.
- Uncaught framework and platform errors are logged in release builds instead of vanishing.
- Release builds log at `warning+`; debug/test builds keep full verbosity.
- `Result` is available as a shared type for future call sites that want explicit success/failure without adding a dependency.
- Persistence-layer degradations (corrupted prefs/DB content, write failures) are now observable in release logs; `print` / `debugPrint` / `assert(()=>print())` are removed from the persistence layer.
- `AppPrefs` no longer dumps values into debug logs by default.
- All 197 tests pass (184 from Phase 1 + 13 new `Result` tests), and the existing `lesson_viewmodel_flow_test` confirms the `_onLessonCompleted` refactor preserves behavior.
- Phase 17 extends coverage with corruption-degradation tests for `CourseRepository._toLesson` and `StudyLogRepository._readLogs`; total suite is 314 (see `test/BASELINE.md`).