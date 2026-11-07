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

Default target: the directory named by `assets/courses/manifest.json` for the
language (currently `assets/courses/nouveau-turkish/` for `tr`). `--course-dir`
overrides it; every path below is relative to that course directory, not to the
repository root.

### `index.json`

- `version` (int): 对外内容发布号，由 `tool/publish_course.py` 按已部署 feed 的下一版分配；GUI 定稿不推进它。
- `sections[]`: `{ id, name, description, level?, prerequisiteSectionIds, file }`
- `file` is relative to the course dir (e.g. `sections/section1.json`).

Composite reseed key is `indexVersion+expressionsVersion`.

### Section file

- Top-level: `{ id, name, description?, units: [...] }`
- Unit: `{ id, name, description?, lessons: [...] }`
- Lesson: `{ id, name, type, template, content, ... }`
- Prefer **canonical** content shapes (`stages` / `subLessons` / `listeningPhases`).
  Dialogue lessons additionally use `dialogueScene`; flat review pools may declare
  `reviewPolicy`. Flat `questions` is still normalized at seed time, but new
  authoring should write canonical shapes.

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
**runtime** concern only.

## Validate before commit

```bash
# Human-readable (defaults to the course dir named by the manifest)
python tool/course_cli.py validate

# Machine-readable (GUI / CI)
python tool/course_cli.py validate --format json

python tool/course_cli.py lint
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

1. 修改相关课程 JSON 与资源元数据，不改已发布 ID。
2. 运行 `validate` 与 `lint --strict`；待生成媒体必须先真实交付，不能用占位文件消除警告。
3. 用 `python tool/export_content_inventory.py` 更新内容与质量清单。
4. GUI 执行「定稿」：保存、校验、导出报告，不推进对外版本。
5. 需要交付作者时，用 `python tool/export_author_workspace.py --course-dir <course> --output <workspace>` 导出课程及引用媒体。
6. 生成应用更新包时，由 `python tool/publish_course.py --previous-feed <deployed-feed> --bump --strict` 分配下一 index 版本。媒体随 app 发布，ZIP 仍只含 JSON。
7. 上线时先上传 ZIP，最后更新远端稳定 feed；本地产物不等于远端已发布。

## Forbidden

- Writing the app SQLite DB from the editor.
- Merging all sections into one giant JSON for “convenience”.
- Auto-renumbering lesson ids on reorder.
- Shipping content that exceeds scale ceilings without raising the constants in
  **both** `lib/courses/course_validator.dart` and `tool/course_cli.py`.

## Templates

Minimal lesson skeletons live in `docs/authoring/templates/`. Clone and fill;
do not invent new `runtimeType` values without adding a Dart `Interaction` case.
