# Phase 0 + Phase 1 技术修补结果

```text
TECHNICAL CONDITIONAL GO
License/legal: NOT EVALUATED BY THIS PLAN
Production release: subject to separate License gate
```

> 日期：2026-08-17  
> 基线 HEAD：`63663c0358557235f3df044ada7086da16169b66`  
> 上游 Anki：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 生产切流：**禁止**。`OfficialAnkiFeatureFlags.fromEnvironment()` 全部默认 `false`。

本文件只记录本轮已测量事实。Fake / Host / Android 分栏。未测项不写通过。

## 1. 决策

代码正确性、真实 Host FFI、一致性 backup、Saga cursor/journal 已闭合。
以下外部条件仍开着，因此结论是 **TECHNICAL CONDITIONAL GO**，不是 TECHNICAL GO：

| 条件 | Owner | 期限 | 禁止项 |
|---|---|---|---|
| C1 新 debug/release APK + 完整真机闭环 | 构建 / 平台 | 打开 release import 之前 | PLG110 debug 已过 Spike + 官方 import 181 张；仍缺 release APK 与第二台设备 |
| C2 native 体积产品确认 | 产品 | 含 `.so` 的外部包之前 | 不得发含 `.so` 的商店包 |
| 干净 CI runner 一次成功 | 平台 | 合入默认分支前尽量完成 | 不得把本机结果写成 CI 通过 |
| License/C4 | 法律 | 本计划外 | 本文件不评价 |

不可延期（本轮已做）：ABI lifetime、contract envelope、production transport、
worker isolate、backup/restore、Saga O(N)+cursor+journal、Host Dart FFI、官方 AV/TTS DTO。

## 2. 任务对照

| 任务 | 结果 | 证据 |
|---|---|---|
| R-000 证据边界 | 通过 | `/tmp/grok-goal-anki-r000/baseline.txt`；未 reset/checkout |
| R-001 ABI | 通过（Host Rust） | `with_request_bytes`；45 Rust tests |
| R-002 contract/FFI | 通过（Host） | envelope 强制；`OfficialAnkiNativeTransport`；Host ENGINE_INFO |
| R-003 isolate/cancel | 部分通过 | 真实 isolate + Fake heartbeat 通过；Native 导入中 cancel 仍缺真机/5k 同测 |
| R-004 backup/restore | 通过（Host Rust） | close→copy/fsync/rename→独立 open；`backup_restore_round_trip` |
| R-005 Saga/catalog | 通过（Dart unit + Host FFI unicode） | journal 分块；cursor=`nextOffset`；恢复不从 0 重跑 |
| R-006 Host Dart FFI | 通过（unicode fixture） | `official_anki_host_ffi_test.dart` 全绿 |
| R-007 composition | 通过（代码+flag 默认关） | `OfficialAnkiCompositionRoot`；debug 内部页；release 仍 Legacy |
| R-008 AV/TTS | 通过（Host Native） | 官方 proto tags；sound + TTS golden |
| R-009 Android 新 APK | 部分 | 新 arm64 `.so` 已编；debug/release APK 未打 |
| R-010 真机 | 部分 | PLG110 debug：Spike open/check/reopen + 官方 import `blank (1).apkg` 181/181 `state=active`；无 release / 第二台设备 |
| R-011 性能/C2 | 部分 Host | Rust 100k 仍绿；无新 Android 指标；C2 未签字 |
| R-012 CI | 已落文件，未跑干净 runner | `.github/workflows/official_anki.yml` |
| R-013 文档 | 通过 | 本文件 + 02 去重 + 04/05/README 回指 |

## 3. Fake / Host / Android

