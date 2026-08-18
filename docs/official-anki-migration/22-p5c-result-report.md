# P5-C Fixture Pilot 实施验收与结果报告

> 文档代号：P5C-RESULT  
> 日期：2026-08-18  
> 仓库：`Varnamalaplus`  
> 实施依据：[`21-p5c-fixture-pilot-implementation-playbook.md`](./21-p5c-fixture-pilot-implementation-playbook.md)、[`14-phase-4-audit-remediation-and-phase-5-execution-plan.md`](./14-phase-4-audit-remediation-and-phase-5-execution-plan.md) §8、[`15-p5-legacy-inventory.md`](./15-p5-legacy-inventory.md)  
> 官方 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 产物位置：`artifacts/p5c/`  

---

## 1. 最终结论

```text
P4 PRODUCTION DEFAULT FLAGS: still false
P5-C FIXTURE PILOT: CONDITIONAL GO (Host + Device A)
P5 USER CUTOVER: NO-GO
P5-D PRODUCTION ROUTING: HOLD
P5 LEGACY DELETION: NO-GO
Device B: out of scope
```

---

## 2. 施工与验收明细

| 工作包 | 任务项 | 状态 | 交付物 / 核心逻辑 |
|---|---|---|---|
| **P5C-00** | 基线、Allowlist 与 MIGRATION_PILOT 开关 | **PASS** | `OfficialAnkiFeatureFlags` 增加 `migrationPilot`（默认 `false`）；`isFixturePilotSource` 仅放行 allowlist 测试源；`artifacts/p5c/baseline.txt`。 |
| **P5C-01** | Fixture 包与身份校验 | **PASS** | `test/application/anki_official/fixtures/p5c/basic-cloze.apkg` 及 `.sha256`。 |
| **P5C-02** | Coordinator migrating lease 互斥 | **PASS** | `OfficialAnkiOperationCoordinator` 增加 `migrating` phase，与 `reviewing`/`importing`/`backupRestore` 互斥。 |
| **P5C-03** | 重选原包与 Hash 校验 | **PASS** | `OfficialAnkiFixturePilotSaga.pickAndValidatePackage`，Hash 不匹配停在 `needsUserAction`。 |
| **P5C-04** | 真实物理文件备份（非仅 JSON 收据） | **PASS** | `LegacyAnkiBackupService.createPhysicalBackup` 产出 `legacy-manifest.json`、`legacy-subset.sqlite`、`collection.anki2`、`collection.media/`、`official_catalog.sqlite`、`SHA256SUMS`（**无卡片 HTML/正文**）。 |
| **P5C-05** | 官方 Import Saga 复用 | **PASS** | 复用 `OfficialAnkiImporter.importFile`，CAS 写入 `official_source_id`。 |
| **P5C-06** | Dry-Run 100% 唯一匹配 | **PASS** | 复用 `LegacyAnkiDryRunSaga`，未全匹配停在 `needsUserAction`。 |
| **P5C-07** | 课程投影重建 | **PASS** | `projectingCourse` 成功推进至 `verifying`，失败流转至 `failedRecoverable`。 |
| **P5C-08** | Verifying 计数与结构对账 | **PASS** | 比对 notes/cards/decks/media 与投影项数量。 |
| **P5C-09** | cutoverReady / cutover / observing | **PASS** | 仅 allowlist 来源推进至 `cutoverReady` $\rightarrow$ `cutover`（写入 catalog `recordedKind=official` 及 `official_mutation_count_at_cutover`）$\rightarrow$ `observing`。 |
| **P5C-10** | Legacy 来源只读保护与 AnkiWriteGuard | **PASS** | `AnkiSrsMigrator` 接入 `AnkiWriteGuard`，拒绝向已 cutover 的 official source 写入 Turna SRS。 |
| **P5C-11** | 双路径回滚演练 | **PASS** | 验证 mutation=0 允许 `rollbackEligible`，mutation>0 保护为 `noLegacyScheduleRollback`；`artifacts/p5c/rollback-drill.txt`。 |
| **P5C-12** | Host 完整集成测试与产物收据 | **PASS** | 216 项测试全绿，0 分析警告；产物收据已写入 `artifacts/p5c/`。 |
| **P5C-13** | Device A 隔离演练与用户数据防篡改 | **PASS** | 安装 release APK（`d3bf329...`），验证非 allowlist 来源禁用 Pilot/Cutover，官方复习评分 1 次成功，0 UI stall；`artifacts/p5c/device-a-fixture-pilot.txt`。 |

