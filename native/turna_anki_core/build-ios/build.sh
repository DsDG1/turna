#!/usr/bin/env bash
# Builds libturna_anki.dylib for iOS device + simulator and stages the slices
# under ios/Frameworks/{iphoneos,iphonesimulator}/. The Xcode embed phase
# (embed_dylib.sh) copies the matching slice into Runner.app/Frameworks;
# absent slices are skipped so builds without the Rust toolchain still work
# (the Dart-side probe then fails closed and Anki stays unavailable).
#
# Usage: build.sh            # both slices
#        build.sh device     # aarch64-apple-ios only
#        build.sh sim        # aarch64-apple-ios-sim only
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$(cd "$root/../.." && pwd)"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

export PROTOC="${PROTOC:-$root/tools/protoc/bin/protoc}"
export PROTOC_BINARY="${PROTOC_BINARY:-$PROTOC}"
if [[ ! -x "${PROTOC}" ]]; then
  echo "missing protoc at ${PROTOC} (Anki pins 31.1)." >&2
  echo "Run build-android/fetch_protoc.sh or export PROTOC=/path/to/protoc." >&2
  exit 2
fi

bash "$root/build-android/apply_patches.sh"
if [[ ! -d "$root/anki/ftl/core-repo/core" ]]; then
  echo "Anki FTL submodules are missing. Run:" >&2
  echo "  git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo" >&2
  exit 2
fi

mode="${1:-both}"
case "${mode}" in
  both)   targets="aarch64-apple-ios aarch64-apple-ios-sim" ;;
  device) targets="aarch64-apple-ios" ;;
  sim)    targets="aarch64-apple-ios-sim" ;;
  *)
    echo "unknown mode '${mode}' (both|device|sim)" >&2
    exit 2
    ;;
esac

if command -v rustup >/dev/null 2>&1; then
  rustup target add ${targets}
fi

echo "turna_anki_core iOS build"
echo "  root:        ${root}"
echo "  targets:     ${targets}"
echo "  min iOS:     ${IPHONEOS_DEPLOYMENT_TARGET}"
echo "  PROTOC:      ${PROTOC} ($("${PROTOC}" --version))"
echo "  rustc:       $(rustc --version)"

cd "${root}"
for target in ${targets}; do
  cargo build --release --target "${target}"
done

out="${project}/ios/Frameworks"
stage() {
  local target="$1" sdk="$2"
  local src="target/${target}/release/libturna_anki.dylib"
  local dst="${out}/${sdk}"
  mkdir -p "${dst}"
  cp "${src}" "${dst}/libturna_anki.dylib"
  install_name_tool -id "@rpath/libturna_anki.dylib" \
    "${dst}/libturna_anki.dylib"
  if ! nm -gU "${dst}/libturna_anki.dylib" | grep -q '_turna_anki_abi_version'; then
    echo "FFI symbols missing from ${sdk} slice" >&2
    exit 1
  fi
  echo "staged ${dst}/libturna_anki.dylib"
}

for target in ${targets}; do
  case "${target}" in
    aarch64-apple-ios)     stage "${target}" iphoneos ;;
    aarch64-apple-ios-sim) stage "${target}" iphonesimulator ;;
  esac
done
