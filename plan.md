# Varnamala — Flutter 5-Layer Course Architecture Plan

> ⚠️ **部分实现已被 [`future2.md`](./future2.md) 取代**。本文件保留 5-layer 架构设计历史；prerequisite / derived-unlock 机制不在当前路线图中。

> Status: **in progress** — Phases 1–3 complete, Phases 4–8 pending
> Owner: languagepart
> Last updated: 2026-07

## Context

Varnamala is a Flutter-based Duolingo-style language learning app, currently
single-language (Kannada) and fully offline (no Firebase, no login).

The current course model is a flat 2-layer structure:

```
Course → Level → Question
```

This limits pedagogy: every question in a level shares the same UI shape, there
is no in-lesson grouping (vocab → examples → practice), and no prerequisites
between lessons.

`Reference.md` describes a richer 5-layer architecture originally drafted in
Kotlin/Compose. This plan documents the **Flutter/Dart port** of that design,
adapted to Varnamala's existing patterns (Provider, GetIt+Injectable,
streaming_shared_preferences, Freezed, AutoRoute).

### Goals

| # | Goal | Status |
|---|---|---|
| G1 | 5-layer curriculum: Language → Section → Unit → Lesson (+ Stage) → Interaction | ✅ data models done, UI pending |
| G2 | 7 Interaction types (sealed class) | ✅ data models done, renderers pending |
| G3 | 4-level prerequisites + derived unlock | ⏳ Phase 6 |
| G4 | SM-2 spaced-repetition word review | ✅ SrsProvider done, UI pending |
| G5 | Backwards-compatible with existing lesson data | ✅ legacy `getKannadaData` retained |
| G6 | Plugin-style renderer lookup (Dart 3 sealed + injectable Set) | ⏳ Phase 4 |

---

## Architecture

### 1. Domain model (Dart 3 sealed + Freezed)

```
Section
  ├── units: List<Unit>
  │     └── lessons: List<Lesson>
  │           ├── type: LessonType    (normal / listening / reading / review / challenge)
  │           └── content: LessonContent (sealed, matches type 1:1)
  │                 ├── NormalContent    → List<Stage>            (items: List<Interaction>)
  │                 ├── ListeningContent → List<Stage> + audioAsset
  │                 ├── ReadingContent   → List<ReadingStage>    (items: List<ReadingQuestion>)
  │                 ├── ReviewContent    → List<Stage>
  │                 └── ChallengeContent → List<Stage>
```

Each `Stage` groups interactions pedagogically (vocab intro / examples /
practice). Each `Lesson` has `prerequisiteLessonIds`; each `Unit` has
`prerequisiteUnitIds`; each `Section` has `prerequisiteSectionIds`. Each
`Stage` has `prerequisiteStageIds`.

Completion rules (all-of at every layer):

| Entity | Complete when |
|---|---|
| Stage | all its items answered correctly |
| Lesson | all its stages complete |
| Unit | all its lessons complete |
| Section | all its units complete |

Unlocks are **derived** from prereqs + completion — not persisted.

### 2. Interaction sealed class (7 variants)

```
sealed class Interaction
  ├── ShowWord           (wordId, context?)
  ├── MultipleChoice     (prompt, options, correctIndex, imageAsset?)
  ├── FillBlank          (sentence, answer, hint?)
  ├── TranslateSentence  (source, expected, hints)
  ├── ListenAndPick      (audioAsset, prompt, options, correctIndex)
  ├── TypeTheWord        (audioAsset, prompt, expected)
  └── ReorderSentence    (scrambled, correct)
```

`ReadingQuestion` is a separate sealed class used only by `ReadingContent`:

```
sealed class ReadingQuestion
  ├── ReadingMcq
  ├── ReadingTrueFalse
  └── ReadingShortAnswer
```

### 3. SRS word pool

`WordEntry` (immutable vocab record) decoupled from lessons. `SrsWord` carries
per-word SM-2 state (`dueAt`, `intervalDays`, `ease`, `reps`, `lapses`,
`isLeech`).

SM-2 algorithm:

```
quality 0..2 → reset reps=0, lapses+=1, interval=1
quality 3..5 → reps+=1
               reps==1: interval=1
               reps==2: interval=6
               else:    interval = round(prev_interval * ease)
ease += 0.1 - (5-q)*(0.08 + (5-q)*0.02), floored at 1.3
dueAt  = now + interval days
isLeech = lapses >= 5 && lapses > reps
```

