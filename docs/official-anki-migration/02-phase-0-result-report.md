# Phase 0 结果报告

> 状态：**Conditional Go**（P0-000～P0-013 收口；P0-004 真机仍缺）  
> 分支：`spike/official-anki-core-android`  
> 决策日：2026-08-16  
> 决策提交：在本文件之后的 P0-013 commit

本文件只记录已测量事实。未验证的命令标为候选。

## 1. 执行摘要

Phase 0 Spike **证明了官方 `rslib` 可以在本机作为唯一 Anki 核心跑通**
open → import → render → queue → Good → undo → close/reopen，以及 5k/100k
host 导入。生产 `AnkiImporter` / Legacy 渲染 / Turna SRS **未被替换**。

| 问题 | 结论 |
|---|---|
| 官方 rslib 能否编成 Android arm64 `.so`？ | 能。`build.sh` 已验证。 |
| Flutter release APK 能否稳定加载？ | **未证明。** Gradle `flutter-plugin-loader` / `25.0.2`；无 adb。 |
| open / import / render / queue / answer / undo？ | Host 已证明。真机 FFI 未证明。 |
| Unicode / Reverse / Cloze / 媒体？ | 冻结 fixture + golden HTML 通过。 |
| 体积 / 大牌组？ | strip 后 `.so` 16 077 904 字节；100k import 3642 ms。产品尚未签字。 |
| AGPL 是否挡住发布？ | **GO WITH CONDITIONS**，不是自动通过。 |

**决策：Conditional Go。** 可以开始规划第二阶段（稳定 Engine 与官方导入），
但在 debug/release 真机加载 `.so`、About 许可证钩子和法律确认完成之前，
不得把生产导入切到官方 Collection，也不得删除 Legacy。

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

未修改官方数据库 schema。P0-010 起有 1 行可见性 patch：
`pub use progress::ProgressState`（见 §16）。

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

## 14. License 评审（P0-012）

工程结论：**GO WITH CONDITIONS**。不是法律意见。

已核实：

- `licenses/ANKI-LICENSE` 与 pin 上 `anki/LICENSE` 字节一致。
- `Cargo.lock` 358 个 crate：353 条对上 `anki/cargo/licenses.json`；
  其余 5 个已从 cargo cache 的 `Cargo.toml` 补齐（本 crate AGPL；
  `find-msvc-tools` / `symlink` / `toml_parser` MIT/Apache；`zmij` MIT）。
- 5 个 AGPL crate 都是 Anki workspace。`priority-queue` 双许可，Turna
  取 MPL-2.0。
- 未捆绑官方 Reviewer Web/Qt/MathJax/logo。
- 唯一修改：`0001-export-progress-state`。
- 源码与重建步骤见 `licenses/SOURCE-OFFER.md`。
- 未把 Turna GPLv3 写成已经完成 AGPL。
- Phase 0 无 AnkiWeb/sync，AGPL §13 未触发。

发布前仍阻塞：

1. 法律确认。
2. 生产 About / `showLicensePage` 调用 `registerOfficialAnkiLicenses()`
   （debug Spike 页已注册并展示）。
3. 每个发版 APK 写明对应 git commit。

## 15. 每日记录

### 2026-08-16

- 完成任务：P0-000～P0-013
- 当前任务：P0-013 阶段报告与 Go/No-Go
- 决策：Conditional Go（§19）
- 失败：官方 export 非 bit-stable；Gradle flutter-plugin-loader 25.0.2；无 adb
- 上游 API/patch 变化：1 行 `ProgressState` re-export
- 阻塞项：C1 Gradle/真机；C2 体积；C3/C4 许可展示与法律确认
- 下一步：修 `flutter-plugin-loader` / 真机加载，作为第二阶段第一张票

## 16. 上游 patch

| Patch | 文件 | 作用 | 删除条件 |
|---|---|---|---|
| `0001-export-progress-state` | `anki/rslib/src/lib.rs` | 对外 re-export `ProgressState`，取消导入时不必持有 Collection 锁 | 上游自己导出 abort handle |

