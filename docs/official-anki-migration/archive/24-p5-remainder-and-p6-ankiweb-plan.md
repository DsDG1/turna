# P5 收口、生产切换与 P6 AnkiWeb 计划

> 文档代号：P5-REMAINDER / P6-PLAN  
> 日期：2026-08-19  
> 前置：[`14`](./14-phase-4-audit-remediation-and-phase-5-execution-plan.md) §8–11、[`15`](./15-p5-legacy-inventory.md)、[`16`](./16-p4r3-production-gate-and-p5b-prep-plan.md) / [`18`](./18-p4r3-audit.md) / [`19`](./19-p4r3-implementation-playbook.md)、[`21`](./21-p5c-fixture-pilot-implementation-playbook.md) / [`23`](./23-p5c-audit.md)、[`25`](./25-p5c-closeout-result-report.md)、`artifacts/p4r2/`、`artifacts/p5c/`  
> 范围：P5 还没做完的部分、P5-D 生产路由、P5-E 删除。Phase 6 AnkiWeb Sync **已取消**  
> 不是施工手册：本文件定阶段、门禁和禁止项。某一批开工前另写 HOWTO。  
> P5-C §4（P5C-14…20）已收口，结论以 [`25`](./25-p5c-closeout-result-report.md) 为准；`23` 只保留作废 GO 记录。

## 1. 结论先行

```text
P4 / P5-A / P5-B / P5-C: 已收口，不再重做
P5-D D1–D4: 已收口（路由、灰度 G1–G4、D4 第一隔离源）
P5-D D5 生产默认（2026-08-20 书面）: Android 新导入默认官方；catalog hash 能对上的旧源认领为 official；OHOS/iOS/Windows 仍 Legacy
P5-E 删 Legacy: HOLD（至少跨一个正式 release 观察）
P6 AnkiWeb Sync: 已取消（2026-08-20 书面：不考虑与 AnkiWeb / 官方 Anki 同步）
设备：只认 Device A（3B15AG00FPB00000）。不设第二台，不把 Device B 当门禁
OHOS official Core: 不在本计划施工范围
```

P5 不是一块。已经做完的是「内部 allowlist fixture 能迁到 observing 并观察官方 Collection」。还没做的是「用户牌组、生产入口、删 Legacy」。P6 已取消，不能当后续票。

产品已进入 P5-D（方案 B）。本批只允许 Sprint D1（P5D-01…04），施工见 [`26`](./26-p5d-production-routing-playbook.md)。禁止把 `TURNA_OFFICIAL_ANKI_*` 默认改 true，禁止 `cutoverEnabled` 默认 true，禁止 P5D-05 灰度 / P5-E。P6 已取消。§4 已收口，见 `25`。

## 2. 现在到底到哪了

收口结论以 `25` 为准往前加算。`23` 只保留作废 GO 记录，不能用 `22` 的作废 GO。

| 块 | 事实 | 还缺什么 |
|---|---|---|
| P5-A | `15` 盘点 30 文件 / 14,995 行；census；`AnkiEngineKind`；capability matrix | 生产路径仍不读 resolver |
| P5-B | catalog **v8** 有 `legacy_anki_migrations` / card map / `recorded_kind`；dry-run matcher；预览页 Cutover 永远 disabled | 生产 `AnkiReviewRoute` 仍不读 `recordedKind`（留给 P5-D） |
| P5-C Host | P5C-14…19 已落地；`createPhysicalBackup` fail-closed；Host 真 `.apkg` 路径有测试；`cutoverEnabled == false` | 见 `25`；不再把 FakeImporter 当缺口 |
| P5-C Device A | P5C-20 已重验；§5.4 回滚两条路径已落盘：`mig-p5c-fixture-device`=`noLegacyScheduleRollback`/`official`，`mig-p5c-fixture-rb0`=`rollbackEligible`/`legacy`；用户 181 张未迁 | `basic-cloze.apkg` 仍是 anki21b stub |
| 生产入口 | `AnkiImportRoute` / `AnkiReviewRoute` 默认 Legacy | P5-D |
| 用户牌组 | 不在 allowlist | 未授权不得加入 |

`artifacts/p5c/device-a-fixture-pilot.txt` 是当前设备事实源。换 APK 必须重跑 hash，禁止抄 `a8161e88` / `bd0e2442` / `81c9622e` / `a6eed1ea` 当「永远有效」。

## 3. 阶段怎么切

```text
P5-C'   收口 isolated fixture（§4）     已完成；见 25。不再当待办
P5-C+   第二个隔离 fixture / 多卡      可选；用户牌组仍禁止
P5-D    生产路由 + 灰度 + 回滚演练      HOLD；产品书面进入
P5-E    断引用 → 删写路径 → 删实现 → tombstone
                                      HOLD；至少一个正式 release 之后
P6      AnkiWeb Collection / Media     已取消；不排期、不写 sync 包
```