Review UI uses a 4-button mapping:

| Button | SM-2 quality |
|---|---|
| Again | 1 |
| Hard | 3 |
| Good | 4 |
| Easy | 5 |

### 4. Renderer plugin architecture (mirrors Hilt `@IntoSet`)

```dart
abstract class InteractionRenderer {
  Type get handlesType;
  Widget render(Interaction interaction, InteractionState state,
                void Function(bool correct) onComplete);
}
```

Each renderer is `@injectable`. A `LessonScreenViewModel` receives a
`Set<InteractionRenderer>` via `getIt<Set<InteractionRenderer>>()` and looks up
by `interaction.runtimeType`. New types = 1 new renderer class + 1 line in the
injectable set.

### 5. Persistence (streaming_shared_preferences)

| Key | Value | Notes |
|---|---|---|
| `srs.state` | JSON `Map<wordId, SrsWord>` | Updated on every review |
| `progress.completedStages` | JSON `List<String>` of stage ids | Phase 6 |
| `progress.completedLessons` | JSON `List<String>` of lesson ids | Phase 6 |
| `progress.completedUnits` | JSON `List<String>` | Phase 6 |
| `progress.completedSections` | JSON `List<String>` | Phase 6 |

Unlocks are derived on the fly from prereqs + completion — no separate unlock
store needed.

### 6. Data flow

```
HomePage (CourseTree)
  └─► CourseTreeScreen (5-layer foldable)
       └─► tap Section → expand/collapse
       └─► tap Lesson → if unlocked → LessonContentScreen
                                          └─► LessonViewModel (state machine)
                                               ├─ currentStageIdx
                                               ├─ currentItemIdx
                                               └─ completedItems: Set<String>

LessonContentScreen
  └─► switch (lesson.type)
       ├─ normal     → NormalContentBody
       ├─ listening  → ListeningContentBody
       ├─ reading    → ReadingContentBody
       ├─ review     → ReviewContentBody
       └─ challenge  → ChallengeContentBody

Each Body:
  Stage header (e.g. "Stage 2/5: Practice")
  current Stage.items.forEach((interaction) {
    final renderer = renderers.firstWhere((r) => r.handlesType == interaction.runtimeType);
    renderer.render(interaction, state, (correct) => viewModel.completeItem(correct));
  });

WordReviewScreen (Phase 7)
  └─► WordReviewViewModel
       ├─ fetch queue from ReviewSource (Due / Mixed / Lapses)
       └─ on quality → srsProvider.reviewWithQuality(wordId, quality) + advance
```

---

## Implementation phases

### ✅ Phase 1 — Domain models + Freezed (done)

**Files** (all under `lib/domain/course/`):

- `section.dart`, `unit.dart`, `lesson.dart`, `lesson_content.dart`
- `stage.dart` (Stage + ReadingStage)
- `interaction.dart` (sealed, 7 variants)
- `reading_question.dart` (sealed, 3 variants)
- `word_entry.dart`, `srs_word.dart`

**Notes**:
- Freezed 2.x doesn't support generics — `Stage<T>` was rejected at
  build time. Workaround: concrete `Stage` holding `List<Interaction>` plus a
  separate `ReadingStage` holding `List<ReadingQuestion>`. Sealed wrapper
  ensures exhaustive dispatch.
- `SrsWord.fresh(wordId)` factory for never-seen words.

### ✅ Phase 2 — SM-2 + SrsProvider (done)

**Files**:
- `lib/core/sm2.dart` — `Sm2Engine.review(word, quality)` + `ReviewQuality` enum
- `lib/application/srs_provider.dart` — `SrsProvider extends ChangeNotifier`
  - `registerWord(id)`, `registerAll(ids)` — idempotent
  - `reviewWord(id, quality)` → `Future<SrsWord?>`
  - `reviewWithQuality(id, ReviewQuality)` — 4-button helper
  - `getDueWords([now])`, `getMixedWords(n)`, `getLapseWords()`
  - `dueCount`, `totalSeen`, `totalRegistered`
  - JSON-encoded Map persisted to `LocalStateKeys.srsState`
