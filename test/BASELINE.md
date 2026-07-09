# Test Baseline

Generated: 2026-07-09 (post-bug-fix regression suite)

## Results
- Passed: 115
- Failed: 0
- Total: 115

## Coverage (flutter test --coverage)
- `lib/application`: TBD
- `lib/views/lesson`: TBD

## Notes
- Pre-bug-fix baseline was 98/98. This run adds 17 new regression tests
  for the bugs fixed during the Phase 12 polish + bug-fix sweep.
- New regression tests:
  - `application/learning_stats_accuracy_test.dart` — B1 (Overall Accuracy
    formatting). Asserts 0.75 → "75%".
  - `application/study_stats_random_suffix_test.dart` — B4 (random suffix).
    Asserts 1000 ids are unique and conform to `[a-z0-9]{6}`.
  - `application/study_stats_weak_words_test.dart` — B5 (weak-words parses
    MistakeEntry log and aggregates by wordId).
  - `application/mastery_dialog_stats_test.dart` — B2 (mastery dialog uses
    real `correctAnswers` / `totalInteractionCount`).
  - `domain/interaction_listen_only_label_test.dart` — B7 (ListenOnly returns
    null instead of leaking audioAsset path).
  - `application/race_condition_test.dart` — C2, C3 (write-queue serialization
    on GemsProvider + StudyLogRepository).
  - `application/achievements_provider_test.dart` — C4 (achievement gem bonus
    routes through GemsProvider; falls back gracefully otherwise).
