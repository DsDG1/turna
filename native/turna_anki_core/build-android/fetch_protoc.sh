#!/usr/bin/env bash
# Fetch the protoc release Anki pins (31.1) into tools/protoc (gitignored).
# Used by CI runners that have no protoc. Local builds that already have a
# 31.x protoc elsewhere can keep exporting PROTOC=/path/to/protoc instead.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="31.1"
dest="$root/tools/protoc"
bin="$dest/bin/protoc"

if [[ -x "$bin" ]]; then
  echo "protoc already present: $("$bin" --version)"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) plat="linux-x86_64" ;;
  Linux-aarch64) plat="linux-aarch_64" ;;
  Darwin-x86_64) plat="osx-x86_64" ;;
  Darwin-arm64) plat="osx-aarch_64" ;;
  *)
    echo "unsupported platform for protoc download: $(uname -s)-$(uname -m)" >&2
    exit 2
    ;;
esac

tmp="$(mktemp -d)"
url="https://github.com/protocolbuffers/protobuf/releases/download/v${version}/protoc-${version}-${plat}.zip"
echo "fetching $url"
curl -fsSL -o "$tmp/protoc.zip" "$url"
mkdir -p "$dest"
unzip -q -o "$tmp/protoc.zip" -d "$dest"
rm -rf -- "$tmp"
exec "$bin" --version