- `lib/service/locator.dart` — added `LocalStateKeys.srsState`
- `lib/application/providers.dart` — registered `SrsProvider`

### ✅ Phase 3 — Course data migration (done, partial data)

**Files**:
- `lib/courses/languages/kannada_vocab.dart` — 32 WordEntry across 3 sections
- `lib/courses/languages/kannada.dart` — **rewritten** with 5-layer structure:
  - 3 Sections (Foundations / Daily Life / World Around)
  - 8 Units
  - 11 Lessons spanning all 5 `LessonType` values
  - All 7 `Interaction` variants exercised
  - Legacy `getKannadaData(firstName)` retained as a thin shim returning 1
    minimal course for backward compatibility

**Migration scope**: Phase 3 ships a **representative** 5-layer tree covering
the new architecture. The full ~2400 lines of original course content can be
ported into this structure incrementally — the model layer is ready.

### ⏳ Phase 4 — Interaction renderers (2 days)

**New files** (`lib/views/lesson/components/interactions/`):

- `interaction_renderer.dart` (interface)
- `multiple_choice_renderer.dart`
- `fill_blank_renderer.dart`
- `translate_sentence_renderer.dart`
- `listen_and_pick_renderer.dart` (TTS button)
- `type_the_word_renderer.dart` (TextField + TTS)
- `reorder_sentence_renderer.dart` (Draggable tokens)
- `show_word_renderer.dart` (flashcard intro)

**Modify**:
- `lib/di/injection.dart` — register a `Set<InteractionRenderer>` from all
  `@injectable` renderers (idiomatic Dart substitute for Hilt `@IntoSet`).

Each renderer takes `(Interaction, InteractionState, void Function(bool) onComplete)`
and returns a `Widget`. Stateful widgets hold `selectedAnswer`, `textController`,
etc. internally and call `onComplete(true/false)` when the user submits.

### ⏳ Phase 5 — LessonContentScreen (2 days)

**New files** (`lib/views/lesson/`):

- `lesson_content_screen.dart` — top-level `when (lesson.type)` dispatcher
- `normal_content_body.dart`, `listening_content_body.dart`,
  `reading_content_body.dart`, `review_content_body.dart`,
  `challenge_content_body.dart`
- `lesson_view_model.dart` — state machine
  - state: `{currentStageIdx, currentItemIdx, completedItems: Set<String>}`
  - methods: `init()`, `completeItem(itemId, correct)`, `next()`, `isStageComplete(s)`, `isLessonComplete()`
- `components/stage_header.dart` — "Stage 2/5: Practice" + progress bar

**Modify**:
- `lib/views/lesson/lesson_screen.dart` — wrap new `LessonContentScreen`,
  accept `Lesson` (not `Course`) as constructor arg
- `lib/routing/routing.dart` — `LessonRoute` takes `Lesson` arg

On lesson complete: call `GameProvider.recordLessonCompletion()` + `SrsProvider.registerAll(extractWordIds(lesson))`.

### ⏳ Phase 6 — 5-layer foldable CourseTree (2 days)

**New / rewrite**:
- `lib/views/courses/course_tree.dart` — foldable tree showing
  Section > Unit > Lesson > Stage-summary. Lock badges 🔒 for incomplete prereqs.
  Default-expanded "active path" (find first incomplete leaf).
- `lib/application/progress_provider.dart` — listens to completion prefs,
  produces `SectionProgressView` / `UnitProgressView` / `LessonProgressView`
  / `StageProgressView` derived trees.
- `lib/application/course_provider.dart` — switch to loading `getKannadaSections()`
  instead of `getKannadaData()`.

Completion prefs (added in Phase 2 / extended in Phase 6):
`completedStages`, `completedLessons`, `completedUnits`, `completedSections`
(JSON-encoded `List<String>` in shared_preferences).

### ⏳ Phase 7 — SRS review screen (1 day)

**New files**:
- `lib/domain/review/review_source.dart` — abstract
- `lib/domain/review/due_review_source.dart`, `mixed_review_source.dart`,
  `lapses_review_source.dart`
- `lib/views/review/word_review_screen.dart` — flashcard with 4 quality buttons
- `lib/views/review/word_review_view_model.dart` — pulls queue from source,
  calls `SrsProvider.reviewWithQuality()` on submit
- `lib/di/review_sources.dart` — `Set<ReviewSource>` injection

