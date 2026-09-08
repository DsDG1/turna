#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
expected="$(tr -d '[:space:]' < "$root/contract/BACKEND_COMMIT")"
head="$(git -C "$root/anki" rev-parse HEAD)"
if [[ "$expected" != "$head" ]]; then
  echo "BACKEND_COMMIT drift: file=$expected submodule=$head" >&2
  exit 1
fi

bash "$root/build-android/apply_patches.sh"

# The anki/ working tree may differ from the pinned commit only through the
# documented patches. Any other modified/untracked path means an undocumented
# Turna edit snuck in — exactly what broke fresh-clone builds before 0002/0003
# were formalized.
allowed="$(
  shopt -s nullglob
  sed -n 's|^diff --git a/\([^ ]*\) b/.*$|\1|p' "$root"/patches/[0-9]*.patch | sort -u
)"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  status="${line:0:2}"
  path="${line:3}"
  # Nested FTL submodules are initialized separately and may carry their own state;
  # .mimosa/ is a local security-scanner artifact, never shipped.
  [[ "$path" == ftl/* || "$path" == .mimosa* ]] && continue
  if ! grep -qxF "$path" <<<"$allowed"; then
    echo "undocumented change in anki/$path (status: $status)." >&2
    echo "Formalize it as patches/<next>.patch or revert it (see patches/README.md)." >&2
    exit 1
  fi
done < <(git -C "$root/anki" status --porcelain)

echo "pin ok $head ($(ls "$root"/patches/[0-9]*.patch 2>/dev/null | xargs -n1 basename | tr '\n' ' '))"
