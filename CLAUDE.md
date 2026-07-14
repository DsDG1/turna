# Varnamala - Language Learning App

> 当前状态：future4 框架已完成，并完成 Swahili→Turkish 迁移（ADR 0020）。真实 Turkish 内容已填充 Section 1 问候语单元（8 词 + 2 表达），Sections 2–8 仍为占位。最新内容清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)，决策记录见 [`docs/decisions/`](./docs/decisions/)。

## Project Overview

**Varnamala** is a Flutter-based, local-first language learning framework. Currently focused on **Turkish** as the primary target language. Ships 8 CEFR-graded sections (A1→B2) with inter-section prerequisites; Section 1 contains a real greetings lesson (8 vocab words + 2 expressions), while Sections 2–8 are metadata-only placeholders awaiting content authoring (see ADR 0020 and `docs/content_inventory_current.md`). The app follows a clean architecture pattern and is entirely offline — no Firebase backend, no social features, no pay-to-win mechanics.

---

## Architecture

### Layer Structure
```
lib/
├── application/       # State management (Providers)
│   ├── srs_provider.dart              # SM-2 spaced repetition (SrsQueueProvider subclass)
│   ├── grammar_review_provider.dart   # Grammar SRS queue (SrsQueueProvider subclass)
│   ├── srs_queue_provider.dart        # Shared base class for SRS queues
│   ├── mistake_provider.dart          # FIFO mistake log
│   ├── study_stats_provider.dart      # Learning statistics aggregation
│   ├── score_provider.dart            # XP / score
│   ├── streak_provider.dart           # Streak tracking
│   ├── lesson_progress_provider.dart  # Completed / perfect lesson ids
│   ├── game_milestone_provider.dart   # Achievement / gem milestones
│   ├── game_provider.dart             # Thin facade forwarding to the providers above
│   ├── weak_word_quiz_assembler.dart  # Build weak-word review lesson
│   └── ...
├── core/              # Enums, extensions, utilities, pure functions
│   └── streak_resolver.dart           # Pure streak resolution logic
├── courses/           # Language course data
│   ├── alphabets/     # Alphabet learning content
│   ├── course_loader.dart
│   ├── course_validator.dart
│   └── languages/     # Language-specific course files
├── data/              # Repository implementations
│   ├── course_repository.dart         # implements ICourseRepository
│   └── study_log_repository.dart      # implements IStudyLogRepository
├── di/                # Dependency injection (GetIt + Injectable)
├── domain/            # Domain models + repository interfaces
│   ├── course/        # section, unit, lesson, stage, interaction,
│   │                  # sub_lesson, listening_phase, expression,
│   │                  # grammar_point, reading_passage, srs_word, mistake_entry
│   ├── audio/         # VocabAudioResolver abstraction
│   └── repositories/  # ICourseRepository, IStudyLogRepository
├── routing/           # Auto Route configuration + CourseReadyGuard
├── service/           # App services (Preferences, locator, TTS)
└── views/             # UI layer organized by feature
    ├── courses/       # Course tree
    ├── dictionary/    # Dictionary / search page
    ├── home/          # Bottom navigation / home shell
    ├── lesson/        # Lesson player + interaction renderers
    ├── play/          # Play hub (Match Madness, SRS Review, Mistakes, Weak Words)
    ├── profile/       # User profile + settings (reminder, theme, sound)
    ├── review/        # SRS review + mistake list + weak-word review
    ├── theme.dart     # VarnamalaTheme: light/dark ThemeData + semantic color helpers
    └── weak_words/    # Weak-word review UI
```

### Key Patterns
- **State Management**: Provider + ChangeNotifier
- **Dependency Injection**: GetIt with Injectable annotations
- **Routing**: Auto Route with code generation + `CourseReadyGuard`
- **Models**: Freezed for immutable data classes with JSON serialization
- **Repositories**: Interface + concrete implementation; DB-as-derived-cache

---

## Duolingo Features - Implementation Status

