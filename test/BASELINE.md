# Test Baseline

Generated: 2026-07-10 (Wave D package rename + LocalUser + lint/deps)

## Results
- Passed: 221
- Failed: 0
- Total: 221
- `flutter analyze`: No issues found

## Coverage (flutter test --coverage)
- `lib/application`: TBD
- `lib/views/lesson`: TBD

## Notes
- Wave D:
  - Pub package renamed `words625` → `varnamala` (all Dart imports).
  - App widget `VarnamalaApp`; Android id `com.example.varnamala`;
    display names Varnamala on Android/iOS/web.
  - `SerializableFirebaseUser` → `LocalUser` (class rename, JSON shape
    unchanged for prefs compatibility).
  - Deps: dropped unused `http` / `equatable` / `flutter_svg`; moved
    `freezed` + `json_serializable` to `dev_dependencies`.
  - Lint: exclude generated sources; enable `avoid_print`,
    `cancel_subscriptions`, `close_sinks`, `unnecessary_late`,
    `prefer_const_declarations`.
- Wave C: typed `UserGameState`, `LessonCompletionCoordinator`, settings/lesson
  splits, dark-mode audit.
- Wave A: ThemeProvider singleton, FakeAudioController, dead Explore/Shop.
