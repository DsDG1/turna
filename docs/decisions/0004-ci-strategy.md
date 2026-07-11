# ADR 0004: CI Strategy (Flutter CI workflow + Makefile)

- **Status**: Accepted
- **Date**: 2026-07-10 (updated 2026-07-11 for release pipeline integration)
- **Related**: Robustness roadmap Phase 0, future4 Phase 25, ADR 0017

## Context

Varnamala has 34 Dart test files and a clean `flutter analyze` baseline, but until now the only CI in the repository was `course_validation.yml`, which runs the Python course validator (`tool/course_cli.py validate` / `lint`) and the Python CLI tests. The Dart test suite and static analysis were never run in CI — they relied entirely on developers remembering to run them locally.

Two related problems were discovered during the robustness audit:

1. **No Flutter CI**. `flutter test` (132 tests as of this writing) and `flutter analyze` were not enforced on PRs, so regressions in Dart code could merge undetected.
2. **Branch mismatch in `discord_notification.yml`**. That workflow monitored `main`, while the repository's default and only long-lived branch is `master` (see `course_validation.yml` and `git status`). The Discord webhook therefore never fired on real pushes.

There was also no build automation file (no `Makefile`), so contributors had to remember the exact `build_runner` and test invocations.

## Decision

1. **Add `.github/workflows/flutter_ci.yml`**, triggered on push/PR to `master` when `lib/**`, `test/**`, `pubspec.yaml`, `analysis_options.yaml`, or `build.yaml` change. It runs `flutter pub get`, `flutter analyze`, and `flutter test` on a stable Flutter channel (pinned via `channel: stable` with caching enabled). The path filter is complementary to `course_validation.yml` (which fires on `assets/courses/**`), so the two workflows rarely both run on the same change.

2. **Fix the branch mismatch**: change `discord_notification.yml` to monitor `master` so push notifications actually fire.

3. **Add a root `Makefile`** with targets `gen`, `analyze`, `test`, `test-python`, `build-release`, `build-release-smoke`, `ci`, `clean`, and a `help` target. `make ci` runs the local equivalent of CI (`flutter analyze` + `flutter test` + `python -m unittest` + build smoke).

4. **Extend the workflow and Makefile to run a release build smoke test** (future4 Phase 25). After tests pass, CI runs `python3 tool/build_release.py --version ci-smoke --skip-web --skip-content-validation`. This ensures the release path (codegen + `flutter build apk/appbundle`) does not rot between releases. Web is skipped because CI does not consume web artifacts; content validation is skipped because `course_validation.yml` already validates course assets on content changes.

## Consequences

- Dart regressions now fail PRs before merge.
- `flutter analyze` is enforced; since the baseline is already clean, no `continue-on-error` is needed and any new warning blocks CI.
- Contributors have a single `make ci` entry point mirroring CI.
- CI runs on the stable Flutter channel; the pubspec SDK constraint (`>=3.2.3 <4.0.0`) still governs the language version, and a future breaking Flutter release would surface here first.