| 项 | Fake unit | Host Rust | Host Dart FFI | Android |
|---|---|---|---|---|
| ENGINE_INFO | 是 | 是 | 是（真实 `.so`） | PLG110 debug Spike：abi=1、backend=967aa0d5… |
| open/check/close | 是 | 是 | 是 | PLG110 debug Spike：`state=closed error=none` |
| backup/restore | Fake 空实现 | 是 | 走真实 backup | 未测 |
| 9 fixture import | Fake 计数 | 是 | 仅 unicode 真实 Engine | PLG110 debug：`blank (1).apkg` 181 notes / 181 cards，`state=active` |
| 5k/100k | Fake 5k 索引 | 100k import 通过 | 未跑 5k/100k Dart 全链 | 未测 |
| isolate heartbeat | Fake isolate 通过 | n/a | n/a | 未测 |
| cancel during native import | Fake | Host Rust 有 | 未在 Dart 5k 上重跑 | 未测 |

## 4. 命令

```bash
# Native
./native/turna_anki_core/build-android/verify_pin.sh
# pin ok 967aa0d578fc75181e292e95326f9b58698da25c

./native/turna_anki_core/build-android/host-test.sh
# cargo fmt --check（bridge）+ clippy --lib -D warnings + cargo test --lib
# 45 passed (2026-08-17)

# Dart
dart analyze lib/application/anki_official
# No issues found

flutter test --no-pub test/application/anki_official
# Host FFI + orchestrator + recovery + contract + isolate：通过
# 其中 official_anki_host_ffi_test.dart：3 passed
```

Host 新 `.so`（debug，**不是** Android 证据）：

```text
path: native/turna_anki_core/target/debug/libturna_anki.so
bytes: 214964864
sha256: ef840f490f6d88f4e77644870d7180c5aa88c6f9a31c0003635b3d7b0cedead3
symbols: abi_version, engine_new, engine_open, call, cancel, engine_close, buffer_free
```

本轮新 Android arm64 `.so`（**不是** APK 证据，但是 R-001 之后的 native 产物）：

```text
path: android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
bytes: 20126392
sha256: 8672d0e81e081314ee0b71d334b400c4de3434f32127f8745c9dddb851a87f13
elf: ARM aarch64 shared object
symbols: abi_version, engine_new, engine_open, call, cancel, engine_close, buffer_free
command: ANDROID_NDK_HOME=$ANDROID_HOME/ndk/28.2.13676358 bash native/turna_anki_core/build-android/build.sh
```

R-000 标为 stale/non-evidence 的旧产物：

```text
android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
  2026-08-16 19:02  19245480  sha256 bf3196c8…121d28
build/app/outputs/flutter-apk/app-debug.apk
  2026-08-16 20:02  154284268
build/app/outputs/flutter-apk/app-release.apk
  2026-08-14 18:58  84247675  （不含 .so）
```

## 5. 代码修补摘要

- ABI：删除无约束 `'a` helper，改为 `with_request_bytes`；`engine_new` 校验 config 指针。
- Contract：`turna_anki_call` 强制 v1 envelope；name/id 必须一致；禁止 raw Spike 回退。
- Transport：`OfficialAnkiNativeTransport` 加载 `.so`、管理 handle、复制后 `buffer_free`。
- Worker：`OfficialAnkiSession` 使用持久 isolate；UI 可通过同一 handle 调 Native cancel/progress。
- Backup：先官方 `maybe_backup`，再 close + fsync + 原子 rename；`RESTORE_BACKUP` 独立 open/check。
- Saga：每批只写当前 descriptors；cursor 为下一批起点；Note ID 进 `anki_import_attempt_notes`。
- AV：映射官方 `q_tags/a_tags`（sound_or_video / tts），删除手工 `[sound:]` 扫描。
- Flags：`--dart-define` / `fromEnvironment()`；release 默认全 false。

## 6. 仍禁止

- 打开 release official import flag。
- 删除 Legacy importer / renderer / SRS。
- 把 Host 通过写成 Android 通过。
- 用旧 APK 或 19:02 jniLibs `.so` 做验收。
- 把 License/About 写成已由本计划关闭。
