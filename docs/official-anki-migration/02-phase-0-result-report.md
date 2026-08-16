# Phase 0 结果报告

> 状态：进行中（P0-000 / P0-001）  
> 分支：`spike/official-anki-core-android`  
> 起始日期：2026-08-16

本文件只记录已测量事实。未验证的命令标为候选。

## 1. 执行摘要

Phase 0 已开工。本机已建立 `native/turna_anki_core`，并把官方 Anki 钉在
`967aa0d578fc75181e292e95326f9b58698da25c`。尚未安装 Rust，尚未交叉编译，
尚未改动生产 Anki 导入入口。

## 2. 基线环境

```text
Turna commit:           8fb07d9eda3c5ed3c32eb6a6493ef6a1bffa5f24
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
Rust toolchain:         not installed
cargo-ndk version:      not installed
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

## 6. 尚未执行

- Host `cargo test -p turna_anki_bridge`（Rust 未安装）
- `CollectionBuilder` / `import_apkg` / `render_existing_card` 外部 crate 可见性
- Android `cargo-ndk` 交叉编译
- Dart FFI
- Fixture golden
- 本轮无 Native arm64 release 重构建

## 7. 生产路径

未修改：

- `lib/views/anki/anki_import_screen.dart`
- `lib/application/anki/anki_importer.dart`
- 任何 Legacy 渲染 / SRS 文件

## 8. 每日记录

### 2026-08-16

- 完成任务：P0-000 环境盘点（部分）、P0-001 目录与上游钉死
- 当前任务：P0-002 Host Rust 最小编译
- 实际命令：见 §5
- 新增事实：本机是官方 Flutter 3.44.8；minSdk=24；NDK 28.2 已安装；Rust/cargo-ndk 缺失
- 失败：`git clone --reference` 因浅克隆被拒绝
- 指标变化：无 Native 新产物
- 上游 API/patch 变化：无
- 阻塞项：需要安装 Rust 1.97.1 才能做 P0-002
- 下一步：安装 pinned Rust，编译 `turna_anki_abi_version`，再接入 `anki` path 依赖
