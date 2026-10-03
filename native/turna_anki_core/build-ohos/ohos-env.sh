#!/usr/bin/env bash
# Shared OHOS toolchain discovery and Cargo/cc-rs configuration.
#
# Source this, do not execute it. Both build-ohos/build.sh (the probe) and
# build-ohos/build-bridge.sh (the real engine) need identical settings, and
# the failure modes encoded here are non-obvious enough that a second copy
# would eventually drift.
#
# Exports: triple, sdk_native, sysroot, llvm_bin, clang
# Sets:    CARGO_TARGET_*_LINKER, CARGO_ENCODED_RUSTFLAGS, CC_*, AR_*, RANLIB_*

set -euo pipefail

triple="aarch64-unknown-linux-ohos"

# --- Locate the OHOS native toolchain -------------------------------------
# DEVECO_SDK_HOME is what DevEco Studio itself exports, so prefer it. The
# `native` subtree is the OHOS NDK equivalent of ANDROID_NDK_HOME.
sdk_native=""
for candidate in \
  "${DEVECO_SDK_NATIVE:-}" \
  "${DEVECO_SDK_HOME:-}/default/openharmony/native" \
  "${DEVECO_SDK_HOME:-}/native" \
  "${OHOS_NDK_HOME:-}" \
  "${OHOS_SDK_NATIVE:-}"; do
  if [[ -n "${candidate}" && -d "${candidate}/sysroot" ]] \
     && { [[ -x "${candidate}/llvm/bin/clang.exe" ]] || [[ -x "${candidate}/llvm/bin/clang" ]]; }; then
    sdk_native="${candidate}"
    break
  fi
done

if [[ -z "${sdk_native}" ]]; then
  echo "Could not find the OHOS native toolchain (a dir with sysroot/ and llvm/bin/clang)." >&2
  echo "Set DEVECO_SDK_HOME (DevEco Studio's sdk dir) or DEVECO_SDK_NATIVE." >&2
  exit 2
fi

sysroot="${sdk_native}/sysroot"
llvm_bin="${sdk_native}/llvm/bin"

# --- The path-must-not-contain-spaces problem ------------------------------
# cc-rs splits CFLAGS on whitespace and offers no way to keep a value intact
# (CC_SHELL_ESCAPED_FLAGS makes it worse: it strips backslashes, turning
# D:\DevEco Studio\... into D:DevEco and then splitting there anyway). If the
# SDK lives under "C:\Program Files\..." — the default DevEco install — every
# build of sqlite3.c dies with a mangled --sysroot. An 8.3 short name is a
# no-side-effect alias that solves it.
if [[ "${sdk_native}" == *" "* ]]; then
  short=""
  # cygpath is Git-Bash/MSYS only. `cmd //c for %I` breaks there because MSYS
  # rewrites the //c argument, so try cygpath first and keep cmd as a fallback.
  if command -v cygpath >/dev/null 2>&1; then
    short="$(cygpath -w -s "${sdk_native}" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -z "${short}" || "${short}" == *" "* ]]; then
    MSYS_NO_PATHCONV=1 short="$(cmd //c "for %I in (\"${sdk_native}\") do @echo %~sI" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -n "${short}" && "${short}" != *" "* && -d "${short}/sysroot" ]]; then
    echo "note: SDK path contains spaces; using 8.3 alias ${short}" >&2
    sdk_native="${short}"
    sysroot="${sdk_native}/sysroot"
    llvm_bin="${sdk_native}/llvm/bin"
  else
    cat >&2 <<'MSG'
error: the OHOS SDK path contains spaces and no 8.3 short name is available:
    <path>
cc-rs cannot pass a --sysroot containing a space to clang. Create a
space-free alias and point DEVECO_SDK_NATIVE at it. On Windows:

    mklink /J C:\ohos-ndk "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native"
    set DEVECO_SDK_NATIVE=C:\ohos-ndk
MSG
    exit 2
  fi
fi

clang="${llvm_bin}/clang"
[[ -x "${clang}" ]] || clang="${llvm_bin}/clang.exe"
[[ -x "${clang}" ]] || { echo "no clang in ${llvm_bin}" >&2; exit 2; }

# --- Cargo / cc-rs configuration ------------------------------------------
# 1. linker driver. rustc does NOT forward --target to the linker, so without
#    -Clink-arg=--target the driver falls back to the *host* triple and
#    -fuse-ld=lld selects the COFF lld-link, which rejects --version-script,
#    --eh-frame-hdr and -z. This one flag is the whole ballgame.
# 2. CARGO_ENCODED_RUSTFLAGS, not RUSTFLAGS: RUSTFLAGS is split on spaces,
#    which mangles any path containing a space. The \x1f separator is the
#    only encoding cargo reads without splitting. Join with it; never prefix
#    it, because a leading separator yields an empty first element that
#    rustc reads as a second input filename.
us=$'\x1f'
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="${clang}"
export CARGO_ENCODED_RUSTFLAGS="-Clink-arg=--target=${triple}${us}-Clink-arg=--sysroot=${sysroot}${us}-Clink-arg=-fuse-ld=lld"

# 3. cc-rs env, for C dependencies (sqlite3.c, any C in the rslib tree).
export CC_aarch64_unknown_linux_ohos="${clang}"
export CXX_aarch64_unknown_linux_ohos="${clang}"
export CFLAGS_aarch64_unknown_linux_ohos="--target=${triple} --sysroot=${sysroot}"

# 4. llvm-ar / llvm-ranlib: no GNU ar on a Windows host, and cc-rs aborts
#    without them.
if [[ -x "${llvm_bin}/llvm-ar.exe" ]]; then
  export AR_aarch64_unknown_linux_ohos="${llvm_bin}/llvm-ar.exe"
  export RANLIB_aarch64_unknown_linux_ohos="${llvm_bin}/llvm-ranlib.exe"
elif [[ -x "${llvm_bin}/llvm-ar" ]]; then
  export AR_aarch64_unknown_linux_ohos="${llvm_bin}/llvm-ar"
  export RANLIB_aarch64_unknown_linux_ohos="${llvm_bin}/llvm-ranlib"
fi
