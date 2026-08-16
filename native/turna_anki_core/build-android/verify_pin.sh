#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
expected="$(tr -d '[:space:]' < "$root/contract/BACKEND_COMMIT")"
head="$(git -C "$root/anki" rev-parse HEAD)"
if [[ "$expected" != "$head" ]]; then
  echo "BACKEND_COMMIT drift: file=$expected submodule=$head" >&2
  exit 1
fi
patch="$root/patches/0001-export-progress-state.patch"
if [[ -f "$patch" ]] && ! grep -q 'pub use progress::ProgressState' "$root/anki/rslib/src/lib.rs"; then
  echo "required patch 0001-export-progress-state is not applied" >&2
  exit 1
fi
echo "pin ok $head"
