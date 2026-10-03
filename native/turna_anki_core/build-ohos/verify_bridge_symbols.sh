#!/usr/bin/env bash
# Verify the OHOS engine bridge .so.
#
# Stricter than verify_symbols.sh for the probe: this one asserts that rslib
# actually got linked in. The probe's job was proving the toolchain; if
# Collection/sqlite were dead-code-eliminated out of a 2 MB .so, every
# conclusion drawn from it would be about the wrong artifact.
set -euo pipefail

so="${1:-}"
if [[ -z "${so}" || ! -f "${so}" ]]; then
  echo "usage: $0 path/to/libturna_anki.so" >&2
  exit 2
fi

echo "verify: ${so}"
size="$(wc -c < "${so}")"
echo "  size: ${size} bytes"

llvm_bin=""
for candidate in \
  "${DEVECO_SDK_NATIVE:-}/llvm/bin" \
  "${DEVECO_SDK_HOME:-}/default/openharmony/native/llvm/bin" \
  "${OHOS_NDK_HOME:-}/llvm/bin"; do
  if [[ -n "${candidate}" ]] \
     && { [[ -x "${candidate}/llvm-readelf.exe" ]] || [[ -x "${candidate}/llvm-readelf" ]]; }; then
    llvm_bin="${candidate}"
    break
  fi
done

pick() {
  local name="$1"
  if [[ -n "${llvm_bin}" ]]; then
    if [[ -x "${llvm_bin}/${name}" ]]; then echo "${llvm_bin}/${name}"; return; fi
    if [[ -x "${llvm_bin}/${name}.exe" ]]; then echo "${llvm_bin}/${name}.exe"; return; fi
  fi
  if command -v "${name}" >/dev/null 2>&1; then command -v "${name}"; return; fi
  echo ""
}

readelf_bin="$(pick llvm-readelf)"
nm_bin="$(pick llvm-nm)"
if [[ -z "${readelf_bin}" ]] && command -v readelf >/dev/null 2>&1; then readelf_bin="$(command -v readelf)"; fi
if [[ -z "${nm_bin}" ]] && command -v nm >/dev/null 2>&1; then nm_bin="$(command -v nm)"; fi
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
# llvm-readelf prints "DYN (Shared object file)"; llvm-readobj prints
# "SharedObject (0x3)". Accept either.
echo "${header}" | grep -E -q 'DYN \(Shared object file\)|SharedObject' || {
  echo "ELF type is not a shared object:" >&2
  exit 1
}

base="$(basename "${so}")"
if [[ "${base}" != "libturna_anki.so" ]]; then
  echo "filename must be libturna_anki.so, got ${base}" >&2
  exit 1
fi

dyn="$("${readelf_bin}" -d "${so}" || true)"

# bundled SQLite must stay bundled. An external libsqlite3.so would mean the
# engine needs a second .so shipped alongside it on-device — the exact
# dependency the Dart-side ensureOfficialAnkiSqlite() gap already creates.
if echo "${dyn}" | grep -F -q 'libsqlite3.so'; then
  echo "bundled SQLite leaked an external dependency:" >&2
  echo "${dyn}" >&2
  exit 1
fi

needed="$(echo "${dyn}" | grep 'NEEDED' | sed -E 's/.*\[(.*)\].*/\1/' | tr '\n' ' ' || true)"
echo "NEEDED:${needed}"

# No glibc: this is the check that catches a host-triple link mistake.
if echo "${dyn}" | grep -F -q 'libc.so.6'; then
  echo "unexpected host glibc dependency (libc.so.6):" >&2
  exit 1
fi

# Every NEEDED must be resolvable from the OHOS sysroot, or the loader will
# refuse the library on-device. libtime_service_ndk.so arrives via
# iana-time-zone's tz_ohos.rs (local timezone) and is a real system library;
# anything else is a surprise worth failing on.
sysroot=""
for candidate in \
  "${DEVECO_SDK_NATIVE:-}/sysroot/usr/lib/aarch64-linux-ohos" \
  "${DEVECO_SDK_HOME:-}/default/openharmony/native/sysroot/usr/lib/aarch64-linux-ohos" \
  "${OHOS_NDK_HOME:-}/sysroot/usr/lib/aarch64-linux-ohos"; do
  if [[ -n "${candidate}" && -d "${candidate}" ]]; then sysroot="${candidate}"; break; fi
done
if [[ -n "${sysroot}" ]]; then
  for lib in ${needed}; do
    if [[ ! -f "${sysroot}/${lib}" ]]; then
      echo "NEEDED ${lib} is not in the OHOS sysroot (${sysroot})" >&2
      exit 1
    fi
  done
  echo "  all NEEDED resolve against the sysroot"
else
  echo "  warning: sysroot not found, skipped NEEDED resolvability check" >&2
fi

missing=0
for sym in \
  turna_anki_abi_version \
  turna_anki_engine_new \
  turna_anki_engine_open \
  turna_anki_engine_close \
  turna_anki_call \
  turna_anki_cancel \
  turna_anki_buffer_free; do
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

# The arm64 artifact with rslib linked is ~23 MB. Anything under 2 MB means
# Collection/sqlite were DCE'd out and the artifact proves nothing.
min_bytes=2097152
if [[ "${size}" -lt "${min_bytes}" ]]; then
  echo "libturna_anki.so is ${size} bytes; expected >= ${min_bytes} once rslib is linked." >&2
  echo "Collection/sqlite was probably DCE'd out of the cdylib." >&2
  exit 1
fi

if ! "${nm_bin}" -D --defined-only "${so}" | grep -q 'T '; then
  echo "no exported text symbols; the .so was stripped" >&2
  exit 1
fi

echo "verify_bridge_symbols: pass"
echo
echo "NOT YET VERIFIED: on-device dlopen and engine behaviour. A 23 MB .so that"
echo "links and exports its symbols still has to load in a real hap process"
echo "before any conclusion about档 B' is earned."
