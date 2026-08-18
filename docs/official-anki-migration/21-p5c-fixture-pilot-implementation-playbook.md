# P5-C Fixture Pilot 施工手册

> 文档代号：P5C-HOWTO  
> 日期：2026-08-18  
> 前置：[`14`](./14-phase-4-audit-remediation-and-phase-5-execution-plan.md) §8、[`15`](./15-p5-legacy-inventory.md)、[`16`](./16-p4r3-production-gate-and-p5b-prep-plan.md) / [`18`](./18-p4r3-audit.md) / [`19`](./19-p4r3-implementation-playbook.md)、[`20`](./20-p4-remaining-polish-plan.md)、`artifacts/p4r2/`  
> 产品指示：进入 P5。本文件是 **P5-C 怎么改、怎么跑、怎么才算过**。  
> 不是 P5-D 生产路由，不是 P5-E 删 Legacy。

## 1. 结论先行

```text
本轮：只对内部 fixture / 无价值测试号跑单来源迁移 Saga
写到 cutoverReady → observing，不删数据
LegacyAnkiMigrationFlags.cutoverEnabled 保持 false
AnkiReviewRoute / AnkiImportRoute 生产默认不动
TURNA_OFFICIAL_ANKI_* 默认仍 false
P5-D / P5-E：HOLD
Device B：out of scope
```

P5-C 的可观察定义（`14` §8 收成施工口径）：

```text
allowlist fixture
  → coordinator 拿 migration lease
  → 用户重选原 .apkg 且 hash 一致
  → 备份 Legacy 子集 + official Collection 文件
  → 官方 Import Saga
  → dry-run 100% 唯一匹配（否则停）
  → 重建 course projection
  → 计数对账
  → 只对该 source 写 cutoverReady
  → 该 Legacy source 只读（禁止再写 Turna SRS）
  → 用内部「正式复习」观察官方 Collection
  → 不删 Legacy 行、不改生产路由
```

未接到「进入 P5-D」前，禁止把 fixture 成功写成「用户数据可以迁」。

## 2. 准入（开工前当场勾）

这些已经有 artifact。缺一条先停，不要用过期报告充数。

| 项 | 复算命令 / 文件 | 过 |
|---|---|---|
| Device A 正式复习 | `artifacts/p4r2/device-a-release-100.txt` 的 apk sha = 当前要装的 APK | rated=100，timeout=0，superseded=0，revlog delta=100 |
| PlatformView 复用 | `device-a-release-20-reuse.txt` | 同会话 `create viewId=` 一次 |
| Native hash | `bash tool/official_anki_native_hash_manifest.sh` | 无 MISSING；built==jniLibs；apkSo==stripped==deviceSo；deviceApk==apk |
| Host 测试 | `flutter test --no-pub test/application/anki_official` | 全绿 |
| 生产 cutover 开关 | 源码 + `official_anki_p5_prep_test.dart` | `cutoverEnabled == false` |
| 预览 Cutover 按钮 | `official_anki_migration_preview_page.dart` | 生产路径 `onPressed == null` |
| Device B | `adb devices` | 缺席写 out of scope，不写 PASS |

Device A 当前已记账 APK：`a8161e8877b848aad7d6cb6f2a18d5002b25595c1cf904e1e822b1fe52545cac`。换 APK 必须重跑 hash，禁止抄旧 sha。

## 3. 硬约束（全程）

```text
不写 LegacyAnkiMigrationFlags.cutoverEnabled = true
不改 AnkiReviewRoute / AnkiImportRoute 生产默认
不把 TURNA_OFFICIAL_ANKI_* 默认改成 true
不删 lib/application/anki 或 lib/views/anki
不伪造官方 revlog / 不把 Turna SRS 翻译成 revlog
不迁移用户真实牌组（考研政治默写、German、任何非 allowlist 来源）
不 wipe files/official_anki/default/collection.anki2
不为超时重建 WebView
不补 OHOS official Core
不做 Phase 6 AnkiWeb Sync
```

内部 APK 仍只用 dart-define 打开官方能力。P5-C 另加一个 **默认 false** 的 fixture 开关：

