#!/usr/bin/env bash
# Verified command for P0-003. Prints toolchain facts, then produces
# android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$(cd "$root/../.." && pwd)"
ndk_revision="28.2.13676358"
platform="24"
abi="arm64-v8a"

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}/ndk/${ndk_revision}" ]]; then
    export ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${ndk_revision}"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}/ndk/${ndk_revision}" ]]; then
    export ANDROID_NDK_HOME="${ANDROID_SDK_ROOT}/ndk/${ndk_revision}"
  else
    echo "ANDROID_NDK_HOME is unset and NDK ${ndk_revision} was not found." >&2
    exit 2
  fi
fi

if [[ ! -d "${ANDROID_NDK_HOME}" ]]; then
  echo "ANDROID_NDK_HOME does not exist: ${ANDROID_NDK_HOME}" >&2
  exit 2
fi

ndk_name="$(basename "${ANDROID_NDK_HOME}")"
if [[ "${ndk_name}" != "${ndk_revision}" ]]; then
  echo "warning: ANDROID_NDK_HOME is ${ndk_name}, expected ${ndk_revision}" >&2
fi

export PROTOC="${PROTOC:-$root/tools/protoc/bin/protoc}"
export PROTOC_BINARY="${PROTOC_BINARY:-$PROTOC}"
if [[ ! -x "${PROTOC}" ]]; then
  echo "missing protoc at ${PROTOC} (Anki pins 31.1). See README.md." >&2
  exit 2
fi

bash "$root/build-android/apply_patches.sh"
if [[ ! -d "$root/anki/ftl/core-repo/core" ]]; then
  echo "Anki FTL submodules are missing. Run:" >&2
  echo "  git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo" >&2
  exit 2
fi

if ! command -v cargo-ndk >/dev/null 2>&1 && ! cargo ndk --version >/dev/null 2>&1; then
  echo "cargo-ndk is not installed. Pin: cargo install cargo-ndk --version 4.1.2 --locked" >&2
  exit 2
fi

jni_out="${project}/android/app/src/main/jniLibs"
mkdir -p "${jni_out}"

echo "turna_anki_core Android arm64 build"
echo "  root:            ${root}"
echo "  ANDROID_NDK_HOME:${ANDROID_NDK_HOME}"
echo "  platform:        ${platform}"
echo "  abi:             ${abi}"
echo "  PROTOC:          ${PROTOC} ($("${PROTOC}" --version))"
echo "  rustc:           $(rustc --version)"
echo "  cargo-ndk:       $(cargo ndk --version 2>/dev/null || cargo-ndk --version)"
echo "  output:          ${jni_out}/${abi}/libturna_anki.so"

cd "${root}"
if command -v rustup >/dev/null 2>&1; then
  rustup target add aarch64-linux-android
fi
cargo ndk \
  -t "${abi}" \
  --platform "${platform}" \
  -o "${jni_out}" \
  build \
  --release

so="${jni_out}/${abi}/libturna_anki.so"
if [[ ! -f "${so}" ]]; then
  echo "cargo-ndk finished but ${so} is missing" >&2
  exit 1
fi

exec bash "${root}/build-android/verify_symbols.sh" "${so}"
