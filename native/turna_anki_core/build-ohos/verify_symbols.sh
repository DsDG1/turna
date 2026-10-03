#!/usr/bin/env bash
# Verify the OHOS probe .so. Prefer the OHOS llvm-* tools: a host
# llvm-readelf may misreport a foreign-ABI dynsym table and produce a false
# miss, and a host `file` will not know the OHOS triple.
set -euo pipefail

so="${1:-}"
if [[ -z "${so}" || ! -f "${so}" ]]; then
  echo "usage: $0 path/to/libturna_anki_probe.so" >&2
  exit 2
fi

echo "verify: ${so}"
echo "  size: $(wc -c < "${so}") bytes"

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
    if [[ -x "${llvm_bin}/${name}" ]]; then
      echo "${llvm_bin}/${name}"
      return
    fi
    if [[ -x "${llvm_bin}/${name}.exe" ]]; then
      echo "${llvm_bin}/${name}.exe"
      return
    fi
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
  echo "set DEVECO_SDK_NATIVE so the OHOS llvm tools can be found" >&2
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
# llvm-readelf prints "Type: DYN (Shared object file)"; llvm-readobj prints
# "Type: SharedObject (0x3)". Accept either so the check works with whichever
# tool this machine happens to have.
echo "${header}" | grep -E -q 'DYN \(Shared object file\)|SharedObject' || {
  echo "ELF type is not a shared object:" >&2
  echo "${header}" >&2
  exit 1
}

base="$(basename "${so}")"
if [[ "${base}" != "libturna_anki_probe.so" ]]; then
  echo "filename must be libturna_anki_probe.so, got ${base}" >&2
  exit 1
fi

# The engine layer must be self-contained. `bundled` SQLite means no
# libsqlite3.so in NEEDED; anything beyond libc.so means the probe grew a
# dependency the real bridge would also have to satisfy on-device.
dyn="$("${readelf_bin}" -d "${so}" || true)"
if echo "${dyn}" | grep -F -q 'libsqlite3.so'; then
  echo "bundled SQLite leaked an external dependency:" >&2
  echo "${dyn}" >&2
  exit 1
fi
needed="$(echo "${dyn}" | grep 'NEEDED' | sed -E 's/.*\[(.*)\].*/\1/' | tr '\n' ' ' || true)"
echo "NEEDED:${needed}"
case "${needed}" in
  *libc.so*)
    if [[ "$(echo "${needed}" | tr ' ' '\n' | grep -c '\.so' || true)" != "1" ]]; then
      echo "expected libc.so as the only dynamic dependency, got:${needed}" >&2
      exit 1
    fi
    ;;
  *)
    echo "expected libc.so in NEEDED, got:${needed}" >&2
    exit 1
    ;;
esac

missing=0
for sym in \
  turna_anki_abi_version \
  turna_anki_probe_sqlite_roundtrip \
  turna_anki_probe_unicase_collation \
  turna_anki_probe_tokio_runtime \
  turna_anki_probe_tokio_fs \
  turna_anki_probe_set_fs_path \
  turna_anki_probe_tokio_signal; do
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

# Below ~1 MB the SQLite amalgamation was linked out and the roundtrip probe
# would be a no-op. Real observed size is ~2.9 MB.
min_bytes=1048576
size="$(wc -c < "${so}")"
if [[ "${size}" -lt "${min_bytes}" ]]; then
  echo "libturna_anki_probe.so is ${size} bytes; expected >= ${min_bytes}." >&2
  echo "The bundled SQLite amalgamation was probably DCE'd out." >&2
  exit 1
fi

# Symbols surviving -Wl,--strip-debug is expected; losing the whole dynamic
# symbol table is not, and would make DynamicLibrary.lookup fail on-device.
if ! "${nm_bin}" -D --defined-only "${so}" | grep -q 'T '; then
  echo "no exported text symbols; the .so was stripped" >&2
  exit 1
fi

echo "verify_symbols: pass"
echo
echo "NOT YET VERIFIED: on-device dlopen. Compile success does not prove the"
echo "OHOS loader accepts this .so. Ship it in a minimal hap and call all four"
echo "symbols through DynamicLibrary.open before drawing any conclusion."
