#!/usr/bin/env bash
# Cross-compile the REAL Anki engine bridge for OpenHarmony.
#
# Produces target/aarch64-unknown-linux-ohos/release/libturna_anki.so
#
# This is the step the probe was built to de-risk. The probe proved the
# toolchain, the C ABI and bundled SQLite all work; it deliberately used a
# minimal crate, so rslib's own dependency tree is still unproven. This
# script is where that gets answered.
#
# The flags live in ohos-env.sh, shared with build.sh.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=build-ohos/ohos-env.sh
source "${root}/build-ohos/ohos-env.sh"

out_dir="${root}/target/${triple}/release"

# --- protoc ---------------------------------------------------------------
# protoc is a HOST tool, not a target tool: the Windows binary that already
# builds the Android artifact is the right one here too. Anki pins 31.1
# because prost-generated code is version-sensitive.
export PROTOC="${PROTOC:-$root/tools/protoc/bin/protoc}"
if [[ ! -x "${PROTOC}" ]]; then
  echo "missing protoc at ${PROTOC} (Anki pins 31.1). See README.md." >&2
  exit 2
fi
export PROTOC_BINARY="${PROTOC_BINARY:-$PROTOC}"

# --- FTL submodules -------------------------------------------------------
if [[ ! -d "${root}/anki/ftl/core-repo/core" ]]; then
  echo "Anki FTL submodules are missing. Run:" >&2
  echo "  git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo" >&2
  exit 2
fi

# --- patches must already be applied --------------------------------------
# build-android/apply_patches.sh exists because a fresh `git submodule
# update` resets rslib to upstream. Here the tree is already patched, and
# re-applying would fail or double-apply. So assert instead of apply: if the
# submodule diff is empty, the tree was reset and the caller must re-patch.
#
# `git diff` (not --name-only): the marker we need is a string inside the
# diff, not a filename.
submodule_diff="$(git -C "${root}/anki" diff 2>/dev/null || true)"
if [[ -z "${submodule_diff}" ]]; then
  cat >&2 <<'MSG'
error: the anki submodule has no local modifications, so the Turna patches
are not applied. build-ohos does not apply them (re-applying to an
already-patched tree fails). Run, from the repo root:
    bash native/turna_anki_core/build-android/apply_patches.sh
MSG
  exit 2
fi
patched="$(printf '%s\n' "${submodule_diff}" | grep -c '^+++ ' || true)"
echo "  patches:    ${patched} rslib file(s) modified"

echo "turna_anki_core OHOS engine bridge build"
echo "  root:        ${root}"
echo "  sdk_native:  ${sdk_native}"
echo "  sysroot:     ${sysroot}"
echo "  clang:       ${clang} ($("${clang}" --version | head -1))"
echo "  rustc:       $(rustc --version)"
echo "  PROTOC:      ${PROTOC} ($("${PROTOC}" --version))"
echo "  target:      ${triple}"
echo "  output:      ${out_dir}/libturna_anki.so"

if command -v rustup >/dev/null 2>&1; then
  rustup target add "${triple}"
fi

cd "${root}"

# NOT cargo-ndk: that is an Android-only wrapper. OHOS is driven by plain
# cargo plus the linker/CC configuration in ohos-env.sh.
echo "  building..."
cargo build --release --target "${triple}"

so="${out_dir}/libturna_anki.so"
if [[ ! -f "${so}" ]]; then
  echo "cargo finished but ${so} is missing" >&2
  exit 1
fi

bash "${root}/build-ohos/verify_bridge_symbols.sh" "${so}"
