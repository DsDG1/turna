# Varnamala

A single-user, local-first Flutter framework for learning languages.

**Current status:** Pre-content engineering phase. The framework (course model, SRS, mistake log, grammar review, dark mode, study stats) is implemented; the only seeded target is **Swahili** (Kannada data is held over as a placeholder until real Swahili content is authored). No social features, no leaderboards, no cloud sync.

**Roadmap:** See [`future2.md`](./future2.md) — the only source of truth for post-2026-07-09 work. The older [`dreamplan.md`](./dreamplan.md) is kept for historical reference only.

---

## What's in the box

- **Course engine** — `Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage / Stage → Interaction` (freezed models, JSON-serializable).
- **11 interaction types** — `showWord`, `multipleChoice`, `fillBlank`, `translateSentence`, `listenAndPick`, `typeTheWord`, `listenOnly`, `reorderSentence`, `readingMcq`, `readingTrueFalse`, `readingShortAnswer`. Each ships as a plugin-style `@injectable` `InteractionRenderer`.
- **6 lesson templates** — `intro`, `practice`, `listening`, `reading`, `review`, `mastery`, plus a `legacy` fallback. The `Lesson.flattenedStages` switch normalises every shape into a single `List<Stage>` the renderer walks.
- **Per-section content loading** — `index.json` + per-section JSON under `assets/courses/swahili/`, cached in a drift SQLite database (schemaVersion 4) with content-version reseed.
- **SRS** — SM-2 spaced-repetition for vocabulary, plus a parallel queue for grammar points. Cards show "Learned in: <lesson name>" via `LessonLinkStore`.
- **Mistake log** — 30-entry FIFO, snapshots the original interaction, supports rewrite-to-clear and cross-routing to grammar review.
- **Grammar review** — independent SRS queue, explain → practice → rate flow, `practiceItems` reuses the same interaction renderers.
- **TTS** — `AudioController` routes every speech path through `flutter_tts` keyed by `TargetLanguage.ttsLanguageCode`; offline audio fallback hook is in place but the audio asset pack is empty.
- **Dark mode + light mode** — semantic `VarnamalaTheme.*(context)` colour helpers; `ThemeProvider` persists `light | dark | system`.
- **Study stats dashboard** — 90-day rolling `StudyLog`, 7-day XP trend, total minutes, accuracy, lessons / reviews done.
- **Match Madness** — small word-matching mini-game wired to the same vocabulary pool.

## What's deliberately not in the box

Per `future2.md` §1 / §6, the following are **out of scope** and removed from the code path:

- League / leaderboard / friends / share / follow / patreon
- Hearts / streak repair (XP-counter) / shop power-ups
- Speaking interactions
- Cloud CMS, Firebase content backend, push notifications
- New course content (vocab / grammar / lessons / passages / audio)

## Project layout

```
lib/
├── application/   # Providers: Course, Lesson, SRS, Mistake, Grammar, Game, Study, ...
├── core/          # enums, sm2, spacing, text styles, logger
├── courses/       # alphabet + per-language loaders (Swahili in production; Kannada placeholder vocab)
├── data/          # drift CourseDatabase + Seeder + Repository
├── di/            # GetIt + Injectable (see renderer_module.dart for InteractionRenderer set)
├── domain/        # section / unit / lesson / stage / interaction / sub_lesson / listening_phase /
│                  # reading_passage / expression / grammar_point / lesson_word_link /
│                  # srs_word / mistake_entry / lesson_content
├── routing/       # auto_route configuration
├── service/       # AppPrefs (StreamingSharedPreferences) + locator wiring
└── views/         # UI: courses, lesson, play, review, profile, splash, onboarding, ...
```

## Build & run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed / json_serializable / drift / injectable
flutter run                                                # device or simulator
```

The course database (`course.swahili.db`) is created on first launch from the bundled JSON assets; subsequent starts reuse the cache. To force a reseed, bump `assets/courses/swahili/index.json` `version` (handled automatically) or clear app data.

## Tests

```bash
flutter test
```

Coverage lives in `test/`:
- `application/` — `SrsProvider`, `GrammarReviewProvider`, `CourseProvider`, `LanguageProvider`, provider identity.
- `courses/` — Swahili / Kannada loader round-trips.
- `domain/` — `MistakeEntry` grammar link, `LessonWordLink` upsert.
- `views/lesson/` — renderer lookup, interaction id stability.

The coverage target after `future2.md` Phase 11 is **≥ 70 % in `lib/application`**, **≥ 50 % in `lib/views/lesson`**.

## Documentation

- [`future2.md`](./future2.md) — current roadmap, 38施工 steps, scope policy.
- [`dreamplan.md`](./dreamplan.md) — superseded v1 plan, kept for history.
- [`CLAUDE.md`](./CLAUDE.md) — agent-facing architecture notes.
- [`IMPLEMENTATION.md`](./IMPLEMENTATION.md) / [`NEXT_VERSION.md`](./NEXT_VERSION.md) / [`plan.md`](./plan.md) — historical, partially superseded.

## Screenshots

| Home | Lesson | Profile | Alphabets |
|:---:|:---:|:---:|:---:|
| ![Home](screenshots/screenshot0.png) | ![Lesson](screenshots/screenshot1.png) | ![Profile](screenshots/screenshot2.png) | ![Alphabets](screenshots/screenshot3.png) |

| Writing | Socials | Leagues and Leaderboard | Games |
|:---:|:---:|:---:|:---:|
| ![Writing](screenshots/screenshot4.png) | ![Socials](screenshots/screenshot5.png) | ![Leagues and Leaderboard](screenshots/screenshot6.png) | ![Games](screenshots/screenshot7.png) |

> Note: the last two columns (`Socials`, `Leagues and Leaderboard`) show features that have been removed by `future2.md`. They are kept here as a visual history of the older design.
