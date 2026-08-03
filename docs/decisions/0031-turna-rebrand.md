# ADR 0031 — Turna Rebrand (Non-Visual)

- **Status:** Accepted
- **Date:** 2026-08-03
- **Source plan:** `~/Desktop/Turna改名计划.md` (user-authored)
- **Scope:** non-visual renaming only — product copy, Dart package & symbols, native platform identities, desktop/Web/OHOS names, course editor name, docs, compatibility migration.
- **Out of scope:** logo, app icons, launcher images, mascot artwork, `assets/images/mala/*` files, theme colour values, peacock visual tokens.

## Context

The `Varnamalaplus` repository inherits its product name from upstream
`Varnamala`. Every layer — Dart package, native config, desktop launcher,
Web manifest, OHOS bundle, course editor, and docs — still carries
`Varnamala`/`varnamala`/`vernamala` identifiers. The product has not yet
shipped, so this is the last natural window to align identity before a
public release without having to deal with app-store upgrade compatibility.

The work is being driven from an external plan in
`~/Desktop/Turna改名计划.md`. This ADR records the agreed rename
matrix, the migration strategy, and the audit rules so future contributors
can tell "intentional retention" from "missed rename".

## Naming matrix

| Object                        | Current                          | Target                  |
|-------------------------------|----------------------------------|-------------------------|
| User-visible product name     | Varnamala / Varnamala Plus       | **Turna**               |
| Dart package name             | `varnamala`                      | `turna`                 |
| Root Flutter widget           | `VarnamalaApp`                   | `TurnaApp`              |
| Brand theme class             | `VarnamalaTheme`                 | `TurnaTheme`            |
| Android namespace             | `com.varnamala.app`              | `me.dsdogs.turna`       |
| Android `applicationId`       | `com.varnamala.app`              | `me.dsdogs.turna`       |
| iOS / macOS Bundle ID         | `com.example.varnamala`          | `me.dsdogs.turna`       |
| Linux Application ID          | `com.example.varnamala`          | `me.dsdogs.turna`       |
| OHOS Bundle Name              | `me.dsdogs.vernamala`            | `me.dsdogs.turna`       |
| Windows / Linux binary name   | `varnamala`                      | `turna`                 |
| Course editor display name    | Varnamala Course Editor          | Turna Course Editor     |

`peacockTeal`, `peacockCyan`, and the rest of the Peacock palette tokens
stay as-is; visual-token renaming is part of the future visual rework.

## In scope

- User-visible product copy everywhere a user sees the brand.
- Dart package name, import paths, and brand class names.
- Android, iOS, macOS, Windows, Linux, Web, and OHOS application names
  and publishing identities.
- Course editor display name (`tool/gui`).
- Compatibility migration for local settings (QSettings) and config dirs.
- Current README, dev docs, user guides, and non-historical docs.
- Test files, generated code, and build configs — current product name.

## Out of scope

- `assets/images/app_logo*.png`.
- `assets/images/mala/` mascot artwork.
- Android launcher icon, iOS/macOS `AppIcon`, Web icon, Windows ICO,
  OHOS icon.
- iOS `LaunchImage` and other launch imagery.
- Image file paths and image-only fields in `assets.gen.dart`.
- Theme colour values; the Peacock palette overall.
- Course JSON schema, SQLite table names, content IDs.
- Upstream repo name, historical commits, old release facts.

Because icons are untouched, the renamed APK/bundle will still show the
old visual assets in dev. That state is acceptable pre-launch; the
follow-up Turna visual-assets task closes the loop before public release.

## Implementation principles

1. Baseline before mechanical search-replace.
2. User-visible copy and technical identity land in separate stages so
   build errors stay localised.
3. Generated files are owned by the generator — never hand-edit them.
4. Upstream / old releases stay named *Varnamala*; we don't rewrite history.
5. Old local configs are read-compatible, with a one-shot migration to the
   new namespace; old config is not auto-deleted.
6. Each stage lands as its own commit so reverts stay narrow.

## Execution stages

