# P5-C 验货报告

> 文档代号：P5C-AUDIT  
> 日期：2026-08-18  
> 对照：[`14`](./14-phase-4-audit-remediation-and-phase-5-execution-plan.md) §8、[`21`](./21-p5c-fixture-pilot-implementation-playbook.md)、[`22`](./22-p5c-result-report.md)、源码、`artifacts/p5c/`、`artifacts/p4r2/`  
> 口径与 [`18`](./18-p4r3-audit.md) 相同：GO 必须能当场复算；复算失败则 GO 作废。

## 1. 结论先行

```text
21 作为施工规格：可用，有几处要收紧
22 作为验收：过早。撤销 Device A GO，Host 降为 SKELETON / IN PROGRESS
P5-C FIXTURE PILOT: NO-GO（22 的 CONDITIONAL GO 作废）
P5 USER CUTOVER / P5-D / P5-E: 仍 NO-GO / HOLD
P4 PRODUCTION DEFAULT FLAGS: still false（属实）
cutoverEnabled: false（属实）
生产路由未改（属实）
```

`22` 和 README 把「Saga 骨架 + 用户牌组上评了 1 张官方卡」写成了 Fixture Pilot 闭环。这与 `17` 被 `18` 撤回是同一类问题。

## 2. `21` 规格对照 `14` §8

| `14` §8 步骤 | `21` | 现码 | 验货 |
|---|---|---|---|
| 1 migration lease | P5C-02 | 有 `migrating`；`start()` acquire，无 `try/finally` | 规格够；实现不完整 |
| 2 source 未在 review + census | 未单列 | 无「正在复习则拒绝」检查 | **规格缺口** |
| 3 重选原包 + hash | P5C-03 | `pickAndValidatePackage` 有 | Host 有；设备 UI 没接线 |
| 4 备份 Legacy 子集 + official Collection | P5C-04 | `createPhysicalBackup` 有文件名；缺文件就写空串 | **收据级副本，不是可恢复备份** |
| 5 官方 Import Saga | P5C-05 | 调 `importer.importFile`；测试用 `_FakeImporter` | 未证明真 worker 导入 |
| 6–8 身份 / dry-run / 100% 匹配 | P5C-06 | 复用 DryRunSaga；`sameTrustedPackage` 未传 | 部分 |
| 9 重建 projection | P5C-07 | `projectionAction` 回调；测试传空闭包 | **未接到 generate/publish job** |
| 10 计数 / renderer fixture | P5C-08 | 只比较两个传入整数 | **未对账 deck/note/media/课程位置** |
| 11 `cutoverReady` | P5C-09 | 状态能走到 | 仅内存 catalog |
| 12 原子更新 source route | `21` 明确留给 P5-D | `anki_sources` **无** `recordedKind` 列；`onCutover` 可空且默认不写 | `22` 写「写入 recordedKind」**作废** |
| 13 Legacy source 只读 | P5C-10 | 只拦 `AnkiSrsMigrator.migrate()` | 评分 / DAO / Session **未接** |
| 14 observing，不删数据 | P5C-09/13 | 状态枚举有；设备没跑完 Saga | 设备未进入 observing |

`21` 对生产约束写对了：`cutoverEnabled` 保持 false、不改 `AnkiReviewRoute`、allowlist、不碰用户牌组。这些应继续当施工红线。

`21` 自身应改的规格问题（未改代码也能先记）：

1. §2 记账 APK `a8161e88…` 已过期。磁盘 / 设备 / `native-hash-manifest.txt` 现为 `d3bf329e…`。`21` 自己写「换 APK 必须重跑 hash」。
2. allowlist 第 3 条「显示名包含 `p5c-fixture`」过宽，用户改名即可绕过。应收成 **hash 或 `p5c-fixture-` importId**。
3. `start()` 必须能从中途 state 恢复；现在一律 `detected → awaitingPackage`，重跑会 CAS 失败。
4. 类名写成 `LegacyAnkiFixturePilotSaga`，代码是 `OfficialAnkiFixturePilotSaga`。
5. P5C-10 写成「现在只有单测」不准确：`migrate()` 已接 guard，但 **answer 路径没接**。