```bash
# 加在 19 的 DEFINES 后面，禁止写进 OfficialAnkiFeatureFlags 默认值
--dart-define=TURNA_OFFICIAL_ANKI_MIGRATION_PILOT=true
```

`MIGRATION_PILOT=true` 只允许对 **allowlist** 来源点「Fixture pilot」。它不是 `cutoverEnabled`。

## 4. 已经有、不要重做

| 能力 | 现成符号 | 本轮 |
|---|---|---|
| Legacy 30 文件盘点 | `15`、`official_anki_p5_prep_test` | 只读 |
| Census（无正文） | `LegacyAnkiCensusService`、`DatabaseLegacyAnkiCensusReader` | 复用 |
| 身份 + matcher | `LegacyAnkiCardIdentity`、`LegacyAnkiDryRunMatcher` | 复用 |
| Dry-run 续跑 | `LegacyAnkiDryRunSaga` | 复用；不要第二套 matcher |
| 状态机 + CAS | `LegacyAnkiMigrationState`、`OfficialAnkiMigrationDao.transition` | 只沿合法边走 |
| Backup **收据** | `LegacyAnkiBackupService.generateFromCensus` / `persist` | 保留；P5C-04 要补 **文件副本** |
| Preview UI | `OfficialAnkiMigrationPreviewPage` | Cutover 按钮继续 disabled |
| 官方导入 | `OfficialAnkiImporter.importFile` / worker `importFile` | 复用 |
| 课程投影 | 现有 source-management generate/publish job | 复用 |
| 写边界标签 | `AnkiWriteGuard` | 接到真实写路径 |
| 正式复习 | 内部页 → `OfficialAnkiReviewPage` | 观察入口，不改生产路由 |
| Coordinator | `OfficialAnkiOperationCoordinator` | 加 `migrating` lease，不要第二把锁 |

Catalog 已是 v7（含 `legacy_anki_migrations` / card map / `official_mutation_count_at_cutover`）。不要再发明 v8，除非缺列且写进 forward migration + future-version fail-closed。

## 5. 本轮是什么、不是什么

| | P5-C（本文件） | P5-D（HOLD） | P5-E（HOLD） |
|---|---|---|---|
| 对象 | 内部 fixture / 测试号上的 **一个** Legacy import | 生产 `AnkiImportRoute` / `AnkiReviewRoute` | 删 Legacy 代码和表 |
| 路由 | 生产入口仍 Legacy | 按 resolver 分流 | 生产不再构造 Legacy writer |
| 开关 | `MIGRATION_PILOT` + allowlist | 分级 release flag | 禁止 import 规则 + 单独 schema PR |
| 数据 | 备份、导入、map、投影、观察 | 灰度 + rollback drill（两台设备） | tombstone |
| 删除 | 禁止 | 禁止 | 观察期后再谈 |

Android 先行：OHOS 继续 Legacy。P5-C 成功也不等于可以删共享实现（`14` §9）。

## 6. 允许名单

只认下面任一条件，否则 Saga 必须在 `detected` / `needsUserAction` 停：

1. Host 测试：`legacyImportId` 以 `p5c-fixture-` 开头，或 golden 目录 `test/application/anki_official/fixtures/legacy_match/` 对应的合成 import。
2. 设备：事先写入 `artifacts/p5c/fixture-allowlist.txt` 的 **sourceHash**（sha256 of the re-picked `.apkg`）。当前不要把用户牌组 hash 写进去。
3. 显示名 / 路径包含 `p5c-fixture` 且内部页显式确认。

用户 Collection 里的 `考研政治默写`（deck `1787046637039`）和任何 German 来源 **不在名单**。预览页对它们只显示 census / unmatched，Pilot 按钮保持 disabled。

建议 Host fixture：用现有 Basic/Reverse/Cloze golden 身份，再做一个 **很小的** `.apkg`（≤ 20 张，含 1 张 Cloze 或 Reverse）。放在：

```text
test/application/anki_official/fixtures/p5c/basic-cloze.apkg
test/application/anki_official/fixtures/p5c/basic-cloze.sha256
```

不要把用户 `collection.anki2` 拷进 fixtures。

## 7. 状态机怎么走

