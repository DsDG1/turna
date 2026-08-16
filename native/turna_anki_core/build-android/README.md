# Android arm64 build (Phase 0)

Status: **candidate / unverified**. Do not treat these commands as the
reproducible source of truth until P0-003 records a passing clean-environment
run in `docs/official-anki-migration/02-phase-0-result-report.md`.

## Intended product

```text
android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
```

## Candidate toolchain

| Item | Expected value on this machine | Verified |
|---|---|---|
| Rust target | `aarch64-linux-android` | no |
| ABI | `arm64-v8a` | no |
| NDK | `28.2.13676358` (Flutter 3.44.8 default) | path exists; unused |
| API level | must be compatible with `minSdkVersion = 24` | no |
| cargo-ndk | not installed | no |

## Candidate command

```bash
# CANDIDATE — paths relative to native/turna_anki_core/
# Verify, then freeze the single working command in build.sh.

rustup target add aarch64-linux-android
cargo ndk \
  -t arm64-v8a \
  -o ../../../android/app/src/main/jniLibs \
  --platform 24 \
  build \
  --manifest-path bridge/Cargo.toml \
  --release
```

`build.sh` currently wraps this candidate and exits non-zero with a clear
message until P0-003 verifies it.

## Symbol check (candidate)

`verify_symbols.sh` is a stub until a `.so` exists. Required checks:

- ELF architecture = AArch64
- filename / SONAME = `libturna_anki.so`
- visible: `turna_anki_abi_version`, `turna_anki_engine_new`,
  `turna_anki_call`, `turna_anki_buffer_free`
- no unexpected host glibc dependency