子模块指针仍钉在 `967aa0d578fc75181e292e95326f9b58698da25c`。
`host-test.sh` / `build.sh` 在干净树上会 apply 该 patch。
这落在实施方案「很小且可维护的 visibility patch」Conditional Go 允许范围内。

## 17. 未解决风险

| ID | 风险 | 现状 | 对决策的影响 |
|---|---|---|---|
| R-APK | 本机无法 `flutter build apk` | `flutter-plugin-loader` 1.0.0 → `25.0.2` | 挡住无条件 Go |
| R-DEV | 无 adb 设备 | `adb devices` 为空 | 真机 load / 冷启动 / 低内存未测 |
| R-VOL | Native +16 MiB（strip 后） | 产品未确认预算 | Conditional：arm64-only / 拆分 |
| R-LIC | AGPL 源码提供与 About 钩子 | 工程清单完成；法律未签；生产 About 未钩 | 挡住含 `.so` 的商店包 |
| R-OHOS | 文档写的是 OHOS Flutter fork | 本机用官方 Flutter 3.44.8 | OHOS 打包另做 Spike |
| R-PIN | 上游无 semver | 已钉 commit | 升级必须独立 PR + 重跑 fixture |

没有发现「必须大规模 fork Anki」或「必须让 Dart 读官方 SQLite / RPC index」。

## 18. Go 条件对照（P0-013）

| 硬门禁 | 结果 | 证据 |
|---|---|---|
| Android arm64 debug/release 均能加载 `.so` | **未过** | §8、§13 Gradle/adb 失败 |
| 构建脚本在干净环境可复现 | 部分 | `build.sh` / `host-test.sh` 已在本机复跑；干净 CI 未跑 |
| Collection create/open/close/reopen | **过**（host） | §10 |
| Legacy/current package 可导入 | **过**（host） | §9、§12，含 `09-legacy-package` |
| Unicode 零字段损坏 | **过** | `01-basic-unicode` fields + golden |
| Basic / Reverse / Cloze / FrontSide | **过** | `render_goldens_match_official_html` |
| Queue / Good / Undo | **过**（host） | `queue_good_undo_reopen_and_stale_token` |
| 取消后 Collection 可继续用 | **过**（host） | cancel 测试 |
| 100k 可接受或有规模方案 | **过**（host） | 3642 ms / 100 000 notes；产品仍可再设门槛 |
| Native 体积得到产品确认 | **未过** | 16 077 904 字节已测，未签字 |
| Dart 不必读官方 SQLite/schema | **过** | spike 源码扫描 |
| Dart 不必暴露数字 RPC index | **过** | Turna C ABI + JSON |
| AGPL 至少 GO WITH CONDITIONS | **过** | §14 |

No-Go 条款（大规模 fork、核心模板不可控、取消损坏库、100k 不能跑、AGPL 不可接受）**均不成立**。
Release 无法加载是**尚未测到**，不是已经证明官方 Core 不能进 APK。

## 19. 决策

```text
CONDITIONAL GO
```

允许进入第二阶段（稳定 Engine 与官方导入）的设计与脚手架，条件如下。
每个条件有 owner、截止阶段和验收。未关闭前 **禁止** 切换生产导入默认路径、
**禁止** 删除 Legacy。

| # | 条件 | Owner | 截止 | 验收 |
|---|---|---|---|---|
| C1 | 修 Gradle，打出 arm64 debug **和** release APK，真机 `DynamicLibrary.open('libturna_anki.so')` | 构建 / 平台 | 第二阶段开工后、生产切流前 | 两份 APK + adb 日志，符号与 ABI 检查通过 |
| C2 | 产品书面接受 strip 后约 16 MiB native，或改 arm64-only / 按需下载 | 产品 | 第二阶段开工 | 预算写进 ADR 0036 或产品纪要 |
| C3 | 生产 About / `showLicensePage` 调用 `registerOfficialAnkiLicenses()`；发版记录 git commit | 应用 | 第一个含 `.so` 的对外包 | License 页可见 Anki AGPL |
| C4 | 法律确认 P0-012 清单 | 许可负责人 | 同上 | 书面 GO / GO WITH CONDITIONS |
| C5 | 继续携带 `0001-export-progress-state`，直到上游导出 abort API | Native | 第二阶段全程 | patch 可 replay；升级 pin 时重打 |

