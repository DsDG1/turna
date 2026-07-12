# ADR 0019: Section Tree (L1) vs Lesson Body (L2) Loading

- **Status**: Accepted
- **Date**: 2026-07-12
- **Related**: course scale (~9300 lessons), GUI authoring contract, ADRs 0002, 0011

## Context

Target content size is on the order of **8 sections**, up to **60 units/section**,
~**30 lessons/unit** (hard ceiling **40**), peak **~1800 lessons/section**,
**~9300 lessons** course-wide.

The previous runtime path loaded a full section including every
`lesson_contents` blob, ran deep `validateSection`, and used
`lessonId.isIn(...)` which hits SQLite’s ~999 bind-variable limit above that
scale.

A future local GUI editor must export the same JSON layout without writing
SQLite directly.

## Decision

### Runtime load layers

| Layer | API | Payload |
|-------|-----|---------|
| L0 | `sectionShells()` / `SwahiliCourse.load()` | Section index + vocab/grammar/expressions |
| L1 | `CourseRepository.section` / `loadSection` | Units + lesson **metadata** only (`content` empty) |
| L2 | `lessonById` / `loadLessonById` | Full `LessonContent` for one lesson |

- L1 lessons query uses a **join on `sectionId`** (single bind), not a giant `IN`.
- Runtime L1 validation is `validateSectionTree` (ids + uniqueness + scale).
- Deep content validation remains **seed / CI** (`validateSwahiliCourse`).
- Lesson bodies are cached with an **LRU cap** (`SwahiliCourse.lessonBodyCacheCap = 48`).
- `LessonViewModel.loadLesson` uses provider cache only when the lesson already
  has body content; empty tree metadata always falls through to L2.
- `selectUnit` / `selectLesson` resolve the owning section via reverse lookup
  and load **only that** L1 tree.

### Scale contract

- `kMaxUnitsPerSection = 60`
- `kMaxLessonsPerUnit = 40`

Enforced in Dart (`course_validator.dart` / seeder) and Python
(`tool/course_cli.py`).

### Authoring / GUI boundary

- **JSON under `assets/courses/<lang>/` is source of truth**; DB is derived cache.
- GUI (future) reads/writes per-section files + `index.json`; spawns
  `python3 tool/course_cli.py validate [--format json]`.
- GUI must **not** write `CourseDatabase` or depend on Freezed as sole schema.
- Content changes **bump** `index.json` / `expressions.json` versions (ADR 0002).
- Lesson **ids are immutable** once shipped (progress / links).

### UI

- Course tree: units default collapsed; **accordion** (one expanded unit).
- Due/weak badges: O(due∪weak words) via `LessonLinkStore.linkFor`, not full
  link-table scan.

### Seed

- Per-section parse → cross-id check against running sets → write transaction
  → drop section graph (streaming seed for peak memory).

## Consequences

- Opening a large section stays metadata-bound; entering a lesson pays one
  content decode.
- Tests that expected full content on `section()` / `loadSection` must use
  `lessonById` for body assertions.
- Authoring tooling and App share the same disk layout and validate entrypoint.

## Alternatives considered

- **Keep full-section content load**: fails hard above ~999 lessons and is too
  slow/memory-heavy at 1800.
- **GUI writes SQLite**: couples editor to schema/migrations; breaks versioned
  reseed and Git workflow.
- **Monolithic course JSON**: bad for Git diffs and multi-author section work.
