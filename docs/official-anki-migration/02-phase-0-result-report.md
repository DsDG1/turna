# Phase 0 结果报告

> 状态：进行中（P0-000～P0-011 已落地；P0-004 真机仍缺；P0-012/013 未做）  
> 分支：`spike/official-anki-core-android`  
> 起始日期：2026-08-16

本文件只记录已测量事实。未验证的命令标为候选。

## 1. 执行摘要

Phase 0 已开工。本机已建立 `native/turna_anki_core`，并把官方 Anki 钉在
`967aa0d578fc75181e292e95326f9b58698da25c`。尚未安装 Rust，尚未交叉编译，
尚未改动生产 Anki 导入入口。

## 2. 基线环境

```text
Turna commit:           bdd40f8 (spike start) on 8fb07d9eda3c5ed3c32eb6a6493ef6a1bffa5f24
Turna branch at start:  master → spike/official-anki-core-android
Working tree:           dirty（约 300 条既有未提交改动，本阶段未纳入）
Anki commit:            967aa0d578fc75181e292e95326f9b58698da25c
Anki describe:          25.09.2-370-g967aa0d57
Flutter version:        3.44.8 stable (official, not OHOS fork)
Flutter revision:       058e0af2c2 (2026-07-23)
Dart version:           3.12.2 (Flutter bundled); /usr/bin/dart also 3.12.2
JDK version:            OpenJDK 17.0.19 (JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64)
Gradle:                 8.14 (gradle-wrapper.properties)
AGP:                    8.11.1
Kotlin:                 2.2.20
Android compileSdk:     36
Android minSdkVersion:  24   (resolved from Flutter 3.44.8 FlutterExtension; not the expression flutter.minSdkVersion)
Android targetSdk:      flutter.targetSdkVersion (Flutter 3.44 default)
Android NDK (declared): 28.2.13676358 via ndkVersion flutter.ndkVersion
Android NDK (installed): 26.3.11579264, 27.0.12077973, 28.2.13676358
ANDROID_NDK_HOME:       unset
ANDROID_HOME:           /home/whwen/Android/Sdk
Rust toolchain:         rustc 1.97.1 (8bab26f4f 2026-07-14), cargo 1.97.1
cargo-ndk version:      not installed
protoc:                 31.1 (Anki-pinned zip, sha256 96553041…044d8065)
Host:                   Linux x86_64, Ubuntu 24.04 kernel 7.0.0-28-generic
App versionName:        1.3.0
```

与 `docs/android-build-setup.md` 的差异必须记下：该文档描述的是
Windows 上的 OpenHarmony Flutter `3.35.8-ohos`。本机 `local.properties`
指向官方 Flutter `/home/whwen/documents/reso/flutter`。Phase 0 的构建
证据以本机实际工具链为准，不能假设 OHOS fork 行为已经复现。

## 3. 无 Native Core 的 APK 基线

本机已有先前产物，**不是本轮重新构建**：

| Artifact | Bytes | Size | Timestamp | Notes |
|---|---:|---|---|---|
| `build/app/outputs/apk/release/app-release.apk` | 84247675 | 81 MiB | 2026-08-14 18:58 | fat APK, 3 ABIs |
| `build/app/outputs/apk/debug/app-debug.apk` | 138163491 | 132 MiB | 2026-08-15 23:40 | fat APK, 3 ABIs |

Release APK native 目录（无 `libturna_anki.so`）：

```text
lib/arm64-v8a/libapp.so
lib/arm64-v8a/libdartjni.so
lib/arm64-v8a/libdatastore_shared_counter.so
lib/arm64-v8a/libflutter.so
lib/arm64-v8a/libsqlite3.so
lib/arm64-v8a/libzstandard_android.so
(+ armeabi-v7a and x86_64 copies)
```

```text
baseline APK size:          84247675 bytes (stale fat release, 2026-08-14)
baseline install size:      not measured
baseline cold start:        not measured
baseline arm64-only APK:    not built this run
```

P0-000 尚未完成“可重复的无 Native release 构建”。需要一次
`flutter build apk --release --split-per-abi --target-platform android-arm64`
作为可比较基线。本轮先不阻塞 P0-001 目录与上游钉死。

## 4. 实际上游 commit

Submodule path: `native/turna_anki_core/anki`

```text
967aa0d578fc75181e292e95326f9b58698da25c
25.09.2-370-g967aa0d57
origin = https://github.com/ankitects/anki.git
shallow clone: yes (copied from the existing local checkout)
```

Cargo path 只允许仓库相对路径。未把 `/home/whwen/documents/reso/Varnamalaplus/anki`
写进任何 `Cargo.toml`。

## 5. 已验证命令

```bash
git checkout -b spike/official-anki-core-android
git clone <local-anki> native/turna_anki_core/anki
git -C native/turna_anki_core/anki remote set-url origin https://github.com/ankitects/anki.git
git -C native/turna_anki_core/anki checkout --detach 967aa0d578fc75181e292e95326f9b58698da25c
```

`--reference` 因本地 Anki 是浅克隆而失败，改用直接本地 clone。