允许留到正式 Renderer（第三阶段）的前端工作：隔离 WebView Reviewer、
MathJax、typed-answer 外壳。Phase 0 只保证官方 HTML/CSS/AV 字符串。

## 20. 第二阶段工期调整

总体方案原估计（一名熟 Flutter+Rust 的工程师，Android-only）：

| 阶段 | 原估计 | Phase 0 之后 |
|---|---|---|
| 0 Spike | 1–2 周 | **已完成** |
| 1 稳定 Engine 与官方导入 | 2–3 周 | **2–3 周**，另加 **3–5 日** 专攻 C1（Gradle/APK/真机）。导入/渲染 API 已不必再探路 |
| 2 官方原卡渲染 | 3–4 周 | **维持 3–4 周**（WebView 安全壳未做） |
| 3 课程投影 | 2–3 周 | 维持 |
| 4 官方 Scheduler | 2–3 周 | **可压到 1.5–2.5 周**：Good/Undo/revlog 已在 host 闭环，剩下 session 持久化与 UI |
| 5 Legacy 迁移删除 | 2–4 周 | 维持；取决于是否已有正式用户数据（产品仍未回答） |
| 6 AnkiWeb Sync | 不计入首期 | 维持；会重开 AGPL §13 |

核心迁移总量仍按 **12–18 周**，但第一刀必须先关掉 C1，否则第二阶段会在「能不能装进 APK」上原地打转。

建议第二阶段第一张票就是 C1，而不是立刻改 `anki_import_screen.dart`。

## 16. 上游 patch

| Patch | 文件 | 作用 | 删除条件 |
|---|---|---|---|
| `0001-export-progress-state` | `anki/rslib/src/lib.rs` | 对外 re-export `ProgressState`，取消导入时不必持有 Collection 锁 | 上游自己导出 abort handle |

子模块指针仍钉在 `967aa0d578fc75181e292e95326f9b58698da25c`。
`host-test.sh` / `build.sh` 在干净树上会 apply 该 patch。
这落在实施方案「很小且可维护的 visibility patch」Conditional Go 允许范围内。

## 17. 未解决风险

| ID | 风险 | 现状 | 对决策的影响 |
|---|---|---|---|
| R-APK | 本机无法 `flutter build apk` | `flutter-plugin-loader` 1.0.0 → `25.0.2` | 挡住无条件 Go |
| R-DEV | 无 adb 设备 | `adb devices` 为空 | 真机 load / 冷启动 / 低内存未测 |
| R-VOL | Native +16 MiB（strip 后） | 产品未确认预算 | Conditional：arm64-only / 拆分 |
| R-LIC | AGPL 源码提供与 About 钩子 | 工程清单完成；法律未签；生产 About 未钩 | 挡住含 `.so` 的商店包 |
| R-OHOS | 文档写的是 OHOS Flutter fork | 本机用官方 Flutter 3.44.8 | OHOS 打包另做 Spike |
| R-PIN | 上游无 semver | 已钉 commit | 升级必须独立 PR + 重跑 fixture |

没有发现「必须大规模 fork Anki」或「必须让 Dart 读官方 SQLite / RPC index」。

## 18. Go 条件对照（P0-013）

| 硬门禁 | 结果 | 证据 |
|---|---|---|
| Android arm64 debug/release 均能加载 `.so` | **未过** | §8、§13 Gradle/adb 失败 |
| 构建脚本在干净环境可复现 | 部分 | `build.sh` / `host-test.sh` 已在本机复跑；干净 CI 未跑 |
| Collection create/open/close/reopen | **过**（host） | §10 |
| Legacy/current package 可导入 | **过**（host） | §9、§12，含 `09-legacy-package` |
| Unicode 零字段损坏 | **过** | `01-basic-unicode` fields + golden |
| Basic / Reverse / Cloze / FrontSide | **过** | `render_goldens_match_official_html` |
| Queue / Good / Undo | **过**（host） | `queue_good_undo_reopen_and_stale_token` |
| 取消后 Collection 可继续用 | **过**（host） | `cancel_import_does_not_report_success_and_collection_checks` |
| 100k 可接受或有规模方案 | **过**（host） | 3642 ms / 100 000 notes；产品仍可再设门槛 |
| Native 体积得到产品确认 | **未过** | 16 077 904 字节已测，未签字 |
| Dart 不必读官方 SQLite/schema | **过** | spike 源码扫描 |
| Dart 不必暴露数字 RPC index | **过** | Turna C ABI + JSON |
| AGPL 至少 GO WITH CONDITIONS | **过** | §14 |

