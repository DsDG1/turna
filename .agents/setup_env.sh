#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

FLUTTER_VERSION="3.44.5"
FLUTTER_TARBALL_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_TARBALL_SHA256="28aa13854feb9de44a317b97c4e886ea3f0af744027418b7e63885cfcd2951f3"
RUST_TOOLCHAIN="1.97.1"

# 1. Persist PATH and toolchain env vars idempotently in ~/.bashrc.
touch "$HOME/.bashrc"
sed -i '/case \$- in/,/esac/d' "$HOME/.bashrc" 2>/dev/null || true

append_bashrc_line() {
  local line="$1"
  grep -qxF "$line" "$HOME/.bashrc" || printf '%s\n' "$line" >> "$HOME/.bashrc"
}

if [[ -d /usr/lib/jvm/java-17-openjdk-amd64 ]]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
  append_bashrc_line 'export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"'
fi

export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"
export PATH="$HOME/.venv/bin:$HOME/flutter/bin:$HOME/.cargo/bin:/usr/local/cargo/bin:$PATH"

append_bashrc_line 'export RUSTUP_HOME="$HOME/.rustup"'
append_bashrc_line 'export CARGO_HOME="$HOME/.cargo"'
append_bashrc_line 'export PATH="$HOME/.venv/bin:$HOME/flutter/bin:$HOME/.cargo/bin:/usr/local/cargo/bin:$PATH"'

mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"

# 2. Python virtual environment + GUI/course tool dependencies.
venv_dir="$HOME/.venv"
venv_py="$venv_dir/bin/python"
if [[ ! -x "$venv_py" ]]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv "$venv_dir"
  else
    python3 -m venv "$venv_dir"
  fi
fi

stamp_file="$venv_dir/.turna_pyproject.sha256"
expected_sha="$(sha256sum "$repo_root/tool/gui/pyproject.toml" | awk '{print $1}')"
current_sha="$(cat "$stamp_file" 2>/dev/null || true)"

if [[ "$current_sha" != "$expected_sha" ]] || ! "$venv_py" -c 'import PySide6, yaml, ruff, PIL, fitz, docx, PyPDF2, keyring' >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$venv_py" "$repo_root/tool/gui[dev,ocr]" pyyaml
  else
    "$venv_py" -m pip install --no-input "$repo_root/tool/gui[dev,ocr]" pyyaml
  fi
  if [[ -d "$repo_root/tool/gui/turna_gui.egg-info" ]] && ! git ls-files --error-unmatch tool/gui/turna_gui.egg-info >/dev/null 2>&1; then
    rm -rf "$repo_root/tool/gui/turna_gui.egg-info"
  fi
  printf '%s\n' "$expected_sha" > "$stamp_file"
fi

# 3. Pinned Flutter SDK (3.44.5).
flutter_dir="$HOME/flutter"
flutter_ver_json="$flutter_dir/bin/cache/flutter.version.json"
installed_flutter_ver=""
if [[ -f "$flutter_ver_json" ]]; then
  installed_flutter_ver="$("$venv_py" -c "import json,sys; print(json.load(open(sys.argv[1])).get('flutterVersion',''))" "$flutter_ver_json" 2>/dev/null || true)"
elif [[ -x "$flutter_dir/bin/flutter" ]]; then
  installed_flutter_ver="$("$flutter_dir/bin/flutter" --version --machine 2>/dev/null | "$venv_py" -c "import json,sys; print(json.load(sys.stdin).get('frameworkVersion',''))" 2>/dev/null || true)"
fi

if [[ "$installed_flutter_ver" != "$FLUTTER_VERSION" ]]; then
  if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
    echo "error: automated Flutter install only supports Linux-x86_64" >&2
    exit 1
  fi
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$tmp_dir"' EXIT
  tarball="$tmp_dir/flutter.tar.xz"
  curl -fsSL -o "$tarball" "$FLUTTER_TARBALL_URL"
  printf '%s  %s\n' "$FLUTTER_TARBALL_SHA256" "$tarball" | sha256sum -c -
  rm -rf "$flutter_dir"
  tar -xJf "$tarball" -C "$HOME"
  rm -rf -- "$tmp_dir"
  trap - EXIT
fi

"$flutter_dir/bin/flutter" config --no-analytics >/dev/null

# 4. Pinned Rust toolchain (1.97.1 with rustfmt + clippy).
if command -v rustup >/dev/null 2>&1; then
  if ! rustup toolchain list | grep -q "^${RUST_TOOLCHAIN}-"; then
    rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal --component rustfmt,clippy --no-self-update
  fi
  if ! rustup show active-toolchain 2>/dev/null | grep -q "^${RUST_TOOLCHAIN}-"; then
    rustup default "$RUST_TOOLCHAIN" >/dev/null 2>&1
  fi
fi

# 5. Pinned protoc (31.1) for native/turna_anki_core.
bash "$repo_root/native/turna_anki_core/build-android/fetch_protoc.sh"

# 6. Flutter / Dart package resolution (best-effort when gitcode.com is blocked in cloud VMs).
if "$flutter_dir/bin/flutter" pub get --offline >/dev/null 2>&1; then
  :
elif curl -fs --max-time 8 -o /dev/null "https://gitcode.com/openharmony-sig/flutter_plus_plugins.git/info/refs?service=git-upload-pack" 2>/dev/null; then
  "$flutter_dir/bin/flutter" pub get
else
  echo "warning: gitcode.com is unreachable (likely cloud WAF HTTP 418); skipping 'flutter pub get'. Python/GUI/Rust tools are ready." >&2
fi
