# ADR 0017: Release Pipeline and Versioning

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 25, ADR 0004 (CI strategy), ADR 0009 (Android signing)

## Context

future4 turned Varnamala from "content can be produced" into "framework is maintainable, performant, and feature-complete for a solo offline learner". The next step is to make that work shippable on a repeatable, documented release cadence.

Until now, building a release APK/AAB required remembering a chain of manual commands (`flutter pub get`, `build_runner`, `flutter build apk/appbundle/web`), then locating the unnamed artifacts in `build/app/outputs/`. There was no single entry point, no versioned artifact names, no content report attached to a release, and no CI build smoke test.

## Decision

### 1. Semantic-ish versioning for pre-1.0 releases

- **Major** (`X.0.0`): reserved for breaking framework or app-level changes (e.g., switching storage engines, dropping all progress).
- **Minor** (`0.X.0`): content milestones (e.g., real Swahili vocab replacement, new language course).
- **Patch** (`0.0.X`): framework/engineering-only releases (e.g., the entire future4 framework + feature round).

The release produced from future4 is tagged **`v0.4.0-future4`**.

### 2. One-command release script: `tool/build_release.py`

The script is the single entry point for producing release artifacts. It:

1. Validates the version argument (`--version`).
2. Runs `flutter pub get`.
3. Runs `dart run build_runner build --delete-conflicting-outputs`.
4. Runs `flutter build apk --release`.
5. Runs `flutter build appbundle --release`.
6. Optionally runs `flutter build web --release` unless `--skip-web` is passed.
7. Runs `tool/export_content_inventory.py` to regenerate the content inventory.
8. Copies/renames artifacts into `--output-dir` with versioned names:
   - `varnamala-v0.4.0-future4-release.apk`
   - `varnamala-v0.4.0-future4-release.aab`
   - `varnamala-v0.4.0-future4-web/` (when built)
9. Copies `docs/content_inventory_current.md` to `docs/content_inventory_v{version}.md` (e.g., `docs/content_inventory_v0.4.0-future4.md`).
10. Prints a summary with artifact paths.

The script uses `subprocess.run(..., check=True)` and fails fast on any step so CI can treat a non-zero exit as a broken build.

### 3. Release signing remains out-of-band

`android/app/build.gradle` already reads `android/key.properties` when present and falls back to debug signing when absent (ADR 0009). `build_release.py` does not touch keystore material. A real store release requires dropping `key.properties` locally; CI builds use the debug fallback.

### 4. Content inventory is part of the release artifact

Every release must ship with a `docs/content_inventory_v{version}.md` that records:

- Vocabulary / expression / grammar point counts.
- Section / unit / lesson counts.
- Distinct audio asset references.
- Reference coverage (how many vocab words appear in lessons).
- Known gaps and the next content milestone (future5).

This makes each release self-describing and gives future content PRs a concrete baseline to diff against.

### 5. CI runs the build smoke test

`.github/workflows/flutter_ci.yml` is extended to run `python tool/build_release.py --skip-web --version ci-smoke` after tests pass. This ensures the release path does not rot without a human manually building.

`Makefile` gets a `build-release` target that calls the script with sensible defaults.

## Consequences

- A release is now a deterministic command instead of a checklist.
- Artifact names are unambiguous and tied to the version tag.
- CI catches build breakages before merge.
- Keystore management stays outside source control; the script remains safe for local/CI use.
- Content inventory is regenerated automatically on every release, keeping the report from drifting.

## Alternatives considered

- **GitHub Actions-only release pipeline.** Rejected: the project is local-first and may be built offline; a Python script works identically on a developer machine and in CI.
- **Embed version in `pubspec.yaml` for every release.** Rejected for this pre-1.0 stage: manually bumping `pubspec.yaml` adds friction. The script derives artifact naming from the tag/version argument; `pubspec.yaml` can be bumped when a store release happens.
- **Require `key.properties` in CI.** Rejected: CI would fail because no release keystore exists in the repository.