### ✅ Currently Implemented
- [x] Course tree with progressive levels
- [x] Multiple choice questions
- [x] Translation exercises
- [x] Fill-in-the-blank
- [x] Listening exercises (ListenAndPick / TypeTheWord using TTS)
- [x] Reading exercises (ReadingMCQ / ReadingTrueFalse / ReadingShortAnswer)
- [x] XP scoring system
- [x] Basic streak tracking
- [x] SRS engine (SM-2) + review UI
- [x] Mistake tracking with FIFO log + review list
- [x] Match Madness word-matching mini-game
- [x] Multi-language framework support (target language currently Turkish)
- [x] Content model extended for sub-lessons, listening phases, expressions, grammar points, reading passages
- [x] **Dark Mode** — full light/dark/system theme support with persistent preference, semantic color helpers, and theme-aware widget backgrounds
- [x] **Learning Statistics Dashboard** — daily/weekly XP trends, study time tracking, accuracy metrics, weak-word analysis (Profile page)
- [x] **Dictionary / Search** — search vocab, expressions, and grammar points; play audio via `VocabAudioResolver`
- [x] **Weak-word Review** — 10-question mini-quiz built from recent mistakes (30d / ≥2 errors)
- [x] **Local Daily Reminder** — `flutter_local_notifications` with time picker, no streak repair
- [x] **Course Tree State** — completed / weak / due badges on unit cards
- [x] **Content Update Prompt** — detect built-in course version changes and offer progress reset
- [x] **Accessibility** — icon button tooltips, MCQ screen-reader semantics, input semantics, contrast-aware colors
- [x] **Release Pipeline** — `tool/build_release.py` produces versioned APK/AAB/web artifacts + content inventory

### ❌ Removed / Will Not Do
- [ ] ~~Google Authentication~~ — Removed (local-only user)
- [ ] ~~Leaderboard (top 30 users)~~ — Removed (no social features)
- [ ] ~~Shop UI (streak freeze, power-ups, outfits)~~ — Removed (no monetization)
- [ ] ~~Leagues/Tiers~~ — Removed (no social gamification)
- [ ] ~~XP boost multipliers / Daily XP goals~~ — Removed
- [ ] ~~Streak freeze / Weekend amulet / Streak repair with gems~~ — Removed
- [ ] ~~Hearts/Lives System~~ — Removed (no friction on learning)
- [ ] ~~Gems purchase / Power-ups~~ — Removed
- [ ] ~~Friends System~~ — Removed (no social features)
- [ ] ~~Social achievements~~ — Removed
- [ ] ~~Push notifications~~ — Removed (no backend)
- [ ] ~~Speaking exercises~~ — Removed (TTS route sufficient)
- [ ] ~~External GUI editor~~ — Removed (JSON-first approach)

### ✅ Completed framework milestones
- [x] **Lesson Templates** — intro / practice / review / mastery / reading smoke lessons implemented and verified
- [x] **Expression-level SRS** — end-to-end data pipeline (schema v5, seeder, repository, provider, review UI)
- [x] **TTS language code** — switched to `tr` (Turkish) per ADR 0020 (supersedes the old `sw` decision in ADR 0001)
- [x] **Test coverage** — core ViewModel / Provider / Renderer / seeder / schema migration tests
- [x] **System / Google TTS** — `flutter_tts` with language code `'tr'` (Android prefers `com.google.android.tts`). No bundled offline model in this build — the Piper Swahili model and `sherpa_onnx` dependency were removed (ADR 0020). Pre-recorded `audioAsset` reserved for listening exercises.
- [x] **future4 framework round** — DI consolidation, audio/content decoupling, performance fixes, repository interfaces, SRS queue base class, GameProvider split with facade, integration tests, golden baselines, release pipeline (see ADR 0018 and ADRs 0009–0018)

