# Corresponding source offer (official Anki core)

This is the Phase 0 recipe for anyone who receives a Turna build that
contains `libturna_anki.so`. It is not a store listing and not legal
advice.

## What you are entitled to

1. The Turna tree at the commit printed in the app’s About / version
   string (`git rev-parse HEAD` at build time).
2. The pinned Anki tree
   `967aa0d578fc75181e292e95326f9b58698da25c`.
3. `native/turna_anki_core/patches/0001-export-progress-state.patch`.
4. `native/turna_anki_core/Cargo.lock`.

## Get the source

```bash
git clone <the Turna remote used for that release>
cd Varnamalaplus   # or the published layout
git checkout <the commit recorded in About>
git submodule update --init native/turna_anki_core/anki
git -C native/turna_anki_core/anki checkout --detach \
  967aa0d578fc75181e292e95326f9b58698da25c
# host-test.sh / build.sh apply the ProgressState patch if needed
```

This workstation’s `origin` is `git@gitee.com:dhwdwf3/Varnamalaplus.git`.
A public clone URL must be written here again at the first store
release if it differs.

## Rebuild `libturna_anki.so` (Android arm64)

```bash
rustup toolchain install 1.97.1
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
# protoc 31.1 — see native/turna_anki_core/README.md
export ANDROID_HOME=/path/to/Android/Sdk
./native/turna_anki_core/build-android/build.sh
```

Host check:

```bash
./native/turna_anki_core/build-android/host-test.sh
```

## Network use (AGPL §13)

Phase 0 does not offer a network service that lets someone else interact
with the official Collection. If a later release adds AnkiWeb, sync, or
any remote Collection API, this offer must also be reachable from that
network interface.