沿用 `legacyAnkiMigrationAllowsTransition`，禁止跳边。

```text
detected
  → awaitingPackage          用户点选原包
  → validatingSource         sha256 == census.sourceHash
  → backingUp                Legacy 子集 + official 文件副本
  → importingOfficial        现有 Import Saga
  → indexingOfficial         列出 official card identities
  → mappingCards             DryRunSaga；unresolved>0 → needsUserAction（停）
  → projectingCourse         现有 generate/publish
  → verifying                note/card/deck/media/课程位置
  → cutoverReady             只写 allowlist source
  → cutover                  记录 recordedKind=official（catalog 行，不是全局 flag）
  → observing                内部正式复习；不删 Legacy
```

回滚：

```text
cutover 之前任意失败 → rolledBackLegacy（路由仍 Legacy）
cutover 之后 official mutation=0 → rollbackEligible（可把 recordedKind 改回 legacy）
cutover 之后 official mutation>0 → noLegacyScheduleRollback
  （禁止把旧 Turna SRS 重新设为事实源）
```

`official_mutation_count_at_cutover` 在进入 `cutover` 时写入当时官方 revlog 行数。之后 `revlog` 增量 > 0 则只能去 `noLegacyScheduleRollback`。

## 8. 开工顺序

```text
P5C-00  基线、allowlist、migrating lease、MIGRATION_PILOT 开关
P5C-01  fixture 包 + sha256 + Host 身份 reader
P5C-02  Coordinator migrating 与 review/import 互斥
P5C-03  重选 .apkg 校验 hash；失败停在 needsUserAction
P5C-04  真实文件备份（不只 JSON 收据）
P5C-05  官方 Import Saga（复用 importFile）
P5C-06  Dry-run 100% 唯一匹配，否则停
P5C-07  重建 projection（复用现有 job）
P5C-08  verifying 计数与 renderer fixture
P5C-09  cutoverReady / cutover（仅 allowlist）
P5C-10  该 source 只读；AnkiWriteGuard 接到 Legacy 写路径
P5C-11  回滚两条路径 + 测试
P5C-12  Host 集成测试 + artifacts/p5c
P5C-13  可选 Device A fixture drill（新小牌组，不碰用户卡）
```

下面按项写「改哪里 / 禁止 / 怎么过」。

### P5C-00 基线与开关

**改哪里**

| 文件 | 改动 |
|---|---|
| `lib/application/anki_official/official_anki_feature_flags.dart` | 增加 `migrationPilot`，`fromEnvironment('TURNA_OFFICIAL_ANKI_MIGRATION_PILOT')`，**默认 false** |
| `lib/application/anki_official/migration/official_anki_engine_kind.dart` | `cutoverEnabled` 保持 `false`。另加 `isFixturePilotSource({importId, sourceHash})` |
| `lib/application/anki_official/engine/official_anki_operation_coordinator.dart` | 增加 `migrating`；与 `reviewing` / `importing` / `backupRestore` 互斥 |
| `artifacts/p5c/baseline.txt` | HEAD、dirty 行数、`cutoverEnabled=false`、当前 Device A apk sha |

**禁止**

- 把 `migrationPilot` 并进 `allowsOfficialScheduler`
- 用 `cutoverEnabled` 给预览页 Cutover 按钮解禁

**过**

```text
const OfficialAnkiFeatureFlags().migrationPilot == false
LegacyAnkiMigrationFlags.cutoverEnabled == false
isFixturePilotSource(importId: 'user-deck') == false
isFixturePilotSource(importId: 'p5c-fixture-basic') == true
```

### P5C-01 fixture 包

**改哪里**

- 新增 `test/application/anki_official/fixtures/p5c/`
- sha256 文件与 `.apkg` 并排，测试里当场 `sha256sum` 对账
- Host 用 Fake engine + 这份身份，不要依赖 Device A 用户库

**禁止** 把用户 `collection.anki2` / 考研政治默写导出当 fixture。

### P5C-02 migration lease

**改哪里**

`OfficialAnkiOperationCoordinator`：