### 📋 Next Round
- [ ] **Content authoring** — Fill Sections 2–8 with real Turkish vocabulary, expressions, grammar points, listening phases, and reading passages. The framework ships **8 sections** (CEFR A1→B2, inter-section prerequisites wired) with a real **intro greetings lesson** in Section 1 (`s1-l2`: 8 vocab + 2 expressions, 3 subLessons). Sections 2–8 currently contain one placeholder unit/legacy MCQ lesson each (see ADR 0020 and `docs/content_inventory_current.md`).

---

## UI Theming Guidelines

### VarnamalaTheme (lib/views/theme.dart)

The app uses a single `VarnamalaTheme` class that provides both `lightTheme` and `darkTheme` `ThemeData` getters, plus a suite of **semantic color helpers** that adapt to the current `Brightness` via `BuildContext`:

```dart
// Theme-aware helpers — use these instead of hard-coded Colors.white
static Color cardBg(BuildContext context)
static Color scaffoldBg(BuildContext context)
static Color dividerBg(BuildContext context)
static Color textHintColor(BuildContext context)
static Color inputFillColor(BuildContext context)
static Color statCardBorder(BuildContext context)
static Color bottomNavBg(BuildContext context)
static Color streakChipBg(BuildContext context)
static Color scoreChipBg(BuildContext context)
// ... and more
```

### Color Palette (Peacock-inspired, distinct from Duolingo)

```dart
// Primary: Teal/Cyan
const primaryColor = Color(0xFF1F727E);
const primaryLight = Color(0xFF359CBB);
const primaryDark = Color(0xFF145A64);

// Accent / Secondary
const secondary = Color(0xFF46D1BF);
const secondaryLight = Color(0xFF00FFC6);

// Semantic
const error = Color(0xFFE74C3C);
const success = Color(0xFFFFD93D);
const warning = Color(0xFFFF9F43);

// League Colors (Jewel Tones)
const amethystLeague = Color(0xFF9B59B6);
const pearlLeague = Color(0xFFF5F5F5);
const rubyLeague = Color(0xFFE74C3C);
const emeraldLeague = Color(0xFF27AE60);
const diamondLeague = Color(0xFF3498DB);
```

### Theme Switching

- `ThemeProvider` (ChangeNotifier) manages `ThemeMode.light / dark / system`
- Preference persisted to `StreamingSharedPreferences` (`settings.themeMode`)
- `PlatformDispatcher.platformBrightness` used when `system` mode is active
- Toggle available in Profile page (AccountWidget popup menu)
- `MaterialApp.router` receives both `theme` and `darkTheme`

---

## Course Data Structure

### Question Types
```dart
enum QuestionType {
  multipleChoice,    // Choose correct translation
  translate,         // Translate sentence
  fillBlank,         // Complete the sentence
  matchWords,        // Match pairs
  listening,         // Listen and select
  speaking,          // Speak the phrase (not implemented)
}
```

### Course Format (in assets/courses/turkish/)
Course data is JSON, loaded by `CourseLoader` (`lib/courses/course_loader.dart`)
and seeded into SQLite by `DatabaseSeeder`. See `docs/authoring/course-layout.md`
for the full authoring contract. Minimal `index.json` shape:
```dart
{
  "version": 5,
  "language": "tr",
  "displayName": "Turkish",
  "sections": [
    { "id": "section1", "name": "Section 1", "level": "A1",
      "prerequisiteSectionIds": [], "file": "sections/section1.json" }
  ]
}
```
Each section file holds `units → lessons → content` (stages / subLessons /
listeningPhases / readingPassage). Interaction variants are discriminated by
`runtimeType` (see `lib/domain/course/interaction.dart`).

---

## Development Commands

