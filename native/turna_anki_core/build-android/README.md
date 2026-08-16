# Android arm64 build (Phase 0)

Status: **verified on 2026-08-16** (P0-003). Frozen command is `build.sh`.

## Product

```text
android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
```

This file is gitignored. CI and developers produce it with `build.sh`.

## Verified toolchain

| Item | Value |
|---|---|
| Rust target | `aarch64-linux-android` |
| ABI | `arm64-v8a` |
| NDK | `28.2.13676358` |
| API level / platform | `24` (`minSdkVersion`) |
| cargo-ndk | `4.1.2` |
| rustc | `1.97.1` |
| protoc | `31.1` |

## Command

```bash
# from repo root, after rustup target add aarch64-linux-android
# and: cargo install cargo-ndk --version 4.1.2 --locked
export ANDROID_HOME=/path/to/Android/Sdk   # or ANDROID_NDK_HOME=.../28.2.13676358
./native/turna_anki_core/build-android/build.sh
```

`build.sh` sets `ANDROID_NDK_HOME` from `ANDROID_HOME/ndk/28.2.13676358` when unset, then runs:

```bash
cargo ndk -t arm64-v8a --platform 24 -o <app>/android/app/src/main/jniLibs build --release
```

and immediately runs `verify_symbols.sh`.

## First-run measurements (this machine)

| Artifact | Bytes |
|---|---:|
| unstripped `libturna_anki.so` | 16294656 |
| llvm-strip copy | 13816680 |

Dynamic deps: `libdl.so`, `libm.so`, `libc.so` (Bionic). No `libc.so.6`.

## Symbol check

`verify_symbols.sh` uses NDK `llvm-nm`/`llvm-readelf` (not a host llvm-readelf) and requires:

- ELF AArch64
- filename `libturna_anki.so`
- exported: `turna_anki_abi_version`, `turna_anki_engine_new`, `turna_anki_call`, `turna_anki_buffer_free`
- no host glibc
- size ≥ 2 MiB so rslib was not DCE'd out
