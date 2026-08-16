# Phase 1 结果报告：稳定 Engine 与官方导入

> 结论：**Conditional Go**  
> 日期：2026-08-16  
> 工作树基线：`f422c840efb019098af5f9aec32746817516c824`（Phase 1 代码尚未单独提交）  
> 上游 Anki：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 生产切流：**禁止**。官方导入 flag 默认关闭。  
> 打开 release import 的前提：用 **本轮 ABI 修复后的 commit** 重编 debug **和** release APK，并在真机跑完 `ENGINE_INFO → open → import fixture → close → reopen`。当前磁盘上的 8 月 14 日 release APK 与 19:02 jniLibs `.so` 都不算。

本文件只记录本轮已测量事实。未测项不写“通过”。

## 1. 决策

可以继续 Phase 2 的渲染设计与脚手架，但不得打开 release import flag，也不得删除 Legacy。

未关闭条件：

| 条件 | 本轮 | 限制 |
|---|---|---|
| C1 release APK + 真机闭环 | 未关闭 | 不得打开 release import flag |
| C2 体积签字 | 未签字 | 不得发含 `.so` 的外部包 |
| C4 法律签字 | 未签字 | 不得发含 `.so` 的外部包 |
| ABI 修复后的新 `.so` 真机回归 | 未测 | 旧 debug 真机结果不能作为最终 Android 验收 |

已工程化关闭或本轮可证明：

| 项 | 结果 |
|---|---|
| ABI alloc/free / 非 `'static` 请求 / panic boundary | 通过（Host Rust） |
| contract v1 envelope + `ENGINE_INFO` 构建期 commit | 通过 |
| 9 fixture + 5k 来源索引 + 同 hash 去重 + 取消 | 通过（Host + Dart orchestrator） |
| 100k host import | 通过：3614 ms；峰值 RSS 1 035 208 KiB |
| 九个 fault 恢复决策 | 通过 |
| 生产 License 页注册 Anki AGPL | 通过（代码 + 测试） |
| 默认导入路径仍为 Legacy | 通过 |

## 2. 基线

```text
Turna HEAD:             f422c840efb019098af5f9aec32746817516c824
Anki submodule:         967aa0d578fc75181e292e95326f9b58698da25c
Rust:                   rustc 1.97.1
Flutter:                3.44.8 stable (058e0af2c2)
Dart:                   3.12.2
host-test.sh:           cargo fmt --check + clippy --lib -D warnings + cargo test
```

工作树仍有大量与本阶段无关的既有改动。本阶段新增/修改集中在
`native/turna_anki_core/`、`lib/application/anki_official/`、
`test/application/anki_official/`、两处生产 License 入口和导入 facade 钩子。

## 3. 命令与测试

```bash
./native/turna_anki_core/build-android/host-test.sh
# lib tests: 33 passed (2026-08-16)

flutter test test/application/anki_official/official_anki_contract_test.dart
# All tests passed (6)

flutter test test/application/anki_official/official_anki_import_orchestrator_test.dart
# All tests passed (9)

flutter test test/application/anki_official/official_anki_recovery_test.dart
# All tests passed (10)

flutter test test/application/anki_official/official_anki_license_test.dart \
  test/application/anki_official/official_anki_license_hook_test.dart
# All tests passed (4)

dart analyze lib/application/anki_official \
  lib/views/settings/about_turna_page.dart \
  lib/views/settings/widgets/settings_about_section.dart
# No issues found
```

## 4. ABI / contract

- 返回缓冲改为 `Box<[u8]>`；释放走 `Box::from_raw(slice)`。
- 请求 slice 生命周期限定在当次 FFI entry，不再是 `&'static [u8]`。
- 空缓冲、1 字节、非精确 capacity、10 万次 alloc/free、null/oversize、panic mapping 均有测试。
- `ENGINE_INFO` 与 envelope 请求的 `IMPORT_PACKAGE` 走 JSON v1；backend commit 由 `build.rs` 注入 `contract/BACKEND_COMMIT`。
- 未知 major 返回 `CONTRACT_VERSION_MISMATCH`。
- `turna_anki_spike.proto` 已归档到 `native/turna_anki_core/contract/archive/`。JSON 是唯一 wire。

