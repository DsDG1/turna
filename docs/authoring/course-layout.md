# Course layout & authoring contract

This document is the **source-of-truth contract** for humans, CLI, CI, and a
future local GUI course editor. The Flutter app never treats the SQLite cache
as authoritative.

## Directory layout

```text
assets/courses/<lang>/
  index.json                 # version, language, section shells + file pointers
  vocab.json                 # words[]
  expressions.json           # version, expressions[]
  grammar_points.json        # grammarPoints[]
  sections/
    section1.json            # full section: units → lessons → content
    ...
```

Swahili default: `assets/courses/swahili/`.

### `index.json`

- `version` (int): bump on any semantic course change that should reseed.
- `sections[]`: `{ id, name, description, level?, prerequisiteSectionIds, file }`
- `file` is relative to the course dir (e.g. `sections/section1.json`).

Composite reseed key is `indexVersion+expressionsVersion` (see ADR 0002).

### Section file

- Top-level: `{ id, name, description?, units: [...] }`
- Unit: `{ id, name, description?, lessons: [...] }`
- Lesson: `{ id, name, type, template, content, ... }`
- Prefer **canonical** content shapes (`stages` / `subLessons` / `listeningPhases`).
  Flat `questions` is still normalized at seed time, but new authoring should
  write canonical shapes.

## Scale contract

| Limit | Value | Where enforced |
|-------|------:|----------------|
| Units per section | ≤ 60 | Dart + `course_cli validate` + seeder |
| Lessons per unit | ≤ 40 | same (production target ≈ 30) |

Soft production layout for 8 sections may use unit counts like
10 / 30 / 30 / 60 / 50 / 50 / 40 / 40 with ~30 lessons each (~9300 lessons).

## IDs

- **Global uniqueness** for unit ids and lesson ids across the whole course.
- **Immutable after ship**: renaming a lesson changes `name` only, never `id`.
  Changing ids orphans `completedLessonIds` and `LessonWordLink` entries.
- Suggested patterns: `l-{unitSlug}-{n}`, or stable UUIDs; pick one and stick.

## App load model (authors do not reimplement this)

| Layer | What | When |
|-------|------|------|
| L0 | section shells | app start |
| L1 | unit/lesson metadata | open section (tree) |
| L2 | lesson content JSON | open one lesson |

Authors always edit **full** content in the JSON files. The L1/L2 split is a
**runtime** concern only (ADR 0019).

## Validate before commit

```bash
# Human-readable
python3 tool/course_cli.py validate --course-dir assets/courses/swahili

# Machine-readable (GUI / CI)
python3 tool/course_cli.py validate --format json --course-dir assets/courses/swahili

python3 tool/course_cli.py lint --course-dir assets/courses/swahili
```

Exit code `0` = ok; non-zero = errors. JSON shape:

```json
{
  "ok": false,
  "errorCount": 1,
  "problems": [
    { "level": "error", "message": "...", "path": "section:section4/unit:u-1" }
  ]
}
```

Also: `flutter test` runs Dart validators so Python/Dart rules stay aligned.

## Export checklist (GUI or human)

1. Edit only the touched `sections/*.json` (and vocab/expressions/grammar if needed).
2. Run `validate` + `lint`.
3. **Bump** `index.json` `version` (and `expressions.json` version if that file changed).
4. Optional: `python3 tool/export_content_inventory.py` for scale report.
5. Commit; app users reseed via ADR 0002 prompt when the composite version changes.

## Forbidden

- Writing the app SQLite DB from the editor.
- Merging all sections into one giant JSON for “convenience”.
- Auto-renumbering lesson ids on reorder.
- Shipping content that exceeds scale ceilings without raising the constants in
  **both** `lib/courses/course_validator.dart` and `tool/course_cli.py`.

## Templates

Minimal lesson skeletons live in `docs/authoring/templates/`. Clone and fill;
do not invent new `runtimeType` values without adding a Dart `Interaction` case.