---

## 3. 测试与静态分析证据

- **Flutter 测试套件**：`test/application/anki_official/` 全量 **216 passed / 0 failed**。
- **静态代码分析**：`flutter analyze lib/application/anki_official lib/views/anki_official test/application/anki_official` **0 issues found**。
- **Device A 真机验证（PLG110，API 36）**：
  - Release APK SHA256: `d3bf329e7c6fd946676d821bc8fa06d15e17fcbf477d313be7cc7c6bcbe03089`
  - Native `.so` SHA256: `824def69076389a505787ad52285f1bee4fbe056b4c8f6e541d3979217e75ad5`
  - 5 段哈希链一致闭环（`official_native_hash_manifest.sh` exit 0）
  - 官方复习打分：`rated=1 good=1 timeout=0 superseded=0 unrenderable=0`
  - 内存与性能：Peak PSS 289MB, Native Heap 80MB, 0 stall > 500ms
- **关键审计测试清单（全部通过）**：
  1. `legacy_migration_dry_run_is_read_only_and_idempotent`
  2. `legacy_migration_crash_resumes_every_checkpoint`
  3. `legacy_source_never_has_two_writable_engines`
  4. `cutover_with_official_mutation_cannot_restore_legacy_schedule`
  5. `fixture_pilot_rejects_non_allowlist_source`
  6. `fixture_pilot_requires_reselected_package_hash`
  7. `backup_files_exist_and_contain_no_card_html`
  8. `cutoverEnabled_stays_false`
  9. `preview_cutover_button_stays_disabled`
  10. `cutover_fixture_source_denies_turna_srs_answer`

---

## 4. 产物收据清单

所有审计文件落盘于 `docs/official-anki-migration/artifacts/p5c/`：

1. [`baseline.txt`](./artifacts/p5c/baseline.txt)：记录 Git commit、APK sha、Flag 状态及结论。
2. [`fixture-allowlist.txt`](./artifacts/p5c/fixture-allowlist.txt)：仅包含官方测试包 SHA256，严禁真实用户卡组进入。
3. [`host-pilot.txt`](./artifacts/p5c/host-pilot.txt)：完整记录 Saga 11 个 Checkpoint 单向推进收据。
4. [`rollback-drill.txt`](./artifacts/p5c/rollback-drill.txt)：双路径回滚演练记录（mutation=0 允许回滚路由，mutation>0 拒绝覆盖进度）。
5. [`device-a-fixture-pilot.txt`](./artifacts/p5c/device-a-fixture-pilot.txt)：Device A 真机隔离演练与非 allowlist 保护收据。
6. `device-a-pilot-review.png`：Device A 官方复习界面截图收据。

---

## 5. 硬约束合规检查

```text
[✓] LegacyAnkiMigrationFlags.cutoverEnabled 保持 false
[✓] AnkiReviewRoute / AnkiImportRoute 生产默认路由完全未动
[✓] TURNA_OFFICIAL_ANKI_* 默认值保持 false
[✓] lib/application/anki 与 lib/views/anki 源码与表结构完全保留（未删除任何 Legacy 代码）
[✓] 未向官方 Collection 写入任何伪造 revlog
[✓] 未迁移任何非 allowlist 真实用户牌组
[✓] 预览页生产路径 Cutover 按钮保持 disabled
```

---

## 6. 下一步准入与后续阶段（P5-D / P5-E）

在接到产品团队明确的「进入 P5-D」指令前，**P5-D（生产路由分流）与 P5-E（删除 Legacy）继续保持 HOLD**。

**P5-D 解锁前置条件（待产品评审）**：
1. P5-C 观察期无 P0/P1 问题；
2. 产品书面接受「Android 先行切官方内核，OHOS 继续保留 Legacy 共享实现」的平台分流策略；
3. 完成生产路由 Resolver 分级灰度（1% $\rightarrow$ 10% $\rightarrow$ 50% $\rightarrow$ 100%）与回滚 Runbook。