No-Go 条款（大规模 fork、核心模板不可控、取消损坏库、100k 不能跑、AGPL 不可接受）**均不成立**。
Release 无法加载是**尚未测到**，不是已经证明官方 Core 不能进 APK。

## 19. 决策

```text
CONDITIONAL GO
```

允许进入第二阶段（稳定 Engine 与官方导入）的设计与脚手架，条件如下。
每个条件有 owner、截止阶段和验收。未关闭前 **禁止** 切换生产导入默认路径、
**禁止** 删除 Legacy。

| # | 条件 | Owner | 截止 | 验收 |
|---|---|---|---|---|
| C1 | 修 Gradle，打出 arm64 debug **和** release APK，真机 `DynamicLibrary.open('libturna_anki.so')` | 构建 / 平台 | 第二阶段开工后、生产切流前 | 两份 APK + adb 日志，符号与 ABI 检查通过 |
| C2 | 产品书面接受 strip 后约 16 MiB native，或改 arm64-only / 按需下载 | 产品 | 第二阶段开工 | 预算写进 ADR 0036 或产品纪要 |
| C3 | 生产 About / `showLicensePage` 调用 `registerOfficialAnkiLicenses()`；发版记录 git commit | 应用 | 第一个含 `.so` 的对外包 | License 页可见 Anki AGPL |
| C4 | 法律确认 P0-012 清单 | 许可负责人 | 同上 | 书面 GO / GO WITH CONDITIONS |
| C5 | 继续携带 `0001-export-progress-state`，直到上游导出 abort API | Native | 第二阶段全程 | patch 可 replay；升级 pin 时重打 |

允许留到正式 Renderer（第三阶段）的前端工作：隔离 WebView Reviewer、
MathJax、typed-answer 外壳。Phase 0 只保证官方 HTML/CSS/AV 字符串。

## 20. 第二阶段工期调整

总体方案原估计（一名熟 Flutter+Rust 的工程师，Android-only）：

| 阶段 | 原估计 | Phase 0 之后 |
|---|---|---|
| 0 Spike | 1–2 周 | **已完成**（本机约 1 个日历日集中落地 + 既有脏树未清） |
| 1 稳定 Engine 与官方导入 | 2–3 周 | **2–3 周**，另加 **3–5 日** 专攻 C1（Gradle/APK/真机）。导入/渲染 API 已不必再探路 |
| 2 官方原卡渲染 | 3–4 周 | **维持 3–4 周**（WebView 安全壳未做） |
| 3 课程投影 | 2–3 周 | 维持 |
| 4 官方 Scheduler | 2–3 周 | **可压到 1.5–2.5 周**：Good/Undo/revlog 已在 host 闭环，剩下 session 持久化与 UI |
| 5 Legacy 迁移删除 | 2–4 周 | 维持；取决于是否已有正式用户数据（产品仍未回答） |
| 6 AnkiWeb Sync | 不计入首期 | 维持；会重开 AGPL §13 |

核心迁移总量仍按 **12–18 周**，但第一刀必须先关掉 C1，否则第二阶段会在「能不能装进 APK」上原地打转。

建议第二阶段第一张票就是 C1，而不是立刻改 `anki_import_screen.dart`。

## 21. 每日记录（P0-013）

### 2026-08-16

- 完成任务：P0-000～P0-013
- 决策：Conditional Go
- 阻塞项：C1 Gradle/真机；C2 体积；C3/C4 许可展示与法律确认
- 下一步：修 `flutter-plugin-loader` / 真机加载，或按第二阶段方案开工但把 C1 当第一张票
