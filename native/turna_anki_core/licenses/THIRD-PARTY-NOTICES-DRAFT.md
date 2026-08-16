# Third-party notices (P0-012)

Status: **engineering inventory complete**. This is **not** a legal opinion
and does **not** replace counsel review before the first binary that ships
`libturna_anki.so`.

Conclusion: **GO WITH CONDITIONS**

Turna’s existing GPLv3 license does **not** automatically satisfy Anki’s
AGPL-3.0-or-later distribution duties.

## 1. Official Anki core

| Field | Value |
|---|---|
| Project | [ankitects/anki](https://github.com/ankitects/anki) |
| Pin | `967aa0d578fc75181e292e95326f9b58698da25c` (`25.09.2-370-g967aa0d57`) |
| Used tree | `native/turna_anki_core/anki/rslib` and its workspace path-deps (`anki_i18n`, `anki_io`, `anki_proto`, proto codegen) |
| License | GNU Affero General Public License v3 or later |
| Copy | `licenses/ANKI-LICENSE` (byte-identical to `anki/LICENSE` on the pin) |

What Turna links:

- Official `Collection` / `import_apkg` / `render_existing_card` /
  scheduler / undo / progress.
- Bundled sqlite inside the `rslib` graph (via `rusqlite`).
- No Desktop Python, no Qt, no official Reviewer Web/JS/CSS, no MathJax,
  no Anki logo assets, no AnkiWeb/sync client in Phase 0.

pylib/qt items listed in `ANKI-LICENSE` (mpv.py, jQuery, MathJax, …) are
**not** in `libturna_anki.so`.

## 2. Turna modifications of official source

| Patch | File | Change |
|---|---|---|
| `patches/0001-export-progress-state.patch` | `anki/rslib/src/lib.rs` | `pub use progress::ProgressState;` |

One-line re-export. No algorithm, schema, or renderer change. Replay:
`build-android/host-test.sh` and `build-android/build.sh` apply the patch
when the pin tree does not already contain it.

The Anki submodule pointer stays on `967aa0d…`. Do not treat the dirty
working tree as a new upstream pin.

## 3. Rust crate inventory (this lockfile)

Source of truth: `native/turna_anki_core/Cargo.lock` joined to
`anki/cargo/licenses.json` (Anki’s own license table at the pin).

```text
lock packages:                 358
matched in anki/licenses.json: 353
unlisted in that table:        5
```

Unlisted:

| Crate | License (from crate Cargo.toml in cargo cache) |
|---|---|
| `turna_anki_bridge` | AGPL-3.0-or-later (this package) |
| `find-msvc-tools` 0.1.11 | MIT OR Apache-2.0 |
| `symlink` 0.1.0 | MIT/Apache-2.0 |
| `toml_parser` 1.1.3+spec-1.1.0 | MIT OR Apache-2.0 |
| `zmij` 1.0.23 | MIT |

License buckets among the 353 matched crates:

| Count | SPDX |
|---:|---|
| 210 | Apache-2.0 OR MIT |
| 72 | MIT |
| 18 | Unicode-3.0 |
| 8 | Apache-2.0 |
| 7 | MIT OR Unlicense |
| 6 | Apache-2.0 OR Apache-2.0 WITH LLVM-exception OR MIT |
| 5 | AGPL-3.0-or-later (`anki`, `anki_i18n`, `anki_io`, `anki_proto`, `anki_proto_gen`) |
| 3 | MPL-2.0 (`cssparser`, `dtoa-short`, `option-ext`) |
| 1 | LGPL-3.0-or-later OR MPL-2.0 (`priority-queue` 2.7.0) |
| rest | BSD-2/3, ISC, Zlib, BSL-1.0, CC0, dual/triple OSI combinations |

Regenerate the counts:

```bash
cd native/turna_anki_core
python3 licenses/inventory_lockfile.py
```

Copyleft notes (engineering, not counsel):

- **AGPL-3.0-or-later** on Anki crates and this bridge is the reason a
  source offer is required for any shipped `.so`.
- **`priority-queue`** is dual `LGPL-3.0-or-later OR MPL-2.0`. Turna
  takes the **MPL-2.0** option so an LGPL-only notice is not required.
- **MPL-2.0** crates are file-level copyleft; keep their source
  available via Cargo.lock + crates.io (already implied by a full
  corresponding-source offer).
- No SSPL, Commons Clause, or known non-OSI license appeared in this
  lockfile join.

`anki_proto_gen` is AGPL and lives in the lock because `anki_proto`
build-depends on it. It is a codegen crate, not a Reviewer UI.

## 4. Official Web / Reviewer assets

Not shipped in Phase 0. The bridge and `Cargo.toml` do not reference
`qt/`, `ts/`, Sass, MathJax, or Anki logo files. A later Reviewer
WebView must re-run this inventory before adding those files.

## 5. Corresponding source

A binary that includes `libturna_anki.so` must be accompanied by
source for:

1. This Turna commit (GPLv3 app + AGPL bridge).
2. The pinned Anki tree at `967aa0d578fc75181e292e95326f9b58698da25c`.
3. `patches/0001-export-progress-state.patch`.
4. `Cargo.lock` (and therefore every crates.io crate it names).

How a user gets it:

- Git remote currently configured on this machine:
  `git@gitee.com:dhwdwf3/Varnamalaplus.git`
- Checkout the **same commit** as the shipped app
  (`git rev-parse HEAD` at build time; record it in the About page).
- `git submodule update --init native/turna_anki_core/anki`
- `git -C native/turna_anki_core/anki checkout --detach 967aa0d578fc75181e292e95326f9b58698da25c`
- Apply `patches/0001-export-progress-state.patch` if `rslib/src/lib.rs`
  does not already re-export `ProgressState`.

See `SOURCE-OFFER.md`.

## 6. Rebuild the native bridge

Documented and verified commands:

```bash
# host tests
./native/turna_anki_core/build-android/host-test.sh

# Android arm64 cdylib
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
export ANDROID_HOME=...   # NDK 28.2.13676358
./native/turna_anki_core/build-android/build.sh
```

Toolchain table: `build-android/README.md`.
`protoc` 31.1 and Anki FTL submodules are required (see core README).

This machine still cannot produce a release APK
(`flutter-plugin-loader` / `25.0.2`) and has no adb device. That is a
P0-004/P0-013 ship blocker, not a missing source-offer recipe.

## 7. In-app notices

- Debug spike page registers Anki AGPL with Flutter
  `LicenseRegistry` and shows a short source-offer line.
- Production About → “开源许可证” (`showLicensePage`) does **not** yet
  call `registerOfficialAnkiLicenses()`. That hook is a **release
  condition** before the first store build that packages
  `libturna_anki.so`.
- About still says “基于 GNU 通用公共许可证 v3.0 授权.” That sentence
  alone is insufficient once the official core ships.

## 8. GPLv3 + AGPL

Turna `LICENSE` is GPLv3. Combining with AGPL `rslib` in one APK means:

- The shipped combination must be treated as AGPL-capable corresponding
  source (users who receive the binary can take the Anki-derived parts
  under AGPL).
- AGPL §13 (network source offer) is **not** triggered by Phase 0:
  the spike does not expose AnkiWeb, sync, or a network service that
  remotely interacts with the official Collection.
- Adding AnkiWeb/sync or any remote Collection API requires a new
  review of §13.

## 9. Conditions (must hold before a public official-core binary)

1. Counsel (or an appointed license owner) signs off on this inventory.
2. About / `showLicensePage` calls `registerOfficialAnkiLicenses()`.
3. Each released APK records its exact git commit and offers the source
   in `SOURCE-OFFER.md`.
4. Do not claim “we are already GPL, so AGPL is done.”
5. Re-inventory if Reviewer web assets, AnkiWeb, or new native crates
   are added.
6. Keep taking the MPL-2.0 option on `priority-queue`.

Until (1)–(3) happen, Phase 0 may continue internally, but a store
release that includes `libturna_anki.so` is **blocked**.