```text
acquire(migrating)  仅 idle 可进入
reviewing 时 acquire(migrating) → operation_conflict
migrating 时 guardSchedulerWrite / acquire(reviewing) → conflict
release(migrating) 回到 idle
```

`LegacyAnkiFixturePilotSaga`（新文件，见 P5C-03 起）进入时 `acquire(migrating)`，`finally` 里 `release`。

Preview / census 继续 **不** acquire。

**过**：单测 `migration_lease_blocks_review_and_import`。

### P5C-03 重选原包 + hash

**改哪里**

新 Saga：`lib/application/anki_official/migration/official_anki_fixture_pilot_saga.dart`

```text
start(legacyImportId)
  dao.insertDetected / 或从 detected 恢复
  → awaitingPackage
pickPackage(file)
  sha256(file) == census.sourceHash
    → validatingSource → backingUp
  否则 → needsUserAction（messageKey=official_anki.migration_package_mismatch）
```

内部预览页：allowlist 且 `migrationPilot==true` 时显示「选择原 apkg 并试跑 Pilot」。非名单来源不显示。

**禁止** 静默使用磁盘上「可能是原包」的缓存路径。必须用户再选一次。

### P5C-04 真实备份

现有 `LegacyAnkiBackupService` 只写 counts/hash JSON，**不够**。

**改哪里**

在 `OfficialAnkiPaths.backups / p5c/<migrationId>/` 落：

```text
legacy-manifest.json          现有收据（无正文）
legacy-subset.sqlite          CourseDatabase 中该 importId 的 notes/cards/srs/review_events 导出
collection.anki2              官方 Collection 副本
collection.media/             媒体目录副本（可硬链；失败则 copy）
official_catalog.sqlite       catalog 副本
SHA256SUMS
```

`backingUp` 完成前这些文件必须 `existsSync`。`recordInDao` 写 `backupId` + `backupManifestHash`。

**禁止**

- 收据当备份
- 备份文件里写 `questionHtml` / 字段正文（subset 只留 id、guid、ord、wordId、counts）
- 把备份写到 `CourseDatabase`（downgrade 会清）

**过**：`backup_files_exist_and_contain_no_card_html`。

### P5C-05 官方导入

**改哪里**

Saga 在 `importingOfficial` 调用现有：

```dart
await OfficialAnkiCompositionRoot.requireImporter(supportDir: ...).importFile(
  packagePath: pickedApkg,
  displayName: 'p5c-fixture-...',
);
```

把返回的 `sourceId` 写入 `dao.transition(..., officialSourceId: ...)`。

**禁止** 再写一套 importer；禁止 in-process fallback（`rejectInProcessForProduction` 已在）。

崩溃：从 `dao.findByLegacyImport` 读 state，CAS 恢复。已导入则不要二次 `importFile`，除非 official source 不存在。

### P5C-06 dry-run 100% 匹配

**改哪里**

`indexingOfficial`：`OfficialAnkiSourceDao.listCards` → `OfficialAnkiCardIdentity`。  
`mappingCards`：`LegacyAnkiDryRunSaga.run`（已有 cursor）。

退出：

```text
unresolvedCount == 0
collision == 0
matchedCount == legacyCardCount
```

否则 `needsUserAction`，**不要** `projectingCourse`。用户排除某张卡必须显式 `excluded`，并重跑 matcher。P5-C 不实现「猜一张」。

`sameTrustedPackage: true` 仅当 P5C-03 hash 已通过。

**过**：golden 全 matched；故意缺 GUID 的 fixture 停在 `needsUserAction`。

### P5C-07 重建投影

**改哪里**

`projectingCourse` 调现有 generate/publish job（`officialAnkiBuildSourceManagementPage` 同一套 store / jobs），`profileId=profile-default-01`。

**禁止** 手写第二套 section/lesson 插入。失败 → `rollbackRequired` 或 `failedRecoverable`，不要 `cutoverReady`。

### P5C-08 verifying

对账表（写入 artifact，禁止只打日志）：

