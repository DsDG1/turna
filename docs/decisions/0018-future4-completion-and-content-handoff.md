# ADR 0018: future4 Completion and future5 Content Handoff

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phases 16–26, future5 plan, ADRs 0009–0017

## Context

`future4.md` was created to close the non-content gaps left by `future3.md` and to harden the Varnamala framework for long-term maintenance. The plan explicitly excluded new real Swahili vocabulary and lesson rewriting — those were reserved for a follow-up content round.

After Phases 16–25, the framework round is complete. This ADR records what was delivered and defines the clean handoff to `future5`, which will focus on content-only changes.

## What future4 Delivered

### 1. Test foundation (Phase 16)

Direct tests for the modules most likely to be touched by refactoring:

- `test/core/sm2_test.dart` — SM-2 interval/ease/reps/lapse evolution.
- `test/data/study_log_repository_test.dart` — append, read, purge, write-chain serialization, corruption fallback.
- `test/data/course_repository_test.dart` — batch section loading, lesson-by-id, content corruption fallback.
- `test/application/lesson_link_store_test.dart` — first-seen semantics and write-chain.
- `test/data/schema_migration_test.dart` — v1/v2/v3/v4 → v5 plus downgrade path.
- `test/application/srs_provider_test.dart` — register, review, cache invalidation.

This foundation made the later structural refactors safe.

### 2. Engineering hygiene and robustness (Phase 17)

- Unified persistence-layer error handling to `logger.w`.
- Corruption fallbacks in `CourseRepository._toLesson` and `StudyLogRepository._readLogs`.
- `CourseDatabase.onDowngrade` to avoid crashes on schema rollback.
- Runtime cross-section lesson id uniqueness gate in the seeder.
- `expressions.json` version included in reseed trigger.
- Android applicationId moved from `com.example.varnamala` to `com.varnamala.app` with `key.properties` signing skeleton.
- Content update prompt on built-in course version change.

### 3. DI consolidation and audio/content decoupling (Phase 18)

- `AudioController` and `MatchProvider` switched from `getIt<>` lookups to constructor injection.
- `MatchProvider` fields privatized + read-only getters.
- `VocabAudioResolver` abstraction introduced; `AudioController` no longer imports `swahili_vocab.dart`.
- Asset path normalization moved from `ListenOnlyRenderer` into `AudioController`.
- `AppRouter` annotated with `@lazySingleton` and `CourseReadyGuard` added.

### 4. Performance wave I (Phase 19)

- Removed per-keystroke `setState` from four input renderers.
- Cached `LearningStats` futures across tab switches.
- Routed `getWeakWords()` through `MistakeProvider._cached`.
- Provider rebuild audit + course tree lazy loading.

### 5. Performance wave II (Phase 20)

- Cached `expressionDueCount`.
- Performance baselines and ADRs for SRS persistence scaling (0011) and study-log append strategy (0012).
- Parameterized `_PlayHubCard` replacing five near-duplicate cards.
- Hard-coded `Colors.white` and similar migrated to `VarnamalaTheme` semantic helpers.

### 6. SRS base class and repository interfaces (Phase 21)

- `SrsQueueProvider` base class extracted; `SrsProvider` and `GrammarReviewProvider` became thin subclasses.
- `ICourseRepository` and `IStudyLogRepository` interfaces defined; concrete repositories implement them.
- `PiperSwahiliTts._init` moved from polling loop to `Completer`.

### 7. Learning experience features (Phase 22)

- `/dictionary` route and search over existing vocab / expression / grammar content.
- Weak-word review (30d / ≥2 mistakes) using `WeakWordQuizAssembler`.
- Local daily reminder via `flutter_local_notifications`.
- Course tree state badges (completed / weak / due).
- Accessibility pass: tooltips, MCQ semantics, contrast, input labels.

### 8. GameProvider split (Phase 23)

- `GameProvider` split into `ScoreProvider`, `StreakProvider`, `LessonProgressProvider`, `GameMilestoneProvider`.
- `streak_resolver.dart` extracted as a pure function.
- `GameProvider` kept as a thin facade so existing call sites remained unchanged.

### 9. Integration tests and golden baselines (Phase 24)

- `integration_test/lesson_flow_test.dart`
- `integration_test/srs_review_flow_test.dart`
- `integration_test/dictionary_and_weak_words_test.dart`
- Golden tests for play hub, dictionary, settings reminder, and SRS empty state in light + dark themes.
- Widget gap coverage for match words, settings sound section, and lesson completion dialog.

### 10. Release pipeline (Phase 25)

- `tool/build_release.py` — one-command builder for APK/AAB/web + content inventory.
- `test/tool/build_release_test.py` — Python unit tests for the script.
- `docs/content_inventory_v0.4.0-future4.md` — release content report.
- CI build smoke test via `make build-release-smoke`.
- Local tag `v0.4.0-future4`.

### 11. Documentation handoff (Phase 26)

- Updated `CLAUDE.md` to reflect the new providers, routes, features, and release pipeline.
- This ADR (0018) formalizes completion and the future5 entry point.

## Decision

### future4 is closed

No new framework-wide refactoring belongs in `future4`. The remaining ADR sequence (0001–0018) is complete. Any further framework fixes should be small, targeted PRs with their own justification; large framework churn requires a new plan document.

### future5 is a content-only round

`future5` has a single responsibility: replace the Kannada-as-Swahili placeholder content with real Swahili vocabulary and rewrite lessons. It must **not** introduce new framework mechanisms unless absolutely unavoidable. The following foundations from future4 make that possible:

1. **Regression safety** — Integration tests and golden baselines catch content-side breakage.
2. **Audio decoupling** — `VocabAudioResolver` lets real Swahili audio wiring happen without touching `AudioController`.
3. **Repository interfaces** — Content loaders can be mocked or swapped without changing viewmodels.
4. **SRS / study-log scaling** — Decisions 0011 and 0012 documented the thresholds; if real content crosses them, the implementation path is already agreed.
5. **Feature readiness** — Dictionary, weak-word review, reminders, and course-tree state all work against placeholder content and will become useful immediately when real content arrives.

### Content PR acceptance criteria for future5

- `flutter test` must stay green at the current baseline (or higher).
- `flutter analyze` must remain clean.
- `tool/course_cli.py validate` must pass for the updated course JSON.
- `docs/content_inventory_current.md` must be regenerated and diffed against the previous release report.
- No changes to `lib/application/`, `lib/data/`, or `lib/routing/` unless the change is justified by an ADR amendment.

## Consequences

- Future content work has a stable, documented foundation.
- The boundary between "framework" and "content" is explicit, reducing the risk of future5 turning into another framework round.
- `CLAUDE.md` and `future4.md` together describe the completed system; `future5.md` should reference this ADR as the starting point.

## Alternatives considered

- **Continue framework work under future4.** Rejected: the original scope was "framework + non-content features"; expanding it would delay content and blur accountability.
- **Start future5 without a formal handoff ADR.** Rejected: without explicit closure, future contributors might reintroduce framework churn during content work.
