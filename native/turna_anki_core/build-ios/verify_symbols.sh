#!/usr/bin/env bash
# Verify an arm64 libturna_anki.a Mach-O static archive: arch + exported
# turna_anki_* bridge symbols + a minimum size so a DCE'd crate fails loudly.
set -euo pipefail

lib="${1:-}"
if [[ -z "${lib}" || ! -f "${lib}" ]]; then
  echo "usage: $0 path/to/libturna_anki.a" >&2
  exit 2
fi

echo "verify: ${lib}"
echo "  size: $(wc -c < "${lib}") bytes"
file "${lib}"

if ! lipo -info "${lib}" 2>/dev/null | grep -q 'arm64'; then
  echo "archive does not contain an arm64 slice:" >&2
  lipo -info "${lib}" >&2 || true
  exit 1
fi

nm_bin="$(xcrun -f nm 2>/dev/null || command -v nm || true)"
if [[ -z "${nm_bin}" ]]; then
  echo "need nm (xcrun -f nm)" >&2
  exit 2
fi

# Apple nm exits non-zero on archive members carrying LLVM attributes it does
# not parse (Rust LLVM is newer); the symbol dump on stdout is still complete,
# so capture it once instead of piping under pipefail.
nm_out="$("${nm_bin}" -gU "${lib}" 2>/dev/null || true)"

missing=0
for sym in \
  _turna_anki_abi_version \
  _turna_anki_engine_new \
  _turna_anki_engine_open \
  _turna_anki_call \
  _turna_anki_cancel \
  _turna_anki_engine_close \
  _turna_anki_buffer_free; do
  if ! grep -q "T ${sym}$" <<<"${nm_out}"; then
    echo "missing exported symbol: ${sym}" >&2
    missing=1
  else
    echo "symbol ok: ${sym}"
  fi
done
if [[ "${missing}" -ne 0 ]]; then
  exit 1
fi

min_bytes=2097152
size="$(wc -c < "${lib}")"
if [[ "${size}" -lt "${min_bytes}" ]]; then
  echo "libturna_anki.a is ${size} bytes; expected >= ${min_bytes} once rslib is linked." >&2
  exit 1
fi

echo "verify_symbols: pass"
