#!/bin/sh
# Xcode Run Script phase: embeds the prebuilt libturna_anki.dylib slice for
# the active SDK into Runner.app/Frameworks and signs it with the app's
# identity when one is active.
#
# A missing slice is NOT an error: iOS builds without the Rust toolchain keep
# working — DynamicLibrary.open('@executable_path/Frameworks/...') then fails
# and the Dart-side availability probe fails closed, matching the platform
# policy. Build slices first with:
#   bash native/turna_anki_core/build-ios/build.sh
set -eu

case "${EFFECTIVE_PLATFORM_NAME}" in
  -iphoneos)       slice="iphoneos" ;;
  -iphonesimulator) slice="iphonesimulator" ;;
  *)
    echo "turna_anki: unsupported platform ${EFFECTIVE_PLATFORM_NAME}; skipping embed"
    exit 0
    ;;
esac

src="${SRCROOT}/Frameworks/${slice}/libturna_anki.dylib"
if [ ! -f "${src}" ]; then
  echo "turna_anki: ${src} absent (run build-ios/build.sh); skipping embed"
  exit 0
fi

frameworks_dir="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
mkdir -p "${frameworks_dir}"
cp "${src}" "${frameworks_dir}/libturna_anki.dylib"
install_name_tool -id "@rpath/libturna_anki.dylib" \
  "${frameworks_dir}/libturna_anki.dylib"

identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -n "${identity}" ] && [ "${identity}" != "-" ]; then
  codesign --force --sign "${identity}" --timestamp=none \
    "${frameworks_dir}/libturna_anki.dylib"
fi
echo "turna_anki: embedded ${slice} slice into Frameworks/"