**Modify**:
- `lib/views/courses/course_tree.dart` — add "Review due (N)" button at top,
  uses `SrsProvider.dueCount`
- `lib/routing/routing.dart` — add `WordReviewRoute(source: 'due' | 'mixed:20' | 'lapses')`

### ⏳ Phase 8 — Cleanup + verification (1 day)

**Delete**:
- `lib/domain/course/course.dart` (old `Course`/`Level`/`Question`)
- `lib/views/lesson/components/grid_lesson.dart`, `list_lesson.dart`
- Old `parseCourses()` in `lib/courses/courses.dart`
- Legacy `getKannadaData()` in `lib/courses/languages/kannada.dart`
  (now that `LessonContentScreen` uses the new structure)

**Modify**:
- `lib/application/game_provider.dart` — `recordLessonCompletion` already
  works; add `recordStageCompletion(stageId)` for finer-grained XP
- `lib/application/character_provider.dart` — unaffected
- `lib/views/courses/course_tree.dart` — replace any remaining legacy hooks
- `lib/routing/routing.dart` — final route cleanup

**Verify**:
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze    # 0 errors
flutter run
```

End-to-end smoke test:
1. Open Course Tree → see 3 Sections, expand "Foundations"
2. Tap "Greetings" → tap "Hello & Yes/No" → Lesson loads
3. Stage 1 (Vocabulary): 4 ShowWord cards
4. Stage 2 (Practice): MultipleChoice → FillBlank → ListenAndPick
5. Stage complete → auto-advance; Lesson complete → back to Tree
6. Tree shows "Hello & Yes/No" with ● done
7. Top of Tree: "Review due (N)" → tap → flashcard review
8. 4 quality buttons → SRS state updates, due count decrements

---

## Reused existing patterns

- **Provider + ChangeNotifier** for SrsProvider, future ProgressProvider
- **GetIt + Injectable** for DI; `@injectable` on renderers and sources
- **streaming_shared_preferences** for SRS state + completion tracking
- **Freezed + json_serializable** for all domain models (already in pubspec)
- **AutoRoute** for `LessonRoute` (already) + new `WordReviewRoute`
- **flutter_tts** for ListenAndPick / TypeTheWord audio
- **existing LocalStateKeys class** — extend with srs/progress keys
- **existing SerializableFirebaseUser** — unchanged (prefs compat)
- **existing GameProvider awardXP / incrementScore** — preserved;
  Stage completion continues to feed XP

---

## Key files

### Created (Phases 1–3, 12 files)

```
lib/domain/course/section.dart
lib/domain/course/unit.dart
lib/domain/course/lesson.dart
lib/domain/course/lesson_content.dart
lib/domain/course/stage.dart
lib/domain/course/interaction.dart
lib/domain/course/reading_question.dart
lib/domain/course/word_entry.dart
lib/domain/course/srs_word.dart
lib/core/sm2.dart
lib/application/srs_provider.dart
lib/courses/languages/kannada_vocab.dart
```

### Rewritten (Phase 3, 1 file)

```
lib/courses/languages/kannada.dart    (legacy data → 5-layer structure)
```

### To create (Phases 4–8, ~28 files)

```
# Phase 4 (8)
lib/views/lesson/components/interactions/interaction_renderer.dart
lib/views/lesson/components/interactions/multiple_choice_renderer.dart
lib/views/lesson/components/interactions/fill_blank_renderer.dart
lib/views/lesson/components/interactions/translate_sentence_renderer.dart
lib/views/lesson/components/interactions/listen_and_pick_renderer.dart
lib/views/lesson/components/interactions/type_the_word_renderer.dart
lib/views/lesson/components/interactions/reorder_sentence_renderer.dart
lib/views/lesson/components/interactions/show_word_renderer.dart

# Phase 5 (8)
lib/views/lesson/lesson_content_screen.dart
lib/views/lesson/normal_content_body.dart
lib/views/lesson/listening_content_body.dart
lib/views/lesson/reading_content_body.dart
lib/views/lesson/review_content_body.dart
lib/views/lesson/challenge_content_body.dart
lib/views/lesson/lesson_view_model.dart
lib/views/lesson/components/stage_header.dart

# Phase 6 (2)
lib/application/progress_provider.dart
(replace) lib/views/courses/course_tree.dart