| # | Stage | Anchor commit message | Key files |
|---|-------|------------------------|-----------|
| 1 | Baseline | (no commit, snapshot only) | `git status --short`; `flutter pub get`/`analyze`/`test`; old-name census |
| 2 | User-visible copy | `feat: update user-facing product copy to Turna` | `lib/l10n/app_strings.dart`, `lib/views/app.dart`, `lib/views/settings/about_varnamala_page.dart`, `lib/views/settings/widgets/settings_about_section.dart`, splash / welcome / share |
| 3 | Dart package & symbols | `refactor: rename Flutter package and Dart symbols to Turna` | `pubspec.yaml`; `package:varnamala/→package:turna/` everywhere; `VarnamalaApp`→`TurnaApp`; `VarnamalaTheme`→`TurnaTheme`; `about_varnamala_page.dart`→`about_turna_page.dart`; rerun `build_runner` |
| 4 | Native identities | `chore: rename native application identities to Turna` | `android/app/build.gradle`, `AndroidManifest.xml`, Kotlin package path; iOS `Info.plist`/`project.pbxproj`; macOS `AppInfo.xcconfig`/`pbxproj`; Windows `CMakeLists.txt`/`main.cpp`/`Runner.rc`; Linux `CMakeLists.txt`/`my_application.cc`; Web `index.html`/`manifest.json`; OHOS `oh-package.json5` + AppScope resources |
| 5 | Editor + local-data compat | `refactor: rename course editor and migrate local settings` | `tool/gui/*`; `QSettings("Turna","CourseEditor")` with read-from-old on first run; `.varnamala`/`.varnamala-gui` → `.turna`/`.turna-gui` (with read-compat); `.varnamala-backup` preserved |
| 6 | Docs | `docs: document Turna rebrand and preserve upstream attribution` | `README.md`, `CLAUDE.md`, project analysis, course authoring guide, GUI user docs, release/build notes |
| — | Final verification | (no commit, audit only) | `flutter pub get` + `dart format .` + `flutter analyze` + `flutter test`; platform build per §11.2; old-name audit per §11.4 |

## Migration strategy (local data)

### QSettings (`tool/gui`)

Read order on first run after the upgrade:

1. Look up `QSettings("Turna","CourseEditor")`.
2. If empty, read `QSettings("Varnamala","CourseEditor")`.
3. Copy the value into the new `Turna` settings and proceed with the new
   key from there.
4. Never delete the old `Varnamala` key — leave it for any user who
   rolls back the binary.

### Local directories

- `.varnamala` → `.turna` (user config dir).
- `.varnamala-gui` → `.turna-gui` (editor config dir).
- Both migrations: read the old dir, fall back, write through to the new
  one; do not delete the old dir.
- `.varnamala-backup` is a course-internal backup format. **Keep it.**
  Renaming it would invalidate existing course backups and test fixtures.

### Protocols that do not migrate

- Course JSON schema and field names.
- SQLite table names and DB structure.
- Existing course / vocab / lesson IDs.
- Anki import format and study-progress data structures.

## About-page rule (upstream attribution)

The about page is rewritten as *Turna* but must not lie about provenance.
The accepted wording pattern:

> Turna 是一款本地优先的土耳其语学习应用，基于开源项目 Varnamala 开发。

Keep:

- `github.com/rshrc/Varnamala` link.
- Upstream author and community attribution.
- All license texts.

## Retention rules — what we deliberately do **not** rename

A reviewer should treat the following hits as **legitimately retained**
`Varnamala` references, not regressions:

- Upstream repo names, links, and community credits (`README`, `About`,
  `LICENSE`).
- Historical entries inside `CHANGELOG` / ADRs.
- One-shot migration code in `tool/gui` (read-old-write-new for
  QSettings + local dirs).
- `.varnamala-backup` paths in course-internal backup logic and fixtures.
- Image / launcher / icon file names listed in §"Out of scope".

Everything else — current product copy, current `package:` imports,
current platform display names, current publish IDs — must end up
`Turna` / `turna` / `me.dsdogs.turna`.

## Acceptance criteria (from the source plan §12)

The rebrand is "done" iff:

- [ ] All user-visible product copy is `Turna`.
- [ ] Dart package is `turna`; no `package:varnamala/` imports remain in
      committed code.
- [ ] Root widget and brand theme class use `Turna` naming.
- [ ] Android, Apple, Linux, Windows, Web, OHOS identities are unified.
- [ ] Android `applicationId` and Apple `Bundle ID` confirmed as the
      long-term release values (`me.dsdogs.turna`).
- [ ] Course editor displays as `Turna Course Editor`.
- [ ] Old GUI settings and local directories have read-compat or
      one-shot migration in place.
- [ ] Upstream Varnamala attribution, links, and historical records
      preserved.
- [ ] No images, icons, mascot files were modified.
- [ ] Static checks, unit tests, and available platform builds pass.
- [ ] Every remaining `Varnamala` hit has a documented "intentional"
      reason under §"Retention rules".

## Follow-up task (out of this ADR)

A separate visual-assets round will handle:

- Turna logo, new mascot and pose sets.
- App icons for Android / iOS / macOS / Windows / Web / OHOS.
- Splash and store artwork.
- Re-evaluating whether the Peacock palette stays.

The visual task must precede any public release.
