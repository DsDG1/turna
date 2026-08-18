#!/usr/bin/env bash
# Compute the four-segment official native identity chain.
# Does not hand-fill hashes. Any mismatch exits 1.
set -euo pipefail

project="$(cd "$(dirname "$0")/.." && pwd)"
core="$project/native/turna_anki_core"
abi="arm64-v8a"
so_name="libturna_anki.so"
built="$core/target/aarch64-linux-android/release/$so_name"
jni="$project/android/app/src/main/jniLibs/$abi/$so_name"
apk="${OFFICIAL_ANKI_APK:-}"
out="${OFFICIAL_ANKI_HASH_OUT:-$project/docs/official-anki-migration/artifacts/p4r2/native-hash-manifest.txt}"
package="${OFFICIAL_ANKI_PACKAGE:-me.dsdogs.turna}"
ndk="${ANDROID_NDK_HOME:-${ANDROID_HOME:-}/ndk/28.2.13676358}"
strip_bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

sha256() {
  sha256sum "$1" | awk '{print $1}'
}

if [[ ! -f "$built" ]]; then
  echo "missing built native: $built" >&2
  exit 2
fi
if [[ ! -f "$jni" ]]; then
  echo "missing jniLibs native: $jni" >&2
  exit 2
fi

built_hash="$(sha256 "$built")"
jni_hash="$(sha256 "$jni")"
stripped_hash=""
if [[ -x "$strip_bin" ]]; then
  tmp_strip="$(mktemp)"
  cp "$jni" "$tmp_strip"
  "$strip_bin" --strip-unneeded "$tmp_strip"
  stripped_hash="$(sha256 "$tmp_strip")"
  rm -f "$tmp_strip"
fi

apk_hash=""
apk_so_hash=""
if [[ -n "$apk" && -f "$apk" ]]; then
  apk_hash="$(sha256 "$apk")"
  tmp="$(mktemp -d)"
  unzip -p "$apk" "lib/$abi/$so_name" >"$tmp/$so_name"
  apk_so_hash="$(sha256 "$tmp/$so_name")"
  rm -rf "$tmp"
fi

device_so_hash=""
device_apk_hash=""
if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
  device_path="$(adb shell pm path "$package" 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' | head -n1 || true)"
  if [[ -n "$device_path" ]]; then
    tmp="$(mktemp -d)"
    adb pull "$device_path" "$tmp/base.apk" >/dev/null
    device_apk_hash="$(sha256 "$tmp/base.apk")"
    if unzip -p "$tmp/base.apk" "lib/$abi/$so_name" >"$tmp/$so_name" 2>/dev/null; then
      device_so_hash="$(sha256 "$tmp/$so_name")"
    fi
    rm -rf "$tmp"
  fi
fi

mkdir -p "$(dirname "$out")"
{
  echo "official native hash manifest"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "HEAD: $(git -C "$project" rev-parse HEAD)"
  echo "dirty: $(git -C "$project" status --porcelain | wc -l)"
  echo "submodule: $(git -C "$core/anki" rev-parse HEAD 2>/dev/null || echo missing)"
  echo "built: $built_hash"
  echo "jniLibs: $jni_hash"
  echo "stripped: ${stripped_hash:-MISSING}"
  echo "apk: ${apk_hash:-MISSING}"
  echo "apkSo: ${apk_so_hash:-MISSING}"
  echo "deviceApk: ${device_apk_hash:-MISSING}"
  echo "deviceSo: ${device_so_hash:-MISSING}"
} | tee "$out"

status=0
if [[ "$built_hash" != "$jni_hash" ]]; then
  echo "FAIL: built != jniLibs" >&2
  status=1
fi
if [[ -n "$stripped_hash" && -n "$apk_so_hash" && "$apk_so_hash" != "$stripped_hash" ]]; then
  echo "FAIL: apkSo != llvm-strip(jniLibs)" >&2
  status=1
fi
if [[ -n "$device_so_hash" && -n "$apk_so_hash" && "$device_so_hash" != "$apk_so_hash" ]]; then
  echo "FAIL: deviceSo != apkSo (install the APK under test)" >&2
  status=1
fi
if [[ "$status" -ne 0 ]]; then
  exit 1
fi
echo "OK: compared hashes match"