## 5. 导入 / catalog / 恢复

- 独立 `OfficialAnkiDatabase`（sqlite3，不在 `CourseDatabase`）。
- 表只有 `anki_sources` / `anki_source_cards` / `anki_import_attempts`。无 fields / qfmt / CSS / HTML / schedule 列。
- 9 个冻结 fixture 经 hasher + orchestrator + catalog，来源 Card 计数与 manifest 一致。
- 同 hash 不产生第二个 active source。
- 取消后 source 不是 `active`。
- 未来 schema version fail closed。
- 关闭/重开 catalog 仍识别来源。
- 故障点：hash 前无 active；source 已写未 checkpoint → `failed_before_import`；checkpoint 已写 / import 返回未落盘 Note IDs → `needs_reconciliation`（与“import 中死亡结果不明”不可区分）；Note IDs 之后续跑索引至 active；active 后重启幂等；未知状态永不标 `active`。
- 同 hash 未完成来源再次 `importFile` 走 `decideOfficialAnkiRecovery`，不再直接 `resumeIndexing`。空 Note ID 不能被标成 `active`（`afterCheckpointBeforeImport` / `afterImportBeforeNoteIds` 后再调 `importFile` 的测试覆盖）。
- orchestrator / recovery 不构造 `AnkiImporter` / `AnkiImportService`。

## 6. 规模

| 场景 | 结果 |
|---|---|
| 5k Dart index batches (page 200) | 5000 notes / 5000 cards，active |
| 100k Host `import_apkg` | 3614 ms；notes=100000 cards=100000 |
| 100k 过程峰值 RSS | 1 035 208 KiB（`/usr/bin/time -v`，含 cargo test 进程） |
| SEARCH_CARDS_PAGE | 无 Note 字段；stale token → `PAGE_TOKEN_STALE` |

未在本轮对 100k 做 Dart isolate 峰值测量。

## 7. Android 产物

| Artifact | 时间 | SHA-256 | `libturna_anki.so` |
|---|---|---|---|
| debug APK 148 MiB | 2026-08-16 20:02 | `37bc6ed8…ab29ad` | 有，16 078 224 字节 |
| release APK 81 MiB | 2026-08-14 18:58 | `1ebc683b…7b2036be` | **无**（旧包，不当证据） |
| jniLibs `.so` 19 245 480 | 2026-08-16 19:02 | `bf3196c8…121d28` | 未 strip；早于 ABI 修复 |

`adb devices` 本轮为空。用户称此前 debug 真机已加载 `.so`；本轮未复测，且 ABI 修复后需要新 `.so`。

未尝试本轮 release 构建（避免再次 OOM）；未把 8 月 14 日 APK 当作通过。

## 8. Feature flag 与许可

- `OfficialAnkiFeatureFlags` 默认 `engine/import/diagnostics` 全 false。
- `import` 还要求 catalog / capability / platform；缺一 fail closed。
- `AnkiImportFacade.resolve()`：flag off 走 Legacy；official 失败不回退 Legacy。
- `showTurnaLicensePage` 在两个生产入口调用 `registerOfficialAnkiLicenses()`。

C2 体积与 C4 法律仍无书面签字。

## 9. 未决风险

| ID | 风险 | 影响 |
|---|---|---|
| R-REL | 无本轮含 `.so` 的 release APK | 挡住无条件 Go |
| R-DEV | 本轮无 adb；ABI 修复后未真机回归 | 挡住 release import flag |
| R-VOL | strip 后约 16 MiB native，产品未签字 | 挡住外部包 |
| R-LIC | 法律未签 | 挡住外部包 |
| R-SO | 磁盘 jniLibs `.so` 早于 ABI 修复 | 真机必须重编 |

## 10. 结论

```text
CONDITIONAL GO
```

Phase 1 的 Host 契约、Engine/worker、独立 catalog、导入 Saga、恢复矩阵和默认关闭的生产入口已经落地并有测试证据。  
Phase 1 退出表中的 Android release/真机、C2、C4 仍未关闭。官方导入不是用户默认路径。