## 3. `22` 逐项复算

| `22` 主张 | 复算 | 裁决 |
|---|---|---|
| P5C-00 开关默认 false | `OfficialAnkiFeatureFlags().migrationPilot == false`；`cutoverEnabled == false` | **PASS** |
| P5C-01 fixture + sha | 文件在；测试只读 `.sha256` 文本，**没有对 `.apkg` 做 sha256sum** | CODE PARTIAL |
| P5C-02 lease 互斥 | `migration_lease_blocks_review_and_import` 存在且逻辑对 | **PASS**（单测） |
| P5C-03 hash 失败停 | `fixture_pilot_requires_reselected_package_hash` | **PASS**（Host） |
| P5C-04 物理备份 | 文件名齐；collection/catalog 不存在时写成 **空文件**；未从 CourseDatabase 导出真实 subset | CODE PARTIAL；不可当恢复证据 |
| P5C-05 复用 importFile | 生产路径签名对；`legacy_migration_crash_resumes_every_checkpoint` 用 `_FakeImporter` | DEVICE/REAL IMPORT **NOT PROVEN** |
| P5C-06 100% 匹配 | 合成 guid 身份；未跑真实官方卡描述符 | CODE PARTIAL |
| P5C-07 投影 | `projectionAction: () async {}` | **REVOKE** |
| P5C-08 verifying | 只比调用方传入的两个 count | **REVOKE** |
| P5C-09 recordedKind + mutation count | `OfficialAnkiMigrationDao.transition` **没有** mutation 字段；`anki_sources` **没有** recordedKind | **REVOKE** |
| P5C-10 WriteGuard | 测试名 `..._denies_turna_srs_answer`，实际调用 `migrate()`；`OfficialReviewSession` / `anki_note_dao` 无 guard | **REVOKE** as answer-path |
| P5C-11 回滚 | 状态机能走到 `rollbackEligible` / `noLegacyScheduleRollback`；**不读** `official_mutation_count_at_cutover` 列，只看调用方传入的 delta | CODE PARTIAL |
| P5C-12 216 测试 / 点名测试全绿 | `legacy_source_never_has_two_writable_engines` **无此测试名**（另有空格名 resolver 单测）；`preview_cutover_button_stays_disabled` 断言的是 **测试文件里的字符串字面量**，不是读 `official_anki_migration_preview_page.dart` | 过早闭环 |
| P5C-13 Device A Pilot PASS | 截图是 **马原帽子题 87**（用户牌组），不是 fixture 导入。内部页 **没传** `flags` / `onFixturePilot`，Pilot 按钮在设备上不可能出现 | **REVOKE** |

## 4. 设备证据为什么不算 P5-C

`artifacts/p5c/device-a-fixture-pilot.txt` 写：预览 unmatched=10、正式复习 rated=1 Good。

对照 `21` P5C-13 必做而没做：

```text
导入 fixtures/p5c 小牌组到 Legacy     未做
重选同一 .apkg → Fixture pilot       未做（UI 没接线）
考研政治默写 Pilot disabled           无法区分：flags 默认 false，所有来源都没有 Pilot 按钮
内部正式复习评 1 张                    做了，但是用户牌组
revlog 增量只来自 fixture official    未做
```

截图 `device-a-pilot-review.png` 与 P4 会话同一牌组（马原帽子题）。这是 P4 正式复习仍可用，**不是** fixture cutover 观察。

内部页现在这样推预览（未传 flag / 回调）：

```dart
OfficialAnkiMigrationPreviewPage(
  census: preview.census,
  dryRun: preview.dryRun,
  diskFreeBytes: preview.diskFreeBytes,
  displayName: preview.displayName,
);
```

`flags` 走默认 `OfficialAnkiFeatureFlags()` → `migrationPilot=false`。即使 APK 带了 `TURNA_OFFICIAL_ANKI_MIGRATION_PILOT=true`，这一页也看不到 Fixture pilot。

## 5. Artifact 互相打架

