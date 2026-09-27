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
| Turna patches | `0001-export-progress-state` (`pub use ProgressState`) · `0002-export-clear-study-queues` (`pub fn clear_study_queues` for off-queue answers) · `0003-export-encode-iri-paths` (`pub fn encode_iri_paths` for the bridge display module) · `0004-export-import-progress-view` + `0005-export-import-progress-view-reexport` (`ImportProgressView` for `LATEST_PROGRESS`) · `0006-import-apkg-media-toggle-and-foreign-collection` (staged import / `PROMOTE_STAGING_COLLECTION`) |
| reproducible tree | `git submodule update --init anki && git -C anki apply ../patches/000*.patch` (the working tree must contain exactly the six applied patches and nothing else) |
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
├── bridge/               # cdylib + rlib + staticlib, Turna C ABI
├── contract/             # Turna-owned schema, not upstream protobuf
├── build-android/        # Android arm64 scripts (commands unverified)
├── build-ios/            # iOS staticlib + xcframework scripts
├── licenses/
└── patches/              # 0001..0006 (see patches/README.md)
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

## iOS static-library commands

`bridge` declares `crate-type = ["cdylib", "rlib", "staticlib"]`. The
`staticlib` slice is what iOS links: an `.xcframework` of static archives,
not a dylib (iOS has no app-bundled `dlopen`).

> **The product is NOT committed.** `ios/Frameworks/TurnaAnki.xcframework/`
> is listed in `.gitignore`, and a fresh clone has no `ios/Frameworks`
> directory at all. `ios/Runner.xcodeproj/project.pbxproj` references
> `Frameworks/TurnaAnki.xcframework` unconditionally, so **you must run
> `build-ios/build.sh` before any `flutter build ios` / `flutter run` on a
> clean checkout** — cloning is not enough, and there is no CI job that
> produces it for you (every workflow in `.github/workflows/` runs on
> `ubuntu-latest`; no macOS runner exists).

| Item | Value |
|---|---|
| Rust targets | `aarch64-apple-ios` (device) · `aarch64-apple-ios-sim` + `x86_64-apple-ios` (simulator, lipo'd into one fat slice) |
| Deployment target | `IPHONEOS_DEPLOYMENT_TARGET`, default `15.0` (overridable via env; must match the Runner target's `15.0`) |
| Headers | `bridge/include` (ships `turna_anki.h` inside the xcframework) |
| protoc | `31.1`, resolved from `tools/protoc/bin/protoc` (gitignored) or `$PROTOC` |
| Tooling | Xcode (`xcodebuild`, `lipo`, `xcrun -f nm`) — the pack step cannot run without it |
| Output | `ios/Frameworks/TurnaAnki.xcframework` |

```bash
cd native/turna_anki_core
git submodule update --init anki
git -C anki apply ../patches/000*.patch
git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
export PROTOC="$PWD/tools/protoc/bin/protoc"     # or run build-android/fetch_protoc.sh
export PROTOC_BINARY="$PROTOC"
./build-ios/build.sh
```

`build.sh` then, in order: applies `build-android/apply_patches.sh`,
requires the FTL submodules, `rustup target add`s the three targets,
`cargo build --release` per target, `lipo -create`s the two simulator
archives into `target/libturna_anki-sim-fat.a`, runs
`xcodebuild -create-xcframework` (device + fat simulator, both with
`bridge/include` as headers) into `ios/Frameworks/`, and finally runs
`verify_symbols.sh` on the device archive and the fat simulator archive.

It also exports `IPHONEOS_DEPLOYMENT_TARGET` for the whole script: Rust
links iOS objects against the oldest supported libSystem (iOS 10) by
default, which drags in `___chkstk_darwin` and fails at link time — the
`cdylib` slice is still linked during `cargo build`, so the target must
be set even though the app consumes the `staticlib`.

### Xcode linkage (as committed in `ios/Runner.xcodeproj/project.pbxproj`)

- `TurnaAnki.xcframework` is a `PBXFileReference` at path
  `Frameworks/TurnaAnki.xcframework` and a `PBXBuildFile` in the Runner
  target's **Frameworks** build phase.
- All three Runner configurations (Debug / Release / Profile) carry
  `OTHER_LDFLAGS` with `-lc++` plus one `-Wl,-u,_<symbol>` per exported
  entry point — `_turna_anki_abi_version`, `_turna_anki_engine_new`,
  `_turna_anki_engine_open`, `_turna_anki_call`, `_turna_anki_cancel`,
  `_turna_anki_engine_close`, `_turna_anki_buffer_free`. `-u` forces the
  linker to keep the symbol so `DynamicLibrary.process()` can find it at
  runtime; without it the static linker drops the unreferenced objects.
- `STRIP_STYLE = non-global` and `ENABLE_BITCODE = NO` on those same
  configurations: a global strip would remove the C symbols from the
  final binary.
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0`, `SWIFT_VERSION = 5.0`.
- Dart side opens the library differently per platform
  (`lib/application/anki_official/engine/official_anki_native_transport.dart`,
  `official_anki_native_availability.dart`): on iOS they probe
  `DynamicLibrary.process()` and look up `turna_anki_abi_version`
  directly, because there is no file to `DynamicLibrary.open`.

### Verifying the iOS build

```bash
./build-ios/verify_symbols.sh target/aarch64-apple-ios/release/libturna_anki.a
cd ../..
flutter build ios --simulator --no-codesign
```

`verify_symbols.sh` requires an arm64 slice, all seven exported
`turna_anki_*` symbols as `T` entries, and a size ≥ 2 MiB (so a
DCE-stripped crate fails loudly). `build.sh` already runs it for you.

### iOS status and known gaps

- Wired up in commit `ec0170ae` (2026-09-26): the xcframework links and
  the seven symbols land in `Runner.debug.dylib` under
  `flutter build ios --simulator --no-codesign`; the WKWebView reviewer
  (`ios/Runner/AnkiReviewer/`) was exercised E2E on an iOS simulator with
  a real `.apkg` (receipt: `test/BASELINE.md` 2026-09-26 「iOS 官方 Anki 栈接通」).
- **Unverified:** a real-device / release build of the iOS stack, and any
  macOS/Catalyst run (`SUPPORTS_MACCATALYST = NO`). No macOS CI runner
  exists to cover any of it.
- Re-run `build-ios/build.sh` whenever the upstream pin, the six
  patches, or the bridge's exported symbol set changes — the pbxproj
  `-Wl,-u` list and `verify_symbols.sh` both hard-code those seven names.

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