## 6. Host Rust 结论（P0-002）

已验证（2026-08-16）：

```bash
git -C native/turna_anki_core/anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
# protoc 31.1 at native/turna_anki_core/tools/protoc/bin/protoc
PROTOC=... PROTOC_BINARY=... cargo test
```

```text
test tests::abi_version_is_one ... ok
test tests::collection_builder_is_visible_and_closes ... ok
```

外部 bridge 可以直接调用：

- `CollectionBuilder::new` / `default` / `set_media_paths` / `set_shared_progress_state` / `build`
- `Collection::close`
- `Collection::import_apkg`
- `Collection::render_existing_card`

未修改官方数据库 schema，无 Anki 源码 patch。

构建方式结论：

- 不能把 `turna_anki_core` 做成包含 `anki/rslib` 的 Cargo workspace（`rslib` 已声明 `workspace = ".."`）。
- 单独编 `rslib` 时必须在本 crate 打开 tokio `io-util`，否则 Anki workspace 里由其他 member 合并进来的 feature 会缺失。
- 需要 Anki 的 `ftl/core-repo` 与 `ftl/qt-repo` 子模块。
- 需要 Anki 钉死的 `protoc` 31.1。

## 7. Android arm64 交叉编译结论（P0-003）

已验证（2026-08-16）：

```bash
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
ANDROID_HOME=/home/whwen/Android/Sdk ./native/turna_anki_core/build-android/build.sh
```

```text
cargo-ndk:              4.1.2
NDK:                    28.2.13676358
platform / API level:   24
target:                 aarch64-linux-android
ABI:                    arm64-v8a
libturna_anki.so:       16294656 bytes (unstripped)
llvm-strip copy:        13816680 bytes
NEEDED:                 libdl.so, libm.so, libc.so
host glibc:             none
symbols:                abi_version, engine_new, call, buffer_free
sqlite3_open:           present in .so
```

第一次交叉编译只调用 `CollectionBuilder::default()` 时，产物仅 467 KiB，官方
Collection 被 DCE。`engine_new` 现在会 `build()` 一次内存 Collection，release
`.so` 约 15.5 MiB，含 bundled sqlite。

`verify_symbols.sh` 必须使用 NDK `llvm-nm`。本机自带的 `llvm-readelf` 会漏报
Android dynsym，造成假阴性。

## 8. Dart FFI 加载结论（P0-004）

已落地：

- `ffi: ^2.2.0` 升为 `pubspec.yaml` 直接依赖（lock 仍为 2.2.0）。
- `lib/application/anki_official/spike/`：手写 C ABI、engine、fake engine、诊断页。
- 设置 → 系统实验室在 `kDebugMode` 下显示入口；未加入 AutoRoute。
- `DynamicLibrary` 按 isolate 缓存，页面销毁不 `close()`。
- 非 Android 返回 `unsupportedPlatform`；缺库返回 `libraryMissing`。
- `flutter test test/application/anki_official/official_anki_spike_test.dart`：9 passed。
- `flutter analyze lib/application/anki_official`：No issues.

未在本机完成：

```text
flutter build apk --release --split-per-abi --target-platform android-arm64
```

失败点在既有 Gradle/Flutter 插件解析，与本刀 Dart 无关：

```text
Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
> 25.0.2
```

本机无 `adb` 设备。debug/release 真机 `DynamicLibrary.open` 仍待验证。
`android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so` 仍在标准 jniLibs 路径（16 294 656 字节）。

## 9. Fixture 结论（P0-005）

9 个小包由 pinned official `rslib` 导出，已提交：

```text
test/fixtures/anki_official/packages/01-basic-unicode.apkg … 09-legacy-package.apkg
test/fixtures/anki_official/expected/*.json
test/fixtures/anki_official/manifest.json
```

生成命令：

```text
./tool/official_anki_spike/generate_fixtures.sh
./tool/official_anki_spike/generate_fixtures.sh --large 5000
```

本机已跑通 5k（`generated/10-large-generated-5000.apkg`，274 KiB，gitignored）。
100k 用 `--large 100000`。`--large` 不再改写冻结的小包。

校验：

```text
dart run tool/official_anki_spike/verify_fixture_results.dart   # ok 9 packages
flutter test test/application/anki_official/official_anki_fixture_manifest_test.dart
```

官方导出每次会换 card ID，因此 SHA-256 只对冻结提交物有效。有意重生后必须连 `expected/` 和 `manifest.json` 一起更新。

## 10. Collection 生命周期结论（P0-006）

已落地（2026-08-16）：

- Rust `bridge/src/engine.rs`：`HashMap<u64, Engine>` handle registry，
  状态机 `Created → Open → Closed`，路径必须绝对且互不相同，父目录自动创建。
- 同 handle 再次 open → `COLLECTION_ALREADY_OPEN` (17)。
- 同路径第二 handle → `COLLECTION_LOCKED` (18)。
- 无效 handle / 相对路径 / 未 open 时 close → `INVALID_HANDLE` (11) /
  `INVALID_ARGUMENT` (12) / `INVALID_STATE` (16)。
