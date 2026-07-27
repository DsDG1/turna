#!/usr/bin/env bash
#
# Re-apply OHOS-fork Android build fixes to the Flutter SDK + pub cache.
#
# Why: this project builds on the OpenHarmony Flutter fork, whose toolchain
# (flutter_tools bundles KGP 1.8.0) and fork plugins (flutter_local_notifications,
# package_info_plus) don't compile under the current AGP/Kotlin/Android-SDK without
# small source patches. These patches live in tool/patches/ and must be re-applied
# after any of:
#   - `flutter pub cache clean`
#   - `flutter pub get` that re-resolves a git dependency (ref moved)
#   - a fresh clone / update of the OHOS Flutter fork (flutter_flutter)
#
# Usage:  bash tool/apply_patches.sh
# Idempotent: skips patches whose marker is already present.
#
# Override locations via env if your machine differs:
#   PUB_CACHE=...  FLUTTER_SDK=...  bash tool/apply_patches.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES="$HERE/patches"

# --- locate Flutter SDK + pub cache ----------------------------------------
FLUTTER_SDK="${FLUTTER_SDK:-/c/Users/DsDogs/Desktop/developper/flutter_flutter}"
if [ -n "${LOCALAPPDATA:-}" ]; then
  PUB_CACHE="${PUB_CACHE:-$(cygpath -u "$LOCALAPPDATA/Pub/Cache")}"
else
  PUB_CACHE="${PUB_CACHE:-$HOME/AppData/Local/Pub/Cache}"
fi

# Find a pub-cache checkout dir by glob (robust to hash in dir name).
# Usage: find_checkout <glob relative to PUB_CACHE>
# NOTE: the glob is intentionally UNquoted so bash expands `*`. PUB_CACHE on
# this machine has no spaces; if yours does, set PUB_CACHE to a space-free path.
find_checkout() {
  local found
  found=$(ls -d ${PUB_CACHE}/$1 2>/dev/null | head -n1)
  echo "$found"
}

JNI=$(find_checkout "hosted/pub.flutter-io.cn/jni-1.0.1")
FLN=$(find_checkout "git/fluttertpc_flutter_local_notifications-*/flutter_local_notifications")
PIP=$(find_checkout "git/flutter_plus_plugins-*/packages/package_info_plus/package_info_plus")

# apply_if_needed <target_dir> <patch_file> <marker_file_rel> <marker_string>
# - marker present  -> skip (already applied)
# - else apply via classic `patch` (git apply skips unpredictably due to the
#   `index` blob-hash line in git-format diffs). patch runs from <target_dir>
#   with -p1 to strip the leading a/ b/ component.
apply_if_needed() {
  local dir="$1" patch="$2" marker_file="$3" marker="$4"
  local name
  name=$(basename "$patch")

  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "  [SKIP: target dir not found] $name"
    return
  fi
  if [ ! -f "$patch" ]; then
    echo "  [SKIP: patch file missing] $name"
    return
  fi

  if [ -f "$dir/$marker_file" ] && grep -Fq "$marker" "$dir/$marker_file"; then
    echo "  [skip: already applied] $name"
    return
  fi

  if (cd "$dir" && patch -p1 --forward --dry-run -i "$patch" >/dev/null 2>&1); then
    if (cd "$dir" && patch -p1 --forward -i "$patch" >/dev/null 2>&1); then
      echo "  [applied] $name"
    else
      echo "  [ERROR: apply failed] $name"
    fi
  else
    echo "  [WARN: conflict, marker absent but patch won't apply cleanly] $name"
  fi
}

echo "Applying OHOS-fork build patches..."
echo "  Flutter SDK: $FLUTTER_SDK"
echo "  Pub cache:   $PUB_CACHE"
echo

# B. Flutter SDK: bump flutter_tools bundled KGP 1.8.0 -> 2.0.21
apply_if_needed \
  "$FLUTTER_SDK" \
  "$PATCHES/flutter_tools-kgp-2.0.21.patch" \
  "packages/flutter_tools/gradle/build.gradle.kts" \
  "kotlin-gradle-plugin:2.0.21"

# C1. jni: extension-level -> task-level compilerOptions (KGP 1.8+ compatible)
apply_if_needed \
  "$JNI" \
  "$PATCHES/jni-task-compilerOptions.patch" \
  "android/build.gradle" \
  "tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach"

# C2. flutter_local_notifications: bigLargeIcon(null) -> bigLargeIcon((Bitmap) null)
# (the enum file is NOT patched - it exists in the fork's HEAD; only the working
#  tree was dirty. A fresh checkout has it. If missing, run: git -C <fln> checkout -- .)
apply_if_needed \
  "$FLN" \
  "$PATCHES/flutter_local_notifications-fix.patch" \
  "android/src/main/java/com/dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java" \
  "bigLargeIcon((Bitmap) null)"

# C3. package_info_plus: Kotlin null-safety (Android @RecentlyNullable under Kotlin 2.0)
apply_if_needed \
  "$PIP" \
  "$PATCHES/package_info_plus-nullsafe.patch" \
  "android/src/main/kotlin/dev/fluttercommunity/plus/packageinfo/PackageInfoPlugin.kt" \
  "info.applicationInfo?.loadLabel"

echo
echo "Done. If anything shows [ERROR] or [WARN], inspect and re-run after fixing."
echo "Reminder: Android build also needs JDK 17 as JAVA_HOME (User scope)."
