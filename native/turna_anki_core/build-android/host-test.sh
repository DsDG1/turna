#!/usr/bin/env bash
# Verified on 2026-08-16: cargo test passes with the pinned Anki commit
# after PROTOC=31.1, FTL submodules, and tokio io-util feature unification.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export PROTOC="${PROTOC:-$root/tools/protoc/bin/protoc}"
export PROTOC_BINARY="${PROTOC_BINARY:-$PROTOC}"
if [[ ! -x "$PROTOC" ]]; then
  echo "missing protoc at $PROTOC (Anki pins 31.1). See README.md." >&2
  exit 2
fi
patch="$root/patches/0001-export-progress-state.patch"
if [[ -f "$patch" ]] && ! grep -q 'pub use progress::ProgressState' "$root/anki/rslib/src/lib.rs"; then
  git -C "$root/anki" apply "$patch"
fi
if [[ ! -d "$root/anki/ftl/core-repo/core" ]]; then
  echo "Anki FTL submodules are missing. Run:" >&2
  echo "  git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo" >&2
  exit 2
fi
exec cargo test
