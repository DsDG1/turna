#!/usr/bin/env bash
# Verify an arm64 libturna_anki.so. Prefer the NDK llvm-* tools; a host
# llvm-readelf may fail to list Android dynsyms and produce a false miss.
set -euo pipefail

so="${1:-}"
if [[ -z "${so}" || ! -f "${so}" ]]; then
  echo "usage: $0 path/to/libturna_anki.so" >&2
  exit 2
fi

echo "verify: ${so}"
echo "  size: $(wc -c < "${so}") bytes"
file "${so}"

prebuilt=""
if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
  prebuilt="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
fi

pick() {
  local name="$1"
  if [[ -n "${prebuilt}" && -x "${prebuilt}/${name}" ]]; then
    echo "${prebuilt}/${name}"
    return
  fi
  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
    return
  fi
  echo ""
}

readelf_bin="$(pick llvm-readelf)"
nm_bin="$(pick llvm-nm)"
if [[ -z "${readelf_bin}" ]] && command -v readelf >/dev/null 2>&1; then
  readelf_bin="$(command -v readelf)"
fi
if [[ -z "${nm_bin}" ]] && command -v nm >/dev/null 2>&1; then
  nm_bin="$(command -v nm)"
fi
if [[ -z "${readelf_bin}" || -z "${nm_bin}" ]]; then
  echo "need llvm-readelf/readelf and llvm-nm/nm" >&2
  exit 2
fi
echo "  readelf: ${readelf_bin}"
echo "  nm:      ${nm_bin}"

header="$("${readelf_bin}" -h "${so}")"
echo "${header}" | grep -Ei -q 'aarch64' || {
  echo "ELF machine is not AArch64:" >&2
  echo "${header}" >&2
  exit 1
}

base="$(basename "${so}")"
if [[ "${base}" != "libturna_anki.so" ]]; then
  echo "filename must be libturna_anki.so, got ${base}" >&2
  exit 1
fi

dyn="$("${readelf_bin}" -d "${so}" || true)"
if echo "${dyn}" | grep -F -q 'libc.so.6'; then
  echo "unexpected host glibc dependency (libc.so.6):" >&2
  echo "${dyn}" >&2
  exit 1
fi

echo "NEEDED:"
echo "${dyn}" | grep 'NEEDED' || true

missing=0
for sym in turna_anki_abi_version turna_anki_engine_new turna_anki_call turna_anki_buffer_free; do
  if ! "${nm_bin}" -D "${so}" | grep -E -q "T ${sym}$"; then
    echo "missing exported symbol: ${sym}" >&2
    missing=1
  else
    echo "symbol ok: ${sym}"
  fi
done
if [[ "${missing}" -ne 0 ]]; then
  echo "dynsym dump:" >&2
  "${nm_bin}" -D "${so}" | grep 'T ' >&2 || true
  exit 1
fi

min_bytes=2097152
size="$(wc -c < "${so}")"
if [[ "${size}" -lt "${min_bytes}" ]]; then
  echo "libturna_anki.so is ${size} bytes; expected >= ${min_bytes} once rslib is linked." >&2
  echo "Collection/sqlite was probably DCE'd out of the cdylib." >&2
  exit 1
fi

echo "verify_symbols: pass"
