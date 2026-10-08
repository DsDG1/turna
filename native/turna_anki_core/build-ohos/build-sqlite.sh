#!/usr/bin/env bash
# Cross-compile libsqlite3.so for OpenHarmony (ADR 0050 §6 step 2).
#
# Produces target/aarch64-unknown-linux-ohos/release/libsqlite3.so
#
# WHY THIS EXISTS
#   The Anki engine's SQLite is bundled and statically linked into
#   libturna_anki.so. That one works on device. What does NOT work is the
#   OTHER sqlite3 in this project: the FFI library the shared catalog opens
#   through package:sqlite3. HarmonyOS ships no libsqlite3.so, and ADR 0050
#   §4.1 records the resulting failure verbatim:
#     UnsupportedError: Unsupported operation: Unsupported platform: ohos
#   So the catalog needs its own copy, built here and shipped in the hap.
#
# SOURCE
#   The SQLite amalgamation vendored by libsqlite3-sys, the same crate the
#   engine already builds against — so the catalog and the engine cannot drift
#   apart on version. Override with SQLITE_AMALGAMATION to build another.
#
# FLAGS
#   Default amalgamation build. FTS5 and the JSON1 functions are deliberately
#   NOT enabled: nothing in lib/ references either (checked), and an omitted
#   extension fails loudly at prepare time while a half-working one would not.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=build-ohos/ohos-env.sh
source "${root}/build-ohos/ohos-env.sh"

out_dir="${root}/target/${triple}/release"
mkdir -p "${out_dir}"

# --- locate the amalgamation ---------------------------------------------
amalgamation="${SQLITE_AMALGAMATION:-}"
if [[ -z "${amalgamation}" ]]; then
  # The cargo registry layout is <root>/<registry-hash>/libsqlite3-sys-<ver>/.
  for candidate in "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/libsqlite3-sys-*/sqlite3/sqlite3.c; do
    if [[ -f "${candidate}" ]]; then amalgamation="${candidate}"; fi
  done
fi
if [[ -z "${amalgamation}" || ! -f "${amalgamation}" ]]; then
  cat >&2 <<'MSG'
error: no sqlite3 amalgamation found.

Looked in the cargo registry for libsqlite3-sys-*/sqlite3/sqlite3.c (the copy
the Anki engine already compiles). If the registry layout differs on this
machine, point SQLITE_AMALGAMATION at an amalgamation directly:

  SQLITE_AMALGAMATION=/path/to/sqlite3.c build-ohos/build-sqlite.sh
MSG
  exit 2
fi

echo "amalgamation: ${amalgamation}"
echo "             version: $(sed -n 's/^#define SQLITE_VERSION  *"\(.*\)"/\1/p' "${amalgamation}" | head -1)"

# -fPIC + -shared because the Dart side dlopen()s it; the engine bridge is
# built as a staticlib, so this is the first shared object in the tree and the
# reason the flags are spelled out rather than inherited.
# -O2 because amalgamation-at-O0 is ~3x slower on catalog migrations.
# -fvisibility=hidden would break the sqlite3_* exports the Dart bindings
# resolve, so it is deliberately absent.
"${clang}" \
  --target="${triple}" \
  --sysroot="${sysroot}" \
  -fPIC -shared -O2 \
  -fvisibility=default \
  -DSQLITE_THREADSAFE=1 \
  -DSQLITE_DEFAULT_FOREIGN_KEYS=0 \
  -DSQLITE_ENABLE_COLUMN_METADATA=1 \
  -DSQLITE_DQS=0 \
  -o "${out_dir}/libsqlite3.so" \
  "${amalgamation}"

echo "built ${out_dir}/libsqlite3.so"
"${llvm_bin}/llvm-readelf" -d "${out_dir}/libsqlite3.so" 2>/dev/null \
  | grep -E 'NEEDED|SONAME' || true