- Dart 路径 DTO 只构造 `<support>/anki-spike/<run-id>/`；错误信息不回显完整目录。
- Spike 页在 ABI 探测之外增加「探测 Collection」：open → check → close → reopen → close。
- 诊断页仍只从 `kDebugMode` 设置入口进入，未加入 AutoRoute。

Host 已验证：

```text
cd native/turna_anki_core
PROTOC=... PROTOC_BINARY=... cargo test
# engine::tests::open_close_reopen_creates_files
# engine::tests::double_open_is_already_open
# engine::tests::second_handle_same_path_is_locked
# engine::tests::invalid_handle_and_relative_paths
# engine::tests::one_hundred_open_close_cycles
# abi::tests::engine_new_close_and_free_round_trip
# abi::tests::invalid_handle_is_rejected
```

```text
flutter test test/application/anki_official/official_anki_spike_test.dart
# 14 passed
flutter analyze lib/application/anki_official test/application/anki_official
# No issues found
```

未在本机完成：真机 / APK 上的 FFI `open_collection`（仍受 P0-004 Gradle
插件解析和缺 adb 阻塞）。Android `.so` 需在有交叉编译环境时重编，才能带上
本刀新增的 registry 实现。

## 11. 生产路径

本 spike 提交未改生产 Anki 入口，也未加入 Legacy fallback：

- `lib/views/anki/anki_import_screen.dart`（工作区里另有既有脏改，未纳入本提交）
- `lib/application/anki/anki_importer.dart`（同上）
- 任何 Legacy 渲染 / SRS 文件

Dart spike 源码测试禁止 `package:sqlite3` / `package:archive` / `ZipDecoder` /
`anki_proto` / `package:protobuf`。

## 12. 导入 / 渲染 / 调度 / 取消（P0-007～P0-010）

Host `cargo test --lib`：19 passed（含下列场景，不是 skip）：

- `import_all_small_fixtures_matches_manifest_and_unicode`
- `render_goldens_match_official_html`（Basic / Reverse 两 ord / Cloze c1+c2 /
  FrontSide+CSS / media AV）
- `queue_good_undo_reopen_and_stale_token`
- `cancel_import_does_not_report_success_and_collection_checks`
- `invalid_and_missing_packages_are_structured`
- `empty_undo_and_missing_card_are_structured`
- `import_100k_or_record_nogo`

批量 card ID 在一次 `OP_SEARCH_CARDS` 内返回，Dart 不对每张卡做 FFI。

取消：第二线程写共享 `ProgressState.want_abort`；官方
`ThrottlingProgressHandler` 在非节流更新时返回 `Interrupted`。导入成功不会被
改写成取消。

极小上游 re-export：`pub use progress::ProgressState;`
（`patches/0001-export-progress-state.patch`）。`CollectionBuilder` 本就可接收
共享 progress，但类型在 private module 里，外部 crate 无法构造。

## 13. 性能与体积（P0-011）

Host debug `cargo test`，2026-08-16，同一进程测得的原始值（不是只报平均）：

| 场景 | 原始值 |
|---|---|
| 5k import | 297 ms；notes=5000 cards=5000 |
| first render | 350 µs |
| warm render ×100 | p50=66 µs，p95=96 µs，p99=121 µs |
| queue build | 2562 µs |
| answer Good | 11307 µs |
| undo | 12096 µs |
| 100k generate | 18.95 s wall，max RSS 1 056 248 KiB |
| 100k import | 3642 ms；notes=100000 cards=100000；cargo test 过程 max RSS 1 065 504 KiB |

`.so`（本轮重编，含 import/render/scheduler）：

| 产物 | bytes |
|---|---:|
| arm64-v8a unstripped | 19 245 480 |
| arm64-v8a llvm-strip | 16 077 904 |
| NEEDED | libdl.so, libm.so, libc.so |

上一轮 P0-003 unstripped 16 294 656；本轮功能变多后 unstripped +2 950 824。

APK / 真机（未发明数字）：

```text
flutter build apk --release --split-per-abi --target-platform android-arm64
Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
> 25.0.2
adb devices → no devices attached
```

因此没有 with-core APK 体积对，也没有设备矩阵。这是环境失败，不是 host 指标失败。
100k 在 host 上完成，不是 No-Go。

## 14. 每日记录

### 2026-08-16

- 完成任务：P0-000～P0-011（P0-004 真机 APK 仍缺；P0-012/013 未做）
- 当前任务：P0-011 测量已写入本报告
- 实际命令：见 §5–§13
- 新增事实：9 个小 fixture 官方 import+golden render 通过；Good/undo/reopen/stale
  token 通过；5k/100k host import 完成；`.so` unstripped 19 245 480
- 失败：官方 export 非 bit-stable；Gradle flutter-plugin-loader 25.0.2；无 adb
- 指标变化：见 §13
- 上游 API/patch 变化：1 行 `ProgressState` re-export
- 阻塞项：release APK / 真机 DynamicLibrary.open
- 下一步：P0-012 License 评审，或先修 P0-004 Gradle/adb