```bash
# Install dependencies (generated code is committed, so build_runner is not required for a fresh clone)
flutter pub get

# Run app
flutter run

# Generate code (only needed after changing @freezed / @JsonSerializable / @AutoRoute / @injectable annotations)
flutter pub run build_runner build --delete-conflicting-outputs

# Run on specific device
flutter run -d chrome
flutter run -d ios
flutter run -d android

# Clean build
flutter clean && flutter pub get && flutter pub run build_runner build --delete-conflicting-outputs

# Run tests
flutter test
flutter analyze

# Run Python tool tests
python3 -m unittest discover -s test -p "*_test.py"

# Release build (one command)
python3 tool/build_release.py --version 0.4.0-future4
# Or via Makefile
make build-release
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point |
| `lib/views/app.dart` | Root widget with providers |
| `lib/routing/routing.dart` | Auto Route configuration + guards |
| `lib/routing/course_ready_guard.dart` | Redirect to splash until DB seeded |
| `lib/di/injection.dart` | GetIt DI setup |
| `lib/service/locator.dart` | AppPrefs, preferences, TTS setup |
| `lib/application/game_provider.dart` | Thin facade to score/streak/progress/milestone providers |
| `lib/application/score_provider.dart` | XP / score |
| `lib/application/streak_provider.dart` | Streak state |
| `lib/application/lesson_progress_provider.dart` | Completed / perfect lessons |
| `lib/application/game_milestone_provider.dart` | Achievements / gems |
| `lib/application/srs_queue_provider.dart` | Shared SRS queue base class |
| `lib/application/srs_provider.dart` | Vocab SRS queue |
| `lib/application/grammar_review_provider.dart` | Grammar SRS queue |
| `lib/application/mistake_provider.dart` | FIFO mistake log |
| `lib/application/study_stats_provider.dart` | Learning statistics aggregation |
| `lib/application/weak_word_quiz_assembler.dart` | Build weak-word review lesson |
| `lib/core/streak_resolver.dart` | Pure streak resolution |
| `lib/domain/audio/vocab_audio_resolver.dart` | Audio/content decoupling interface |
| `lib/domain/repositories/course_repository.dart` | `ICourseRepository` interface |
| `lib/domain/repositories/study_log_repository.dart` | `IStudyLogRepository` interface |
| `lib/data/course_repository.dart` | Concrete course repository |
| `lib/data/study_log_repository.dart` | Concrete study log repository |
| `lib/domain/course/lesson.dart` | Lesson model + LessonTemplate |
| `lib/domain/course/lesson_content.dart` | Lesson content (stages/subLessons/listeningPhases/readingPassage) |
| `lib/views/play/play_hub_screen.dart` | Play hub (Match Madness, SRS Review, Mistakes, Weak Words) |
| `lib/views/review/srs_review_screen.dart` | SRS flashcard review |
| `lib/views/review/mistake_list_page.dart` | Mistake list |
| `lib/views/dictionary/dictionary_page.dart` | Dictionary / search |
| `lib/views/weak_words/weak_words_page.dart` | Weak-word review |
| `lib/views/profile/widgets/learning_stats.dart` | Profile learning statistics dashboard |
| `lib/views/theme.dart` | VarnamalaTheme: light/dark ThemeData + semantic color helpers |
| `tool/build_release.py` | One-command release builder |
| `docs/decisions/0018-future4-completion-and-content-handoff.md` | Completed framework plan |
| `docs/decisions/0020-swahili-to-turkish-pivot.md` | Swahili→Turkish pivot migration plan |
| `test/BASELINE.md` | Latest test baseline |
| `docs/decisions/` | Architecture Decision Records (0001–0020) |

---

## Agents Available

### Flutter/Firebase Expert
Location: `.claude/agents/FLUTTER_FIREBASE_EXPERT.md`
- Architecture guidance
- Firebase implementation
- State management patterns
- Performance optimization

### Course Generator Agent
Location: `.claude/agents/COURSE_GENERATOR_AGENT.md`
- Generate new language courses
- Create question sets
- Validate course structure
- Subject matter expertise for languages

---

## Contributing

1. Follow existing code patterns
2. Run `build_runner` after model changes
3. Run `flutter test` and `flutter analyze` before committing
4. Update `test/BASELINE.md` when the test count changes
5. Use the theming guidelines for UI consistency
6. For architectural decisions, add an ADR to `docs/decisions/`