| 项 | 比什么 |
|---|---|
| notes / cards / decks / media | Legacy census vs official source |
| card map | 每一行 `matchState=matched` 且 `officialCardId` 非空 |
| 课程位置 | projection item 数 = matched 卡数 |
| renderer | Host 至少 1 张 question/answer HTML 非空（fixture，无用户正文入库到测试断言字符串） |
| dry-run 二次 | 同一输入再跑，card map 行完全一致 |

差异必须有解释字段。解释不了 → `needsUserAction`。

### P5C-09 cutoverReady / cutover

**改哪里**

```text
verifying 通过
  → cutoverReady     仅 allowlist
  → cutover          catalog 记录该 source recordedKind=official
                     official_mutation_count_at_cutover = 当时 revlog 行数
  → observing
```

预览页：

- 按钮文案：`Fixture pilot`（key=`official-migration-fixture-pilot`）
- 原 `Cutover (disabled)` **继续 disabled**，key 不变
- `onPressed` 条件：`flags.migrationPilot && isFixturePilotSource && unmatched==0 && coordinator.idle`

**禁止**

```text
LegacyAnkiMigrationFlags.cutoverEnabled = true
AnkiReviewRoute 改 OfficialAnkiReviewPage
对非 allowlist 写 cutoverReady
```

Resolver：`cutoverEnabled` 仍 false。`recordedKind` 只影响 **已经 cutover 的那一个** source。生产复习入口本轮仍不读它（P5-D 才读）。

### P5C-10 该 source 只读 + 观察

**改哪里**

把 `AnkiWriteGuard` 接到真实写路径（现在只有单测）：

| 路径 | owner | cutover 后的 fixture source |
|---|---|---|
| `anki_srs_migrator.dart` / review commit | `turnaSrs` | deny |
| Legacy `anki_note_dao` 评分相关 update | `legacyAnkiDao` | deny |
| `OfficialReviewSession.answer/undo/bury` | `officialScheduler` | allow |
| 课程 preview / derived exercise | `projection` | 评分类 deny |

观察官方复习：**只走内部页「正式复习」**。不要把首页 due 改成官方队列。

**过**

```text
legacy_source_never_has_two_writable_engines
cutover_fixture_source_denies_turna_srs_answer
official_review_via_internal_page_still_works
```

### P5C-11 回滚

| 时机 | 动作 |
|---|---|
| `cutover` 前 | `rolledBackLegacy`；删掉本轮 official source 可选，但必须可从 backup 恢复 catalog 行；Legacy 行保持可写 |
| `cutover` 后 mutation=0 | `rollbackEligible`：recordedKind 改回 legacy；官方 Collection 保留但不再作为该 source 事实源 |
| mutation>0 | 拒绝回滚调度；只允许观察 / 导出 |

**过**：`cutover_with_official_mutation_cannot_restore_legacy_schedule`（`14` §11 点名）。

### P5C-12 Host 测试与 artifact

必跑：

```bash
cd Varnamalaplus
flutter test --no-pub test/application/anki_official
flutter analyze --no-pub \
  lib/application/anki_official \
  lib/views/anki_official \
  test/application/anki_official
```

本轮至少新增（名称尽量原样，方便 `14` §11 对账）：

```text
legacy_migration_dry_run_is_read_only_and_idempotent   # 已有则加断言，不复制
legacy_migration_crash_resumes_every_checkpoint
legacy_source_never_has_two_writable_engines
cutover_with_official_mutation_cannot_restore_legacy_schedule
fixture_pilot_rejects_non_allowlist_source
fixture_pilot_requires_reselected_package_hash
backup_files_exist_and_contain_no_card_html
cutoverEnabled_stays_false
preview_cutover_button_stays_disabled
```

写 `artifacts/p5c/`：

```text
baseline.txt
fixture-allowlist.txt
host-pilot.txt          migrationId、states、counts、sha、是否写过 cutoverReady
rollback-drill.txt      两条回滚路径
```

收据禁止卡片正文。

### P5C-13 Device A（可选，且隔离）

**只有 Host P5C-12 全绿才允许上机。**

