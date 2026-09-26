#!/usr/bin/env bash
# Builds iOS static-library slices (device arm64 + simulator arm64/x86_64 —
# the Runner project builds both sim archs) and packs them into
# ios/Frameworks/TurnaAnki.xcframework for the Xcode project.
# Mirrors build-android/build.sh: same patches, same protoc pin, same FTL
# submodule requirement.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
project="$(cd "$root/../.." && pwd)"
deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)

# Rust links iOS objects against the oldest-supported libSystem by default
# (iOS 10), which pulls in ___chkstk_darwin and fails at link. Building a
# staticlib avoids the Rust-side link entirely for the app, but the cdylib
# slice still links during `cargo build`, so set the deployment target.
export IPHONEOS_DEPLOYMENT_TARGET="${deployment_target}"

export PROTOC="${PROTOC:-$root/tools/protoc/bin/protoc}"
export PROTOC_BINARY="${PROTOC_BINARY:-$PROTOC}"
if [[ ! -x "${PROTOC}" ]]; then
  echo "missing protoc at ${PROTOC} (Anki pins 31.1). See README.md / build-android/fetch_protoc.sh." >&2
  exit 2
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found; Xcode is required to pack the xcframework." >&2
  exit 2
fi

bash "$root/build-android/apply_patches.sh"
if [[ ! -d "$root/anki/ftl/core-repo/core" ]]; then
  echo "Anki FTL submodules are missing. Run:" >&2
  echo "  git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo" >&2
  exit 2
fi

if command -v rustup >/dev/null 2>&1; then
  # rustup resolves the active toolchain from the cwd, so run from inside the
  # crate root: otherwise targets land on the default toolchain instead of the
  # one pinned by rust-toolchain.toml and cargo fails for want of std.
  (cd "${root}" && rustup target add "${targets[@]}")
fi

device_lib="${root}/target/aarch64-apple-ios/release/libturna_anki.a"
sim_arm_lib="${root}/target/aarch64-apple-ios-sim/release/libturna_anki.a"
sim_x64_lib="${root}/target/x86_64-apple-ios/release/libturna_anki.a"
sim_lib="${root}/target/libturna_anki-sim-fat.a"
headers="${root}/bridge/include"
frameworks="${project}/ios/Frameworks"

echo "turna_anki_core iOS build"
echo "  root:            ${root}"
echo "  deployment:      ${deployment_target}"
echo "  targets:         ${targets[*]}"
echo "  PROTOC:          ${PROTOC} ($("${PROTOC}" --version))"
echo "  rustc:           $(rustc --version)"
echo "  output:          ${frameworks}/TurnaAnki.xcframework"

cd "${root}"
for target in "${targets[@]}"; do
  echo "building ${target} (release)"
  cargo build --release --target "${target}"
done

for lib in "${device_lib}" "${sim_arm_lib}" "${sim_x64_lib}"; do
  if [[ ! -f "${lib}" ]]; then
    echo "cargo finished but ${lib} is missing" >&2
    exit 1
  fi
done

# The xcframework needs one simulator slice covering both sim archs, so the
# arm64-sim and x86_64 archives are lipo'd into a fat archive first.
lipo -create "${sim_arm_lib}" "${sim_x64_lib}" -output "${sim_lib}"

mkdir -p "${frameworks}"
rm -rf "${frameworks}/TurnaAnki.xcframework"
xcodebuild -create-xcframework \
  -library "${device_lib}" -headers "${headers}" \
  -library "${sim_lib}" -headers "${headers}" \
  -output "${frameworks}/TurnaAnki.xcframework"

bash "${root}/build-ios/verify_symbols.sh" "${device_lib}"
bash "${root}/build-ios/verify_symbols.sh" "${sim_lib}"

echo "wrote ${frameworks}/TurnaAnki.xcframework"
