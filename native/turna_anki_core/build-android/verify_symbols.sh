#!/usr/bin/env bash
# CANDIDATE — not verified. Requires a built libturna_anki.so.
set -euo pipefail

so="${1:-}"
if [[ -z "${so}" || ! -f "${so}" ]]; then
  echo "usage: $0 path/to/libturna_anki.so" >&2
  echo "No .so has been produced yet (P0-003)." >&2
  exit 2
fi

echo "verify_symbols.sh is still a stub; P0-003 must implement ELF/symbol checks." >&2
exit 2
