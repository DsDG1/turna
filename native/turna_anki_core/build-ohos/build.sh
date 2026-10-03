#!/usr/bin/env bash
# Cross-compile the OpenHarmony probe and verify it.
#
# Produces probe-ohos/target/aarch64-unknown-linux-ohos/release/libturna_anki_probe.so
#
# Every flag in here was arrived at by fixing a real failure; see
# build-ohos/README.md for the failure each one answers. Do not "simplify"
# them away.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
probe="${root}/probe-ohos"
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
# (CC_SHELL_ESCAPED_FLAGS makes it worse: it strips backslashes). If the SDK
# lives under "C:\Program Files\..." — the default DevEco install — every
# build of sqlite3.c dies with a mangled --sysroot. A 8.3 short name is a
# no-side-effect alias that solves it. Fall back to a directory junction if
# the volume has 8.3 names disabled.
if [[ "${sdk_native}" == *" "* ]]; then
  short=""
  # cygpath is Git-Bash/MSYS only. `cmd //c for %I` breaks there because MSYS
  # rewrites the //c argument, so try cygpath first and keep cmd as a fallback
  # for other environments.
  if command -v cygpath >/dev/null 2>&1; then
    short="$(cygpath -w -s "${sdk_native}" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -z "${short}" || "${short}" == *" "* ]]; then
    MSYS_NO_PATHCONV=1 short="$(cmd //c "for %I in (\"${sdk_native}\") do @echo %~sI" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -n "${short}" && "${short}" != *" "* && -d "${short}/sysroot" ]]; then
    echo "note: SDK path contains spaces; using 8.3 alias ${short}"
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

# --- Toolchain facts, printed before the build -----------------------------
echo "turna_anki_core OHOS probe build"
echo "  root:        ${root}"
echo "  sdk_native:  ${sdk_native}"
echo "  sysroot:     ${sysroot}"
echo "  clang:       ${clang} ($("${clang}" --version | head -1))"
echo "  rustc:       $(rustc --version)"
echo "  target:      ${triple}"
echo "  output:      ${probe}/target/${triple}/release/libturna_anki_probe.so"

# --- rust std --------------------------------------------------------------
# Prebuilt std for this target ships with the 1.97.1 stable channel
# (rust-std-1.97.1-aarch64-unknown-linux-ohos.tar.xz, 28.7 MB). So this is a
# plain Tier-3-with-std target: no -Z build-std, no nightly.
if command -v rustup >/dev/null 2>&1; then
  rustup target add "${triple}"
fi

# --- Cargo / cc-rs configuration ------------------------------------------
# 1. linker driver. rustc does NOT forward --target to the linker, so without
#    -Clink-arg=--target the driver falls back to the *host* triple and
#    -fuse-ld=lld selects the COFF lld-link, which rejects --version-script,
#    --eh-frame-hdr and -z. This one flag is the whole ballgame.
# 2. CARGO_ENCODED_RUSTFLAGS, not RUSTFLAGS: RUSTFLAGS is split on spaces,
#    which mangles any path containing a space. The \x1f separator is the
#    only encoding cargo reads without splitting.
us=$'\x1f'
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="${clang}"
# Joined with $us, never prefixed by it: a leading separator produces an empty
# first element, which rustc reads as a second input filename.
export CARGO_ENCODED_RUSTFLAGS="-Clink-arg=--target=${triple}${us}-Clink-arg=--sysroot=${sysroot}${us}-Clink-arg=-fuse-ld=lld"

# 3. cc-rs env, for compiling sqlite3.c (the bundled SQLite).
export CC_aarch64_unknown_linux_ohos="${clang}"
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

cd "${probe}"

# Run the host tests first. A logic bug found here costs seconds; the same bug
# found on a device costs a signing-and-deploy cycle.
echo "  host tests:  cargo test --release"
cargo test --release --quiet

echo "  cross build: cargo build --release --target ${triple}"
cargo build --release --target "${triple}"

so="${probe}/target/${triple}/release/libturna_anki_probe.so"
if [[ ! -f "${so}" ]]; then
  echo "cargo finished but ${so} is missing" >&2
  exit 1
fi

exec bash "${root}/build-ohos/verify_symbols.sh" "${so}"
