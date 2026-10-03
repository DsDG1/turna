#!/usr/bin/env bash
# Cross-compile the OpenHarmony probe and verify it.
#
# Produces probe-ohos/target/aarch64-unknown-linux-ohos/release/libturna_anki_probe.so
#
# The toolchain flags live in ohos-env.sh, shared with build-bridge.sh: the
# failure modes they work around are non-obvious enough that a second copy
# would drift. See README.md for what each one answers.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
probe="${root}/probe-ohos"

# shellcheck source=build-ohos/ohos-env.sh
source "${root}/build-ohos/ohos-env.sh"

echo "turna_anki_core OHOS probe build"
echo "  root:        ${root}"
echo "  sdk_native:  ${sdk_native}"
echo "  sysroot:     ${sysroot}"
echo "  clang:       ${clang} ($("${clang}" --version | head -1))"
echo "  rustc:       $(rustc --version)"
echo "  target:      ${triple}"
echo "  output:      ${probe}/target/${triple}/release/libturna_anki_probe.so"

# Prebuilt std for this target ships with the 1.97.1 stable channel
# (rust-std-1.97.1-aarch64-unknown-linux-ohos.tar.xz, 28.7 MB). So this is a
# plain Tier-3-with-std target: no -Z build-std, no nightly.
if command -v rustup >/dev/null 2>&1; then
  rustup target add "${triple}"
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
