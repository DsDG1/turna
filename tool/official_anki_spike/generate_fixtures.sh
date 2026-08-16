#!/usr/bin/env bash
# Generate official-rslib fixtures. Small packages are committed; pass
# --large [count] to also write gitignored generated/ packages.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
core="$root/native/turna_anki_core"
out="$root/test/fixtures/anki_official"
export PROTOC="${PROTOC:-$core/tools/protoc/bin/protoc}"
export PROTOC_BINARY="${PROTOC_BINARY:-$PROTOC}"
cd "$core"
exec cargo run --release --bin turna_anki_gen_fixtures -- --out "$out" "$@"
