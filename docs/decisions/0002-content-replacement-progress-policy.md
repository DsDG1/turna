# ADR 0002: Content Replacement Progress Policy

- **Status**: Accepted
- **Date**: 2026-07-10
- **Related**: `future3.md` Phase 13, Phase 20

## Context

Varnamala is currently in a transitional state: the course is labeled "Swahili" and its grammar points are real Swahili, but `vocab.json` still contains Kannada placeholder words (`Naanu`, `Neenu`, `Howdu`, etc.). `future3.md` Phase 20 will perform a full replacement of these placeholders with real Swahili vocabulary.

When the underlying word inventory changes, user progress records (completed lessons, SRS intervals, mistake log entries) may no longer make semantic sense. For example:

- A user may have "learned" the word `w-naanu` (Kannada for "I"), but after replacement the same `wordId` will point to `w-mimi` (Swahili for "I").
- Lesson texts, MCQ options, and fill-in-the-blank answers will change language entirely.
- Mistake log entries may reference words whose translations have changed.

We need a policy for how the app behaves when a content version bump occurs after such a large-scale replacement.

## Decision

When the bundled course `version` increases and the app detects existing user progress, it will show a single non-blocking dialog at startup with the following choices:

1. **Reset progress** — Clear all completed lesson IDs, perfect lesson IDs, SRS cards, study stats, and mistake log entries. Start fresh with the new Swahili content.
2. **Keep progress** — Preserve completed lesson IDs and other records. The user continues from where they left off, but some previously completed lessons may now contain new words/phrases.

The dialog will include a brief explanation: "The Swahili course has been updated with new words and lessons. You can start over or continue with your current progress."

## Consequences

### Reset progress

- **Pros**: Clean slate; SRS intervals and mistake logs are semantically consistent with the new content; avoids confusion from Kannada remnants.
- **Cons**: Users lose their streak/lesson completion history; may feel punitive if they have invested significant time.

### Keep progress

- **Pros**: Respects user time investment; no forced restart.
- **Cons**: SRS cards may reference old Kannada terms; mistake logs may point to changed translations; some lessons marked "completed" will show new content on revisit.

### Implementation notes

- The dialog is shown only once per content version bump.
- The default selection is "Keep progress" (non-destructive).
- The choice is persisted so the dialog does not reappear on subsequent launches.
- This policy applies to the Kannada → Swahili replacement in Phase 20 and to any future major content version changes.
- The `SettingsPage` already provides a manual "Reset lesson progress" action (added in the future3 pre-work), so users can reset later even if they choose "Keep progress" initially.

## Alternatives considered

- **Silently reset everyone**: Simplest for data consistency, but disrespectful to active users.
- **Migrate progress word-by-word**: Attempt to map old SRS cards to new Swahili words using `migration/vocab_map.json`. Rejected because the Kannada → Swahili change is a full language swap, not a 1:1 content update; semantic migration is unreliable and could create confusing cards.
- **Keep progress silently with no prompt**: Avoids friction but leaves users with inconsistent data and no awareness that the course changed.

## Related code

- `lib/application/game_provider.dart` — `resetLessonProgress()`
- `lib/application/course_provider.dart` — content version detection
- `lib/views/settings/settings_page.dart` — manual reset action
- `migration/vocab_map.json` — mapping table driving the replacement

## Phase 17 implementation notes

The prompt was wired up in future4 Phase 17 (does not require new content —
the version format change itself is the trigger):

- **Detection**: `CourseRepository.contentVersion()` reads the stored
  `contentVersion` meta (the composite `index+expressions` version written by
  `DatabaseSeeder`, see ADR 0009). The trigger compares it to
  `LocalStateKeys.contentVersionAcknowledged`.
- **Trigger point**: `HomePage._maybePromptContentUpdate`, run post-frame in
  `initSession` after the streak check. The dialog is shown only when the user
  has existing progress (`GameProvider.completedLessonIds` non-empty); fresh
  installs silently acknowledge and never see the dialog.
- **Dialog**: `ContentUpdateDialog` (`lib/views/content_update/`), `barrierDismissible: false`, returns a typed `ContentUpdateChoice` — "Keep progress" (default) / "Reset progress".
- **Reset action** (the "Reset progress" choice) clears:
  `GameProvider.resetLessonProgress()`, `MistakeProvider.clear()`,
  `StudyLogRepository.clearAll()`, and the new `SrsProvider.clear()` /
  `GrammarReviewProvider.clear()` (the SRS queues had no reset method before
  Phase 17).
- **Persistence**: on either choice, `contentVersionAcknowledged` is set to
  the current stored version so the dialog does not recur for the same
  version.
- Existing installs upgrading past Phase 17 see a one-time reseed (their meta
  is the old single-component `"5"`, which differs from the new `"5+1"`),
  which is exactly what makes the prompt fire for users with progress.