| 文件 | apk sha | P5-C 结论 |
|---|---|---|
| `p4r2/device-a-release-100.txt` | `a8161e88…` | P5-C HOLD |
| `p4r2/final-decision.txt` | `a8161e88…` | P5-C HOLD |
| `p5c/baseline.txt` | `a8161e88…` | HOST CONDITIONAL GO |
| `p4r2/native-hash-manifest.txt` | `d3bf329e…` | （无 P5 句） |
| `p5c/device-a-fixture-pilot.txt` | `d3bf329e…` | CONDITIONAL GO |
| `22` | `d3bf329e…` | Host + Device A CONDITIONAL GO |

`21` §2 / §10 要求「100 张 artifact 的 sha = 当前已装 APK」。当前已装 / 磁盘 release 是 `d3bf329e…`，与 100 张证据不是同一份 APK。Hash 链本身对 **新** APK 是闭环的，但不能把旧 100 张成绩自动记到新包上，更不能用新包上的 1 张用户卡评分代替 fixture Saga。

`host-pilot.txt` 逐步抄了 `21` 的 11 个 checkpoint，与测试真实行为不符（Fake importer、空投影、未写 recordedKind）。按 `21` §10 第 4 条，这份收据 **不能** 支撑 GO。

## 6. 仍然属实、不要推倒重来

- `cutoverEnabled == false`；Cutover 按钮源码仍 disabled
- 未改 `AnkiReviewRoute` / `AnkiImportRoute`
- 默认 `TURNA_OFFICIAL_ANKI_*` 仍 false
- 未删 Legacy
- `migrating` lease 单测成立
- allowlist 拒绝 `user-deck` / 考研政治 importId
- hash 不匹配会到 `needsUserAction`
- Dry-run matcher / census / DAO CAS 仍是 P5-B 那套，应继续复用
- Device B 仍应写 out of scope

## 7. 验货后的状态（以本文为准）

```text
P5-C FIXTURE PILOT: NO-GO
  Host: SKELETON IN PROGRESS（Saga 方法在，未接到真实 import/projection/route/answer）
  Device A: NOT PROVEN（未跑 fixture 导入 + Pilot；评的是用户牌组）
P5 USER CUTOVER: NO-GO
P5-D PRODUCTION ROUTING: HOLD
P5 LEGACY DELETION: NO-GO
P4 PRODUCTION DEFAULT FLAGS: still false
```

`22` 标题里的 CONDITIONAL GO **作废**，直到下面能当场复算：

1. 内部页传入 `OfficialAnkiFeatureFlags.current` + 真正的 `onFixturePilot`
2. Host 用 **非 Fake** importer（或可证明的 Fake worker 契约）+ **非空** projection job 跑完 `detected → observing`
3. `transition` 或单独 API **真写** `official_mutation_count_at_cutover`；catalog 有可复算的 per-source route 字段（或诚实写「本轮不写 route，只写 migration state」）
4. `AnkiWriteGuard` 接到评分/undo，而不只是 `migrate()`
5. `preview_cutover_button_stays_disabled` 读 **源文件**
6. P5C-01 对 `.apkg` 字节做 sha256
7. Device：另导 fixture 小牌组，重选包，跑通 Pilot；用户 `考研政治默写` 无 Pilot；revlog 增量可归因到 fixture official source
8. 所有 p5c / p4r2 artifact 的 apk sha 与当次已装包一致，禁止混用 `a8161e88` 与 `d3bf329e`

## 8. 下一步施工（回到 `21`，不要另起炉灶）

优先补 `21` 已写但未落地或被 `22` 写过头的项：

```text
1. 内部页接线 flags + onFixturePilot + coordinator（否则设备永远跑不了 Pilot）
2. start() 按现态恢复；lease 用 try/finally
3. 真备份：禁止空 collection/catalog；subset 从 CourseDatabase 按 importId 导出
4. verify 对账 notes/cards/decks/media/projection items
5. 写 mutation count；决定本轮是否写 per-source route（不写就改 21/22 句子，不要假装写了）
6. WriteGuard 接到 Legacy 评分
7. 修名不副实的测试后再重写 artifacts/p5c
8. 重跑 Device A P5C-13；马原帽子题截图不得再当 Pilot 收据
```

未完成以上之前，禁止把 README / `final-decision` 写成 P5-C GO。
