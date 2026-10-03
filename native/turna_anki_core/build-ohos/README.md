# OpenHarmony cross-compilation probe

Answers one question: **can the Anki engine storage layer run on
OpenHarmony?** Nothing in this directory ships. It exists to retire a single
unknown before anyone commits weeks to it.

Run it:

```bash
export DEVECO_SDK_NATIVE="$DEVECO_SDK_HOME/default/openharmony/native"
bash build-ohos/build.sh
```

`build.sh` runs the host tests first, cross-compiles, and hands off to
`verify_symbols.sh`.

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
