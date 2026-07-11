# Test Baseline

Generated: 2026-07-11 (Phase 16 — test foundation for future4)

## Results
- Passed: 296
- Failed: 0
- Total: 296
- `flutter analyze`: No issues found

## New / Extended Test Files
- `test/core/sm2_test.dart` — SM-2 engine direct tests (11 cases).
- `test/application/lesson_link_store_test.dart` — first-seen links, `_writeChain`, corruption (7 cases).
- `test/data/study_log_repository_test.dart` — append/aggregation, 90-day purge, serialization, corruption (10 cases).
- `test/data/course_repository_test.dart` — section/unit/lesson rebuild, sort order, `lessonById`, corruption degradation (12 cases).
- `test/data/schema_migration_test.dart` — added `v3 -> v5` migration preservation.
- `test/application/srs_provider_test.dart` — added due-count caching and review progression tests.

## Notes
- Phase 16 does **not** modify production code (`lib/`, `android/`, `assets/`, `tool/`).
- Two known gaps documented in tests and scheduled for future4 Phase 17:
  - `StudyLogRepository._readLogs` does not catch malformed JSON yet.
  - `CourseRepository._toLesson` does not degrade on malformed `contentJson` yet.
- Previous baseline (Wave D): 221 tests. Phase 16 added 75 tests.
