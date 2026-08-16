#!/usr/bin/env bash
# CANDIDATE — not verified on a clean host or CI.
# P0-003 must replace this stub with the single frozen command that produced
# android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
echo "turna_anki_core Android build is not verified yet." >&2
echo "Workspace: ${root}" >&2
echo "See build-android/README.md and docs/official-anki-migration/01-phase-0-implementation-plan.md §10." >&2
exit 2
