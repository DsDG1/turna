# OpenHarmony cross-compilation probe

Answers one question: **can the Anki engine storage layer run on
OpenHarmony?** Nothing in this directory ships. It exists to retire a single
unknown before anyone commits weeks to it.

Run it:

```bash
export DEVECO_SDK_NATIVE="$DEVECO_SDK_HOME/default/openharmony/native"
bash build-ohos/build.sh            # the probe
bash build-ohos/build-bridge.sh     # the real engine
```

`build.sh` runs the host tests first, cross-compiles, and hands off to
`verify_symbols.sh`. `build-bridge.sh` does the same for the real bridge via
`verify_bridge_symbols.sh`, and asserts rather than applies the rslib patches
(re-applying to an already-patched tree fails).

Both source `ohos-env.sh` for the toolchain flags. That file is not
duplicated on purpose: the failure modes are non-obvious enough that a second
copy would drift.

## What the real bridge adds over the probe

The probe used a minimal crate to isolate variables, which left rslib's own
dependency tree unproven. `build-bridge.sh` answers that, and it turned out
to need nothing: no feature disabled, no C dependency that would not build,
no patch conflict, 2m39s from clean.

| | probe | real bridge |
|---|---|---|
| `.so` size | 2,939,328 B | 23,123,056 B |
| `NEEDED` | `libc.so` | `libc.so`, `libtime_service_ndk.so` |
| symbols | 7 probe fns | 7 bridge fns |

`libtime_service_ndk.so` comes from `iana-time-zone`'s `src/tz_ohos.rs`,
which has first-class OHOS support and resolves the local timezone through
`OH_TimeService_GetTimeZone`. It is a real system library present in the
sysroot, so it is benign — but `verify_bridge_symbols.sh` asserts that
*every* `NEEDED` entry resolves against the sysroot, so a future dependency
that cannot be satisfied on-device fails the build instead of the device.

`protoc` needs no OHOS-specific handling: it is a host tool, so the same
Windows binary that builds the Android artifact builds this one.

## On-device results

HUAWEI Mate 90 Pro Max, aarch64, API 26, HarmonyOS 7.0.0.109.

Engine bridge lifecycle, via `dlopen` inside a hap process:

```
dlopen("libturna_anki.so")   OK
turna_anki_abi_version()     1
turna_anki_engine_new        status 0, buffer len 8 (u64 handle)
turna_anki_engine_close      status 0
dlclose                      OK
```

`engine_new` is a real test rather than a formality: it calls
`touch_rslib()`, which builds and closes an in-memory `Collection`. A status
of 0 therefore means rslib and the bundled SQLite actually initialised on the
device.

What is still unproven: opening a collection on disk, the review scheduler
under real load, the import path, and card rendering.

## What the probe covers, and what it does not

Seven symbols, one per assumption that could independently be false:

| symbol | assumption |
|---|---|
| `turna_anki_abi_version` | the C ABI is exported and lookup-able at all |
| `turna_anki_probe_sqlite_roundtrip` | bundled SQLite compiles and really reads/writes |
| `turna_anki_probe_unicase_collation` | the pinned `unicase` collation plus a VACUUM b-tree rebuild work |
| `turna_anki_probe_set_fs_path` | the string ABI works |
| `turna_anki_probe_tokio_runtime` | a multi-thread tokio runtime can be built |
| `turna_anki_probe_tokio_fs` | `tokio::fs` works against the target libc |
| `turna_anki_probe_tokio_signal` | OS signal registration works |

A pass covers the **engine storage substrate only**. It says nothing about
card rendering, the scheduler's behaviour under real review workloads, or
AnkiDroid-compatible media serving. See the ADR for the scope boundary.

## Four build failures worth not rediscovering

Every flag in `build.sh` answers a real error. Removing any of them
reintroduces the failure it was added for.

### 1. rustc does not forward `--target` to the linker

With only `linker = <ohos clang>` and `-Clink-arg=-fuse-ld=lld`, the link
fails with:

```
lld: error: unknown argument: --version-script=...
lld: error: unknown argument: --eh-frame-hdr
lld: error: unknown argument: -z
```

Those are all valid GNU/lld arguments. The cause is that rustc never tells
the linker driver which target it is building for, so clang falls back to the
**host** triple (`x86_64-w64-windows-gnu`) and `-fuse-ld=lld` then selects the
COFF `lld-link` instead of `ld.lld`. Fix:
`-Clink-arg=--target=aarch64-unknown-linux-ohos`. One flag, whole ballgame.

### 2. `RUSTFLAGS` splits on spaces

```
error: multiple input filenames provided (first two filenames are `-` and `Studio\sdk\...`)
```

`RUSTFLAGS` is whitespace-split with no quoting, so any SDK path containing a
space destroys it. Use `CARGO_ENCODED_RUSTFLAGS`, which separates with `\x1f`:

```bash
us=$'\x1f'
export CARGO_ENCODED_RUSTFLAGS="-Clink-arg=--target=${triple}${us}-Clink-arg=--sysroot=${sysroot}"
```

Join with `$us` — never prefix it. A leading separator yields an empty first
element, which rustc reads as a second input filename.

### 3. `cc-rs` splits `CFLAGS` too, and `CC_SHELL_ESCAPED_FLAGS` makes it worse

`CC_SHELL_ESCAPED_FLAGS=1` is the documented escape hatch, but it strips
backslashes, turning `D:\DevEco Studio\...` into `D:DevEco` and then splitting
there anyway. The only reliable fix is to make the path itself space-free.
`build.sh` resolves an 8.3 short name via `cygpath -w -s`; if the volume has
8.3 disabled, it tells you to create a junction instead.

This matters in practice: DevEco Studio's default install path is
`C:\Program Files\Huawei\DevEco Studio\sdk\...`.

### 4. No GNU `ar` on a Windows host

`cc-rs` aborts with `failed to find tool "ar"`. Point it at
`llvm-ar` / `llvm-ranlib` from the OHOS toolchain.

## Running it on a device

A retail HarmonyOS device will not `dlopen` an arbitrary `.so` from a shell.
The `.so` has to ship inside a signed hap. The harness used:

- a minimal ArkTS app whose NAPI module `dlopen`s the probe and calls all
  seven symbols
- the probe built as a **prebuilt** library in `entry/libs/arm64-v8a/`, so
  `dlopen` by bare name works off the hap's lib path
- every step writing a marker file into the app's `filesDir`, read back over
  `hdc`

Three harness details that each cost a full deploy cycle to learn:

- **The probe must not run on the ArkUI thread.** It builds a tokio runtime,
  enumerates a directory and runs a SQLite `VACUUM`. Inline from
  `aboutToAppear` the process was `SIGKILL`ed with `APP_INPUT_BLOCK` before
  printing anything. Use `napi_create_async_work`.
- **Pass `filesDir` into the native side.** A relative `fopen` from a native
  library does not land in the sandbox, so the first attempt wrote nothing and
  an empty directory could not be told apart from "never ran".
- **`hilog` is not a reliable channel.** It can be filtered by level and
  domain policy, which makes a negative result indistinguishable from a
  missing one. Files are the channel of record.
