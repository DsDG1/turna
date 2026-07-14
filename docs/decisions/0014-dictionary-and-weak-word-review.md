# ADR 0014: Dictionary and weak-word review

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 22

## Context

Learners need offline search over bundled vocab/expressions/grammar and a
focused drill for words they keep missing.

## Decision

### Dictionary

- Route: `DictionaryPage` / `DictionaryRoute` (guarded by `CourseReadyGuard`).
- Search is a pure function over in-memory maps (`searchDictionary`).
- Playback via `AudioController.speakWord` / `speak`.

### Weak words

| Rule | Value |
|---|---|
| Window | Last **30** days |
| Threshold | Same `wordId` missed **≥ 2** times |
| Cap | **10** quiz items |
| Grammar-only mistakes | Excluded from word quiz |

Assembler: `WeakWordQuizAssembler` → synthetic `Lesson` of MCQs (term →
translation) reusing `LessonViewModel`.

### Local reminder

- Optional daily local notification; mild copy only.
- Prefs: `dailyReminderEnabled`, hour/minute on `SettingsProvider`.
- `LocalReminderService` schedules via `flutter_local_notifications`.

## Consequences

- No new content required for verification.
- Play hub exposes Dictionary + Weak Words cards.
