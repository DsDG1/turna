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
| Turna patches | none yet (`patches/` is empty) |
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
└── patches/              # replayable Turna patches; none yet
```

## Host commands (P0-002)

Once Rust `1.97.1` is installed:

```bash
cd native/turna_anki_core
cargo test -p turna_anki_bridge
cargo build -p turna_anki_bridge
```

P0-001 only implements `turna_anki_abi_version()`. Official `anki::Collection`
path dependencies are added in P0-002.

## Android commands

See `build-android/README.md`. Commands there are **candidates** until a
clean environment reproduces `libturna_anki.so`.

## Spike isolation

- Temporary collections live under `<app-support>/anki-spike/<run-id>/`.
- Dart code belongs in `lib/application/anki_official/spike/`.
- Do not write Turna `anki_notes`, Turna SRS, or a user profile Collection.
