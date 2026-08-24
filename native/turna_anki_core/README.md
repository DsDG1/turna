# turna_anki_core

Turna’s pinned official Anki Rust core and C ABI. Phase 0 is a spike: it
must not change production import, render, or SRS paths.

## Upstream pin

| Field | Value |
|---|---|
| upstream repository | https://github.com/ankitects/anki |
| upstream commit | `967aa0d578fc75181e292e95326f9b58698da25c` |
| git describe | `25.09.2-370-g967aa0d57` |
| Rust toolchain | `1.97.1` (see `rust-toolchain.toml`) |
| Anki license | GNU AGPL v3 or later (`licenses/ANKI-LICENSE`) |
| Turna patches | `0001-export-progress-state` (`pub use ProgressState`) · `0002-export-clear-study-queues` (`pub fn clear_study_queues` for off-queue answers) · `0003-export-encode-iri-paths` (`pub fn encode_iri_paths` for the bridge display module) |
| reproducible tree | `git submodule update --init anki && git -C anki apply ../patches/000*.patch` (the working tree must contain exactly these three applied patches and nothing else) |
| last compatibility run | not run; Phase 0 in progress |

Do **not** follow `origin/main`. Do **not** add a Cargo path that points at
`/home/.../anki`. The only allowed path dependency is
`native/turna_anki_core/anki/...`.

Refresh the pin:

```bash
git -C native/turna_anki_core/anki fetch origin
# then checkout an explicit commit and update this table + the phase report
git -C native/turna_anki_core/anki rev-parse HEAD
git -C native/turna_anki_core/anki describe --tags --always
```

CI should fail if `git submodule status` does not match the commit above.

## Layout

```text
native/turna_anki_core/
├── anki/                 # git submodule, detached at the pin
├── bridge/               # cdylib + rlib, Turna C ABI
├── contract/             # Turna-owned schema, not upstream protobuf
├── build-android/        # Android arm64 scripts (commands unverified)
├── licenses/
└── patches/              # 0001-export-progress-state only
```

## Host commands (P0-002)

Once Rust `1.97.1` is installed. `rslib` proto codegen needs `protoc` 31.1
(the version Anki’s ninja graph pins). A verified copy can live in
`tools/protoc/` (gitignored):

```bash
cd native/turna_anki_core
export PROTOC="$PWD/tools/protoc/bin/protoc"
export PROTOC_BINARY="$PROTOC"
cargo test -p turna_anki_bridge
cargo build -p turna_anki_bridge
```

The first `anki` path-dep build also requires Anki’s FTL submodules:

```bash
git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
```

P0-002 adds `anki = { path = "anki/rslib" }`. The root crate is a
standalone package (not a Cargo workspace) because `rslib` already
belongs to the Anki workspace. Host builds also enable tokio `io-util`
so feature unification matches Anki’s full workspace.

## Android commands (P0-003, verified)

```bash
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
export ANDROID_HOME=...   # NDK 28.2.13676358 must be installed
./build-android/build.sh
```

See `build-android/README.md` for the frozen toolchain table.

## Fixtures (P0-005)

```bash
./tool/official_anki_spike/generate_fixtures.sh
./tool/official_anki_spike/generate_fixtures.sh --large 5000
```

Small packages live in `test/fixtures/anki_official/`. Large ones are
gitignored under `generated/`.

## Collection lifecycle (P0-006)

Handles are `u64` registry IDs, never raw `Collection` pointers. The
engine state machine is `Created → Open → Closed → released`. Dart
opens files only under `<app-support>/anki-spike/<run-id>/`.

```bash
cd native/turna_anki_core
PROTOC="$PWD/tools/protoc/bin/protoc" PROTOC_BINARY="$PROTOC" cargo test
```

## License / source offer (P0-012)

Engineering conclusion: **GO WITH CONDITIONS**.
See `licenses/THIRD-PARTY-NOTICES-DRAFT.md` and `licenses/SOURCE-OFFER.md`.
Turna GPLv3 does not finish Anki AGPL duties.

## Spike isolation

- Temporary collections live under `<app-support>/anki-spike/<run-id>/`.
- Dart code belongs in `lib/application/anki_official/spike/`.
- Do not write Turna `anki_notes`, Turna SRS, or a user profile Collection.
