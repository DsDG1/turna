#!/usr/bin/env bash
# Apply every patches/[0-9]*.patch to the pinned anki/ submodule, idempotently.
# A patch is skipped only when its added lines are already present in the tree;
# anything else (conflict, missing target) is a hard error. This is the single
# replay path mandated by patches/README.md — never edit anki/ by hand.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

shopt -s nullglob
patches=("$root"/patches/[0-9]*.patch)
if [[ ${#patches[@]} -eq 0 ]]; then
  echo "no patches found in $root/patches" >&2
  exit 2
fi

for patch in "${patches[@]}"; do
  name="$(basename "$patch")"
  if git -C "$root/anki" apply --check "$patch" 2>/dev/null; then
    git -C "$root/anki" apply "$patch"
    echo "applied $name"
    continue
  fi
  # Not applicable: accept only if every added line already exists in rslib.
  missing=0
  while IFS= read -r added; do
    [[ -n "${added// /}" ]] || continue
    if ! grep -RqF -- "$added" "$root/anki/rslib" 2>/dev/null; then
      echo "$name: expected applied change not found: $added" >&2
      missing=1
    fi
  done < <(sed -n 's/^+\([^+]\)/\1/p' "$patch")
  if [[ "$missing" -ne 0 ]]; then
    echo "$name neither applies cleanly nor is fully applied." >&2
    echo "Reset with: git -C anki checkout -- . && bash build-android/apply_patches.sh" >&2
    exit 1
  fi
  echo "already applied $name"
done