编号沿用 `14` §8。不要发明 P5-F。原「第七阶段 = Phase 6」已取消，见 `00` 阶段 6。

平台策略必须先定，再谈删代码（`14` §9）：

```text
方案 A  全平台迁移：先补 OHOS official Core，再删共享 Legacy
方案 B  Android 先行：Android 走 official，OHOS 继续 Legacy 共享实现
```

未书面选定前，允许 Android 停 Legacy **写入**，不允许删除仍被 OHOS 引用的文件。

## 4. P5-C 收口（已完成，见 25）

P5C-14…20 已落地（代码 + Host 测试 + Device A P5C-20）。本节保留原规格便于复算，**不再当待办**。状态与证据以 [`25`](./25-p5c-closeout-result-report.md) 和 `artifacts/p5c/` 为准。**不**把任何用户既有牌组放进 allowlist。

### P5C-14 可复现 fixture

- 仓库只把 `test/application/anki_official/fixtures/p5c/classic-basic.apkg`（经典 `collection.anki2`）当设备默认包。
- `basic-cloze.apkg` 若仍是 anki21b stub，文档标明「Legacy≠Official」，或换成两边都能解析的 cloze/reverse（≤20 张）。
- allowlist 只认 `p5c-fixture-` importId 或 `fixture-allowlist.txt` 的 sha256。去掉「显示名包含 p5c-fixture」。

### P5C-15 可恢复备份

`createPhysicalBackup` 缺文件时不得写空串当成功。`backingUp` 完成前这些必须 `existsSync` 且非空：

```text
legacy-manifest.json
legacy-subset.sqlite          该 importId 的 id/guid/ord/wordId/counts，无字段正文
collection.anki2              官方 Collection 副本
official_catalog.sqlite
SHA256SUMS
```

测试：`backup_files_exist_and_contain_no_card_html`。

### P5C-16 catalog `recordedKind`

给 **已经 cutover 的那一个** source 写 `recordedKind=official`。这是 catalog 行，不是全局 flag。`cutoverEnabled` 仍 false。生产 `AnkiReviewRoute` 本批仍不读它。

没有这一列，P5-D 的 resolver 没有东西可读。

### P5C-17 WriteGuard 接到真实写路径

| 路径 | owner | observing 后的 fixture source |
|---|---|---|
| `AnkiDeckManager.recordCardReviewed` / Turna SRS | `turnaSrs` | deny |
| Legacy `anki_note_dao` 评分相关 update | `legacyAnkiDao` | deny |
| `OfficialReviewSession.answer/undo/bury` | `officialScheduler` | allow |
| 课程 preview / derived exercise | `projection` | 评分类 deny |

测试名按 `14` §11：`legacy_source_never_has_two_writable_engines`、`cutover_fixture_source_denies_turna_srs_answer`（必须打 **answer**，不能只打 `migrate()`）。

### P5C-18 回滚读列，不读调用方口头 delta

`official_mutation_count_at_cutover` 以 catalog 列为准。mutation=0 → `rollbackEligible`；mutation>0 → `noLegacyScheduleRollback`。禁止把旧 Legacy scheduling 重新设为事实源。

### P5C-19 Host 真导入（可选但建议）

现在 Host crash-resume 用 `_FakeImporter`。至少加一条不走 Fake 的测试：对 `classic-basic.apkg` 调真实 `importFile`（Linux FFI 若不可用则标 `HOST FFI NOT AVAILABLE`，不要用 Fake 冒充）。

### P5C-20 设备复算清单

换 APK 后当场勾，勾不齐就保持 `P5-C FIXTURE PILOT: IN PROGRESS`：

```text
apk sha == device apk == 本批 artifact 所写
native hash 闭环（built / jniLibs / apkSo / deviceSo）
fixture seed importId=p5c-fixture-* cards 与官方 source 1:1 或官方≥Legacy 且 matched==legacy
Fixture pilot → observing
投影 itemCount == matched
正式复习只评 allowedCardIds；用户 181 张不动
cutoverEnabled 仍 false；用户既有牌组无 Pilot
不 wipe collection.anki2
```

设备只跑 Device A。不写 Device B PASS，也不因为没有第二台而卡 GO。

**P5-C HOST CONDITIONAL GO**（只对 fixture）：已满足；见 `25`。  
**P5-C DEVICE CONDITIONAL GO**：已满足（P5C-20）；见 `25`。  
两条都绿也必须继续写：`P5 USER CUTOVER: NO-GO`。

## 5. P5-D 生产入口切换（Sprint D1 已收口）