```text
另装内部 debug/release（带 MIGRATION_PILOT=true）
导入 fixtures/p5c 小牌组到 Legacy（Anki 导入），不要用已有用户牌组
设置 → 高级（大行）→ Official Anki 内部导入 → Legacy 迁移预览
确认 考研政治默写 的 Pilot 按钮 disabled
对 fixture 来源：重选同一 .apkg → Fixture pilot
内部页「正式复习」评 1 张 Good
adb 确认用户 collection 仍在、revlog 增量只来自 fixture 官方 source
```

**禁止** `new_per_day` 再改用户 Default config（那是 P4 门禁用过的）；禁止 wipe；禁止把 Device A 用户 100 张会话当成 P5 证据。

设备证据另写 `artifacts/p5c/device-a-fixture-pilot.txt`，带 apk sha。没有设备就标 `DEVICE NOT RUN`，Host 仍可收 P5-C HOST CONDITIONAL GO。

## 9. 预览页按钮口径

```text
Cutover (disabled)     永远 disabled（P5-D 之前）
Fixture pilot          仅 migrationPilot && allowlist && unmatched==0
选择原 apkg            仅上一条为 true
```

生产 / 默认 flag 构建里两个按钮都不可点。测试锁死：

```dart
expect(LegacyAnkiMigrationFlags.cutoverEnabled, isFalse);
expect(source.contains("Cutover (disabled)"), isTrue);
expect(source.contains("official-migration-cutover-disabled"), isTrue);
```

## 10. 什么时候才能改 `final-decision.txt`

P5-C **Host** CONDITIONAL GO 需要：

1. 第 2 节 P4 清单仍能复算（或写明沿用哪份 apk sha）
2. `cutoverEnabled == false`，Cutover 按钮仍 disabled
3. 上表 Host 测试全绿
4. `artifacts/p5c/host-pilot.txt` 有一次完整 `detected → observing`
5. `rollback-drill.txt` 覆盖 mutation=0 可回、mutation>0 不可回
6. 生产路由文件没有改到 `AnkiReviewRoute` / `AnkiImportRoute` 默认

即使 1–6 全绿，也必须继续写：

```text
P4 PRODUCTION DEFAULT FLAGS: still false
P5-C FIXTURE PILOT: HOST CONDITIONAL GO   # 或 DEVICE CONDITIONAL GO（仅当 P5C-13 跑过）
P5 USER CUTOVER: NO-GO
P5-D PRODUCTION ROUTING: HOLD
P5 LEGACY DELETION: NO-GO
Device B: out of scope
```

缺任一条：保持 `P5-C FIXTURE PILOT: IN PROGRESS`，不要改 `17` 标题。

## 11. 明确不要做的改法

- 不要 `cutoverEnabled = true`「省事」解开 Cutover
- 不要在 worker 之外再加一把 migration 锁
- 不要把 mutation receipt / backup 放到 `CourseDatabase`
- 不要用 Turna SRS 次数对账官方 revlog
- 不要把 Host 测试通过写成 Device 通过
- 不要把 fixture 成功写成用户牌组可迁
- 不要在 README 写 PRODUCTION GO / P5-D GO / DELETE GO
- 不要为 P5-C 重开 PlatformView remount / timeout 话题（已在 `20` 收）

## 12. 建议一次提交的切片

```text
commit 1  P5C-00/01/02 开关、allowlist、migrating lease、fixture 包
commit 2  P5C-03/04/05 选包、文件备份、importFile
commit 3  P5C-06/07/08 map + projection + verify
commit 4  P5C-09/10/11 cutoverReady、只读、回滚
commit 5  P5C-12 测试与 artifacts/p5c（不改生产 flag）
commit 6  仅当 P5C-13 跑完：device-a-fixture-pilot.txt
```

每个 commit 后跑第 8 节 P5C-12 命令。设备 commit 必须带 apk sha。

## 13. P5-D / P5-E 仍 HOLD

未再接到「进入 P5-D」之前：

```text
不要改 AnkiReviewRoute / AnkiImportRoute
不要做 1% / 10% / 50% / 100% 灰度
不要删 Legacy 文件或表
不要补 OHOS official Core 当本轮范围
```

P5-D 的入口条件（只记录，本轮不施工）：P5-C Host GO、fixture 观察无 P0、`14` §10.1–10.3 能勾、产品书面接受 Android 先行且 OHOS 留 Legacy。
