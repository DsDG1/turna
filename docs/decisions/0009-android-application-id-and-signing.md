# ADR 0009: Android applicationId, release signing, and DB downgrade policy

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 17, ADR 0004 (CI strategy), ADR 0006 (unified error handling)

## Context

The app shipped with the Flutter placeholder `applicationId`/`namespace`
`com.example.varnamala` and a TODO-only release signing block that signed
release builds with the debug keys. Neither is ownable: a store listing needs a
stable applicationId, and a real release build needs a signing path that does
not break `flutter build` when no keystore is present locally/CI.

Separately, `CourseDatabase` (drift) defined `onCreate` + `onUpgrade` but no
downgrade handling. Drift's default behavior on an app downgrade (the on-disk
schema is newer than the code expects) is to throw, crashing the
already-downgraded app on DB open. The course DB is a derived cache reseedable
from the bundled JSON assets, so a crash here is both avoidable and wrong.

Finally, the course content version was stored as the `index.json` version
only. `expressions.json` carries its own `version` field, but a change to it
did not trigger a reseed — a silent seed miss.

## Decision

### 1. applicationId / namespace = `com.varnamala.app`

Reverse-DNS with an `app` suffix, leaving room for sibling apps under
`com.varnamala.*`. The Kotlin source package
(`android/app/src/main/kotlin/com/varnamala/app/MainActivity.kt`) was moved to
match the new namespace.

### 2. Release signing reads `android/key.properties` with debug fallback

A `signingConfigs.release` block reads `key.properties` (already in
`android/.gitignore`) when present and is wired into the `release` build type.
When `key.properties` is absent, the release build type falls back to
`signingConfigs.debug` so local/CI `flutter build` works without a keystore.
A real release keystore is a separate, out-of-band setup — Phase 17 ships the
skeleton only.

### 3. `CourseDatabase` downgrade: wipe + recreate (do not throw)

`onUpgrade` now handles `from > to` by deleting all course tables
(`lesson_contents`, `lessons`, `units`, `sections`, `vocabulary`,
`grammar_points`, `expressions`, `course_meta`) and calling `createAll`.
`setupLocator` runs `DatabaseSeeder.seedIfNeeded` immediately after open; the
`contentVersion` meta is also wiped, so the next cold start reseeds from
assets. This is self-healing for a reseedable cache rather than crashy.

(drift 2.21 routes both upgrades and downgrades through a single `onUpgrade`
handler — there is no separate `onDowngrade` parameter.)

### 4. Composite content version: `index` + `expressions`

`DatabaseSeeder.seedIfNeeded` computes the content version as
`"$indexVersion+$expressionsVersion"` and stores it in the `contentVersion`
meta. Bumping either asset's version now triggers a reseed. A runtime
cross-course lesson/unit id uniqueness gate (`collectCrossCourseIdErrors`)
was also added in `_seedSections` — a runtime mirror of the CI-only
`validateSwahiliCourse` check — so a duplicate id cannot silently corrupt the
seeded tree.

## Consequences

- The first release with `com.varnamala.app` is a fresh install (the old
  `com.example` install is a distinct app); there is no in-place migration.
- Downgrade path is self-healing, not crashy.
- Existing installs upgrade to the composite version on first launch after
  this phase ships: their stored meta is the old single-component `"5"`, which
  differs from the new `"5+1"` and triggers a one-time reseed. This is
  intended — it is the same recovery path `seedIfNeeded` is designed for, and
  it is what drives the content-update prompt (ADR 0002) to fire for users
  with progress.
- A duplicate lesson/unit id in bundled content now throws
  `CourseValidationException` at seed time rather than silently clobbering.
- Local/CI builds work without a keystore; a real release build requires
  dropping `key.properties` in `android/`.

## Alternatives considered

- **Throw on downgrade.** Rejected: crashes an already-downgraded app for a
  reseedable cache.
- **Keep `com.example.varnamala`.** Rejected: not ownable for a store listing.
- **Hard-require `key.properties` for release.** Rejected: breaks local/CI
  `flutter build` and the release keystore does not exist yet.