产品已书面进入。施工手册：[`26`](./26-p5d-production-routing-playbook.md)。P5D-05 已由 D3 灰度收口；P5-E 仍 HOLD；P6 已取消。

### 5.1 入口条件

1. P5-C HOST + DEVICE CONDITIONAL GO（§4）能复算  
2. `14` §10.1–10.3 能勾，或对每一条写明「本批为何可缺」  
3. 产品书面接受方案 B（Android 先行，OHOS 留 Legacy），或方案 A 的 OHOS 工期  
4. rollback runbook 已写（§5.4）；演练只在 Device A 上做

### 5.2 做什么

| ID | 改哪里 | 过线 |
|---|---|---|
| P5D-01 | `AnkiSourceRouteResolver` 在 `cutoverEnabled==true` **且** 该 source `recordedKind==official` 时走 official | 默认构建仍 Legacy |
| P5D-02 | `AnkiReviewRoute` / `AnkiReviewSessionRoute`：official source → 现有 `OfficialAnkiReviewPage`（统一 Formal Reviewer，不要再套一层 Preview） | 首页 due 不改成「全部官方队列」 |
| P5D-03 | `AnkiImportRoute`：Android + official 全 flag 时新导入走 official Import Saga；否则 fail-closed，禁止静默半套 | OHOS 继续 Legacy |
| P5D-04 | 首页 due 按 engine **聚合计数**；评分仍回各自 owner | 双写 = fail |
| P5D-05 | 灰度 dart-define / remote flag：internal → 1% → 10% → 50% → 100% | 每一级单独 artifact |
| P5D-06 | 用户牌组进入 allowlist 必须 **逐个** hash，禁止「census.first」 | 用户既有牌组默认不进 |

`cutoverEnabled` 从 false 改为可读配置的那一次，必须单独 commit，commit message 写清范围。不要和删文件、AnkiWeb、改默认 `TURNA_OFFICIAL_ANKI_*` 捆在一起。

### 5.3 观察指标（每一级）

```text
crash / fatalError
unknown mutation / 二次评分
RENDER_TIMEOUT / RENDER_SUPERSEDED / stall
mapping unmatched / collision
revlog 增量 vs 有效评分
rollback 次数与原因
用户 collection 是否仍在
```

同一版本里禁止「切 100% 并删 Legacy」。

### 5.4 回滚

| 时机 | 动作 |
|---|---|
| 该 source 尚未 cutover | `rolledBackLegacy`；官方 source 可从 backup 恢复 catalog 行 |
| cutover 后 mutation=0 | `recordedKind` 改回 legacy；官方 Collection 保留但不作为该 source 事实源 |
| mutation>0 | 拒绝恢复 Legacy scheduling；只允许观察 / 导出 |

演练：只在 Device A 上做。同一 fixture source 各走一遍「mutation=0 可回」和「mutation>0 不可把 Legacy scheduling 设回事实源」。覆盖 `14` §10.3 的「两台设备」条：本仓不设第二台，不因此判 rollback drill NO-GO。禁止 wipe 用户 Collection。

## 6. P5-E Legacy 删除（HOLD）

只有 `14` §10.4 全绿才能开工。波次不可合并成一个「大扫除 PR」。

| Wave | 做什么 | 不做什么 |
|---|---|---|
| E1 断生产引用 | 正常路由不再 `new AnkiImporter` / `AnkiReviewAssembler`；CI forbidden import | 不删文件、不删表 |
| E2 删自研 Scheduler 写 | 删 Anki→`SrsProvider` 评分 / `anki_srs_migrator` | Turna **非 Anki** 课程 SRS 保留 |
| E3 删自研 render/import | 删 template renderer、HTML fallback、自研 package decode | 保留仍被投影 / media 使用的适配器 |
| E4 schema tombstone | 先停写一个 release，再单独 schema PR 删表 | 禁止当 cleanup 混进功能 PR |

每一波：`rg` 证明生产引用为 0 → 再删 → 更新 `15` 盘点。OHOS 若仍走 Legacy，E2–E4 在共享文件上 **停**。

## 7. P6 已取消（不与 AnkiWeb / 官方 Anki 同步）

2026-08-20 产品书面：「删掉 P6，不考虑同步 Anki 本身」。

- 不另开设计文档，不写 sync 包，不接 AnkiWeb / 官方 Anki 账号。
- 生产路由、复习、预览、灰度配置不得出现 AnkiWeb 入口；`ankiweb_not_linked_from_production_routes` 永久保持绿。
- 不把 Device A 用户 Collection 同步到任何 Anki 云。
- P6-00…06 票作废，不再是入口或后续待办。

## 8. 设备与产物