# Phase 7 (7)
lib/domain/review/review_source.dart
lib/domain/review/due_review_source.dart
lib/domain/review/mixed_review_source.dart
lib/domain/review/lapses_review_source.dart
lib/views/review/word_review_screen.dart
lib/views/review/word_review_view_model.dart
lib/di/review_sources.dart
```

### To modify (Phases 4–8, ~6 files)

```
lib/di/injection.dart                    (register Set<InteractionRenderer>)
lib/routing/routing.dart                  (WordReviewRoute)
lib/views/lesson/lesson_screen.dart       (wrap LessonContentScreen)
lib/application/course_provider.dart      (load Sections)
lib/application/game_provider.dart        (recordStageCompletion)
lib/courses/courses.dart                  (remove parseCourses())
```

### To delete (Phase 8, ~5 files)

```
lib/domain/course/course.dart
lib/views/lesson/components/grid_lesson.dart
lib/views/lesson/components/list_lesson.dart
lib/courses/languages/kannada.dart        (legacy shim section at end)
(legacy getKannadaData in same file)
```

---

## Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Freezed 2.x doesn't support generic `Stage<T>` | Use concrete `Stage` (Interaction items) + `ReadingStage` (ReadingQuestion items) — done |
| R2 | Renderer × Interaction type explosion (7×7 = 49 combos) | Each renderer is one class; new combination = 0 changes if both renderer + interaction exist |
| R3 | Sealed class + JSON polymorphism: `Interaction.fromJson` needs `runtimeType` switch | Freezed's sealed unions handle this automatically via discriminator field |
| R4 | `Stage<T>` generics break kotlinx/json serialization | R1's mitigation |
| R5 | Phase 3 partial data: only 11 of ~50+ planned lessons ported | Phase 8+ can incrementally port old content into the new structure |
| R6 | Lesson-screen rerouting breaks XP / streak awards during refactor | Keep `LessonContentScreen` calling `GameProvider.recordLessonCompletion()` on done |
| R7 | Sealed classes require Dart 3.0+ | Project SDK is `>=3.2.3`, no issue |
| R8 | 5-layer CourseTree render perf with many nodes | Use `SliverList` + lazy build; default-collapse everything except active path |

---

## Verification

### Static
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze    # expected: 0 errors (warnings about pre-existing dupe keys in kannada data OK)
```

### Runtime
```bash
flutter run -d <device>
```

Manual test plan:
1. **Course Tree** — open home, see Sections list; expand "Foundations" → Units → Lessons
2. **Prereq gating** — "Daily Life" lessons show 🔒 until "Foundations" complete
3. **Lesson playback** — tap "Hello & Yes/No", watch Stage 1 (vocab) then Stage 2 (practice)
4. **All 7 interactions render**:
   - ShowWord (flashcard)
   - MultipleChoice (radio buttons)
   - FillBlank (text input in highlighted gap)
   - TranslateSentence (text input)
   - ListenAndPick (TTS play + radio buttons)
   - TypeTheWord (TTS play + text input)
   - ReorderSentence (draggable tokens)
5. **Stage auto-advance** — finish Stage 1 → Stage 2 starts automatically
6. **Lesson complete** — finish Lesson → return to Tree, see ●
7. **SRS review** — "Review due (N)" appears after completing lessons; flashcards with 4 quality buttons; due count decrements
8. **Offline** — disconnect network; all features still work
9. **Persistence** — kill app, reopen; XP, streak, completion, SRS state all preserved

---

## Out of scope (deferred)

- Pre-baked audio assets (`assets/audio/lessons/*.mp3`) — current plan uses
  `flutter_tts` for runtime synthesis
- FSRS algorithm (replacement for SM-2)
- Section/Unit/Lesson reordering UI
- Cloud sync of progress (would require re-introducing Firebase)
- Course import/export (JSON files)
- Audio/Image variants for `ShowWord` (architecture supports; not implemented)
- Translation to other languages (Kannada-only by design)

---

## Related documents

- `Reference.md` — original Kotlin/Compose design study (mostly superseded by
  this plan, but useful background for the interaction taxonomy)
- `CLAUDE.md` — project instructions (architecture overview, Firebase history)
- `IMPLEMENTATION.md` — pre-Firebase gamification plan (legacy)