| 项 | 规则 |
|---|---|
| 唯一设备 Device A `3B15AG00FPB00000` | 继续用；禁止 wipe `files/official_anki/default/collection.anki2` |
| 第二台 / Device B | **不考虑**。不进门禁、不进工期、不写 PASS/FAIL |
| 用户牌组 | 默认不在 allowlist；要迁必须新产品指令 + 新 hash |
| APK | Android 生产默认 official 复刻（CUTOVER+g4+能力 flag）；可用 `--dart-define=…=false` 关回 |
| Artifact | P5-C 继续写 `artifacts/p5c/`；P5-D 起新目录 `artifacts/p5d/`；不建 `artifacts/p6/` |
| 收据 | 禁止卡片正文、字段、媒体文件名里的用户内容 |

## 9. 工期（1 人，不含商店观察）

| 周期 | 内容 | 预计 |
|---|---|---:|
| 已完成 | P5C-14…20 收口（见 `25`） | — |
| 已完成 | Device A 回滚演练 mutation=0 / >0（§5.4，见 `artifacts/p5c/rollback-drill.txt`） | — |
| HOLD 后 Sprint D1 | P5D-01…04 路由 + recordedKind 读取 | 5–8 天 |
| Sprint D2 | 灰度、观察指标、Device A 上回滚两次（0 / >0 mutation） | 5–8 天 + 日历观察 |
| 下一版本 | P5-E Wave 1 | 3–5 天 |
| 再下一版本 | E2–E4 | 5–10 天 + 一版观察 |
| 已取消 | P6 | 不排期；不写 sync 代码 |

编码可以压缩。OHOS 决策和 release 观察是日历约束。不因为没有第二台设备停工。

## 10. 测试名（本计划新增或补齐）

已有的不要复制第二套。缺了再补：

```text
backup_files_exist_and_contain_no_card_html
recordedKind_stays_per_source_and_cutoverEnabled_false
legacy_source_never_has_two_writable_engines
cutover_fixture_source_denies_turna_srs_answer
rollback_reads_official_mutation_count_column
allowedCardIds_skips_foreign_deck_mates
preview_cutover_button_stays_disabled          # 必须读 preview_page.dart 源码
p5d_default_build_still_routes_legacy          # 仅 P5-D 开工后
ankiweb_not_linked_from_production_routes      # 永久：生产不得接 AnkiWeb
```

## 11. 明确不要做的改法

- 不要把 fixture observing 写成「用户数据可以迁」
- 不要 `cutoverEnabled = true` 图省事解开 Cutover 按钮
- 不要改 `AnkiReviewRoute` / `AnkiImportRoute` 默认，除非已进入 P5-D
- 不要把 `TURNA_OFFICIAL_ANKI_*` 默认改 true
- 不要 wipe Device A 用户 Collection
- 不要把 Device A 用户 100 张 P4 会话当成 P5 证据
- 不要把「没有第二台设备」写成 NO-GO 或 HOLD 理由
- 不要在 worker 之外再加一把 migration 锁
- 不要把 Turna SRS 次数翻译成官方 revlog
- 不要为 OHOS 先做 official Core
- 不要接 AnkiWeb / 官方 Anki 同步，也不要把凭证写进 `CourseDatabase` 或 census
- 不要在 README 写 PRODUCTION GO / P5-D GO / DELETE GO / P6 GO

## 12. 文档怎么改

| 时机 | 改哪个 |
|---|---|
| 本计划落地 | 本文 + README 索引 |
| P5-C 收口做完 | 已写 [`25`](./25-p5c-closeout-result-report.md)；本文 §1/§2/§4/§9/§13 回写为已收口。不要覆写 `23` |
| 进入 P5-D | 单独 HOWTO，对标本文 §5 |
| 进入 P5-E | 单独删除 PR 说明 + 更新 `15` |
| 有人提 AnkiWeb / 官方同步 | 拒绝。P6 已取消，见 §7 |

架构变化先改 `00`。已执行任务必须带 commit、命令、apk sha、指标。未跑的命令标「未跑」。

## 13. 下一步（人，不是机器自动开工）

```text
P5-C §4 已收口，见 25。Device A §5.4 已演练
P5-D D1 已收口，见 27 / artifacts/p5d/host-d1-closeout.txt；D2+D3-PREP 已收口见 artifacts/p5d/host-d2.txt + host-d3-prep.txt；D3 G1-G4 + D4 本批 CONSTRUCTION GO 见 28 §7 + artifacts/p5d/written-go-d3d4.txt（逐源书面 hash）
后续大施工见 28。D5 生产默认已翻转。P5-E 仍要另 go。P6 已取消，不另 go
若有人提 AnkiWeb / 官方 Anki 同步：拒绝，不写 sync 代码
```
