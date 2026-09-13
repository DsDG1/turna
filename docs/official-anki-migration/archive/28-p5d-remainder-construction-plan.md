# P5-D 后续大施工计划

> 文档代号：P5D-NEXT  
> 日期：2026-08-19  
> 前置：[`24`](./archive/24-p5-remainder-and-p6-ankiweb-plan.md)、[`26`](./archive/26-p5d-production-routing-playbook.md)、[`27`](./archive/27-p5d-d1-audit.md)  
> 产品：「适合 go 的全部 go」，再把本文改成可大施工的规格。  
> 本文是 **D2 施工手册 + 后续波次锁**。D2 已 CONSTRUCTION GO。后面每一波仍要单独书面 go。
>
> **历史规格；勿按本文开施工波次。** 灰度 `TURNA_OFFICIAL_ANKI_GRAY_COHORT` / D5「OHOS 继续 Legacy」已作废。现行入口：[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)；OHOS EOL：[ADR 0041](../decisions/0041-ohos-product-eol.md)。

## 1. GO 板（当场有效）

```text
已收口且保持
  P5-C HOST+DEVICE CONDITIONAL GO（仅 fixture）
  P5-D D1 HOST+DEVICE CONDITIONAL GO（仅 fixture Official Rating）
  P5-D D2 已补齐（host-d2 + host-d3-prep）

本次书面 GO（2026-08-19）
  D2 CONSTRUCTION GO     P5D-11…13，可选 14；不改流量
  D3-PREP GO             灰度管道默认关；不打开 1%/10%/50%/100%
  D3 G1–G4 CONSTRUCTION GO   仅 Android 新导入 + 已 official 的 allowlist 源；每级单独 artifact，可一键回 G0
  D4 按源 allowlist CONSTRUCTION GO  一个 hash = 一次书面确认；禁止 census.first / 批量迁；按源产出 backup→dry-run→recordedKind→评1张→rollback 双路径

明确 NO-GO / HOLD
  D5 生产默认 已书面翻转（2026-08-20）：Android 新导入 + 能对上 catalog hash 的旧源默认官方；OHOS 仍 Legacy
  P5-E 删 Legacy         HOLD（14 §10.4 + 一版正式 release）
  P6 AnkiWeb             已取消（不考虑与 AnkiWeb / 官方 Anki 同步）

方案 B、Device A only、默认 flag 全 false：不变
用户既有牌组默认不进 allowlist：不变（D4 仅对书面 hash 的逐源例外）
```

判定规则：不改生产默认、不碰批量用户既有牌组、不删 Legacy、不写 AnkiWeb 的内部补齐 / 默认关闭的管道 / 逐源书面 allowlist → 可以 GO。一改 `fromEnvironment` 默认、批量切用户源 → 必须另 go。D3/D4 本批 GO 不等于 P5-D GO。

## 2. 现在到哪了

| 块 | 事实 | 本计划 |
|---|---|---|
| P5-A / B / C | 已收口 | 不再重做 |
| D1 P5D-01…04 | 路由骨架 + fixture 评分已收口 | 不再重做 |
| D2 P5D-11…13 | 已补齐（host-d2 + host-d3-prep；cutover 仍 false） | 不再重做 |
| 灰度百分比 | D3-PREP 默关；G1–G4 Host+Device 已收口（gray-g1..g4 + device-gray-g1..g4） | **D3 灰度序列完成；G4≠P5-D GO** |
| 用户源 | fixture + 第一隔离 hash `d7cdafb7…` 已书面放行并在 Device A 跑完 backup→评1→rollback 双路径（allowlist-d7cdafb7） | **D4 第一源已收口；其它用户 hash 仍逐源书面** |
| 生产默认 | Android：CUTOVER 默认 true，GRAY 默认 g4，能力 flag 默认开 | **D5 已翻转** |

## 3. 总顺序

```text
D2        补齐（已收口 host-d2）
D3-PREP   灰度配置默认关（已收口 host-d3-prep，禁止打开 cohort）
D3 G1–G4  本批 CONSTRUCTION GO（G0=内部 CUTOVER 现状；每级单独 gray-gN.txt，可回退 G0；跳级作废）
D4        本批 CONSTRUCTION GO（逐源书面 hash；每源单独 allowlist-<hash>.txt + host-d4.txt）
D5        另 go，单独 commit
E         HOLD
P6        已取消
```

同一版本禁止「切 100% 并删 Legacy」。D3 G4 若发生，只表示 Android **新导入**走 official，不是 P5-D GO。

## 4. 硬约束

```text
不把 TURNA_OFFICIAL_ANKI_* 默认改 true
不写 cutoverEnabled 默认 true
不解预览 Cutover 按钮
不把首页 due 改成「全部官方队列」
不把用户既有牌组批量进 allowlist
不 wipe collection.anki2
不删 lib/application/anki 或 lib/views/anki
不写 AnkiWeb 生产入口
计划与验货不写具体用户牌组名
收据禁止卡片正文 / 字段 / 用户媒体文件名
```

内部 APK 继续 dart-define。CUTOVER 不是预览按钮。

---

## 5. Sprint D2 — 补齐（CONSTRUCTION GO）

默认构建仍全 Legacy。只修计数、测试和已有回退的收口。

### P5D-11 官方 due 可复算

**现状**：`OfficialAnkiHomeDueSync.refresh()` 已被 Play Hub / Profile / Anki hub 调用。`refreshHomeDue` 把 `newCount+reviewCount` 写入静态 `officialDue`。Device 上 CUTOVER 包曾显示 Official due 0，而当时 fixture 复习卡可打开并评分。`_refreshOnce` 用空 `catch` 吞掉 `collectionLocked` / 打开失败，失败后数字会停在 0。

**改哪里**

| 文件 | 怎么改 |
|---|---|
| `lib/application/anki_official/engine/official_anki_home_due_sync.dart` | 失败不要静默清成「成功的 0」。`collectionLocked` 按现有 gate 重试；最终失败保留上次成功值或显式 `officialDueUnavailable`，禁止把异常当成 0 due |
| `lib/application/anki_official/migration/official_anki_production_router.dart` | `refreshHomeDue` 计数与 `getReviewQueue` 同口径：new + learning + review。只计 official-routed deck，去重 `deckId` |
| `lib/views/play/play_hub_screen.dart` | 继续显示聚合；不要改成「全部官方队列」入口 |
| 测试 | 见 §9 |

**过线**

```text
Host：due>0 的 official deck → officialDue>0
Host：只有未来复习卡 → officialDue==0
Host：refresh 抛 collectionLocked 且重试失败 → 不把成功 0 当结果
Device（可选，CUTOVER 包）：fixture 当日可评时 Play Hub Official due≥1
不双写 Turna SRS
```

Device 不要用「再评一张已到期卡」来假绿。若当前 fixture 已排到未来：另 seed `p5c-fixture-*`，或只对原 fixture 走 Again 后对账。禁止 wipe，禁止点非 fixture section。

### P5D-12 widget：生产入口真打开 Official 页

**现状**：`AnkiReviewPage._startReviewAsync` → `AnkiOfficialReviewGate.openInsteadOfLegacy`。gate 返回 true 则不进 `AnkiReviewSessionRoute`。没有测试证明 push 了 `OfficialAnkiReviewPage`。

**改哪里**

| 文件 | 怎么改 |
|---|---|
| `lib/views/anki/anki_official_review_gate.dart` | 可测：抽 `catalog/router/navigator` 或给 gate 加可选 override（与 resolver 测试同一风格） |
| `test/application/anki_official/official_anki_p5d_routing_test.dart` 或新 widget 测 | cutover+official+target → 出现 `OfficialAnkiReviewPage`；缺 target → SnackBar fail-closed，**不**出现 Legacy Session |
| `lib/views/anki/anki_review_session_page.dart` | 保持同一 gate，不要第二条实现 |

**过线**：§9 两条 widget / gate 测绿。不要为了测去解预览 Cutover。

### P5D-13 native 非队首回退入库

**现状**：`answer_card` 在 `from_queue=true` 未落盘失败后改 `from_queue=false` 并 `clear_study_queues()`。`answer_non_head_card_retries_off_queue` 已绿。这是 D1 设备评分能过的原因。

**本票只收口**：确认 `ops.rs` + `clear_study_queues` 公开性仍在；`queue_good_undo_reopen_and_stale_token` 仍绿；D2 artifact 写上 so / 测试名。不要再改调度语义。

### P5D-14（可选）第二隔离 fixture

仅 `p5c-fixture-` / allowlist hash。≤20 张。用户既有牌组禁止。可不做，不挡 D2 收口。

### D2 过线

```text
flutter test --no-pub test/application/anki_official
点名：§9 D2 四条 + D1 十二条仍绿
cargo test --lib answer_non_head_card_retries_off_queue
cargo test --lib queue_good_undo_reopen_and_stale_token
默认构建 cutoverEnabled==false
不写 P5-D GO
artifacts/p5d/host-d2.txt
```

Device 复算另开，不绑 Host 必过。

---

## 6. Sprint D3-PREP — 灰度管道（已收口，默认关）

**已落地**：可读配置 / dart-define `TURNA_OFFICIAL_ANKI_GRAY_COHORT` **默认 off**，行为等于内部 CUTOVER 包（见 `artifacts/p5d/host-d3-prep.txt`）。

| ID | 做什么 | 过线 |
|---|---|---|
| P5D-21 | `grayCohort` 默认 `g4`（生产 Android 新导入 100% official） | `p5d_gray_default_cohort_is_g4` |
| P5D-22 | 配置源不进 `CourseDatabase` / census JSON | 源码检索 |
| P5D-23 | 预览 Cutover 仍 `onPressed: null` | `preview_cutover_button_stays_disabled` |

G0 = 内部 CUTOVER APK 现状。G1–G4 见 §7，本批已 CONSTRUCTION GO。

---

## 7. D3 G1–G4、D4 与 D5

### D4/D5 本批书面确认

### D3 G1–G4（本批 GO，逐级放量）

只扩 Android 新导入 + 已 `recordedKind=official` 的 allowlist source。每一级单独 `artifacts/p5d/gray-gN.txt`。跳级作废。可一键退回 G0（改回 `TURNA_OFFICIAL_ANKI_GRAY_COHORT=off`）。

### D4 按源 allowlist（本批 GO，逐源书面 hash）

```text
一个 source = 一个 hash = 一次书面确认
禁止 census.first
禁止「设备上所有 Anki section 一起迁」
禁止批量 allowlist 入口
```

顺序：显式指定 `importId` 的 census → backup → dry-run map → `recordedKind=official` → Official Review + `allowedCardIds` → 评 1 张对账 → 按 `24` §5.4 记 rollback。每源 `artifacts/p5d/allowlist-<hash>.txt` + 汇总 `host-d4.txt`。

仍保持 `P5 USER CUTOVER: NO-GO` / `P5-D GO: NO`，D4 不等于用户全量迁移。

### D5 生产 GO 清单（本批可施工，单独 commit）

2026-08-20 已翻转生产默认（见 `artifacts/p5d/host-d5.txt` + `written-go-d5-defaults.txt`）。

**清单**（已按书面 go 落地）：
- 默认行为：`cutoverEnabled` 默认 `true`，`gray` 默认 `g4`；Android 新导入 official；OHOS 仍 legacy
- due 与 owner 一致（`getReviewQueue` 口径 `new+learning+review` 去重 `deckId`）
- fail-closed（`AnkiImportFacade.decisionFor` 半套 flag → `capabilityMissing`，Review gate 无 target/canOpen→`SnackBar` 不进 Legacy）
- 未 allowlist 仍 Legacy；Device A `collection.anki2` 仍在；不接 AnkiWeb；未删 Legacy

### P5-E（HOLD）/ P6（已取消）

E1–E4 与 `14` §10.4、`24` §6 相同。P6 已取消：不另开设计、不写 sync 包、不接官方 Anki 账号。

---

## 8. 观察指标（D2 Device、以及将来的 D3/D4）

```text
crash / fatalError / collectionLocked / invalid_state / answer_failed
unknown mutation / 二次评分 / Turna SRS 双写
RENDER_TIMEOUT / RENDER_SUPERSEDED / stall
official due 与队列是否同向
revlog 增量 vs 有效评分
collection.anki2 是否仍在
```

## 9. 测试名

D1 已有的保持绿。D2 / D3-PREP 新增：

```text
p5d_official_due_nonzero_when_review_card_due
p5d_official_due_zero_when_only_future_review
p5d_due_refresh_does_not_treat_lock_as_zero
p5d_start_review_pushes_official_page_when_cutover_official
p5d_start_review_fail_closed_does_not_push_legacy_session
p5d_gray_default_cohort_is_g4
answer_non_head_card_retries_off_queue
preview_cutover_button_stays_disabled
ankiweb_not_linked_from_production_routes
```

## 10. 设备与产物

| 项 | 规则 |
|---|---|
| Device A | 继续用；禁止 wipe |
| 第二台 | 不考虑 |
| Artifact | D2 → `artifacts/p5d/host-d2.txt`；D3-PREP → `host-d3-prep.txt`；G1+ / D4 / D5 另开 |
| 验货 | D2 不覆写 `27` |

## 11. 工期（1 人）

| 波次 | 状态 | 预计 |
|---|---|---:|
| D2 | **已收口** | 3–5 天 |
| D3-PREP | **已收口**（默关） | 1–2 天 |
| D3 G1–G4 | **本批 CONSTRUCTION GO** | 每级 2–4 天 + 观察 |
| D4 | **第一隔离源 Device A PASS**（allowlist-d7cdafb7）；其它 hash 仍逐源 | 每源 1–2 天 |
| D5 | **生产默认已翻转**（host-d5） | — |
| E | HOLD | 见 `24` §6 |
| P6 | 已取消 | 见 `24` §7 |

## 12. 不要做的改法

- 不要从 D1/D2 PASS 写 P5-D GO
- 不要把 due 异常吞成 0
- 不要在 D3-PREP 打开百分比
- 不要 `census.first`
- 不要同一 PR 改默认 flag + 删 Legacy + AnkiWeb
- 不要为非 Android 先做 official Core

## 13. 文档

| 时机 | 改哪个 |
|---|---|
| 本次 GO + 本文改施工规格 | 本文、README、`24` §13、`artifacts/p5d/written-go-d2.txt`→`written-go-d3d4.txt` |
| D2 做完 | `host-d2.txt`；验货另开 |
| D3 做完 | `gray-gN.txt`（每级单独） |
| D4 做完 | `allowlist-<hash>.txt` + `host-d4.txt` |
| 进入 E | 另一次书面 go + 可另开 HOWTO |
| 有人提 AnkiWeb | 拒绝。P6 已取消 |

## 14. 下一步

```text
D2 + D3-PREP 已收口
D3 G1 Host + Device A 已收口（gray-g1.txt + device-gray-g1.txt）
D3 G2 Host + Device A 已收口（gray-g2.txt + device-gray-g2.txt）
D3 G3 Host + Device A 已收口（gray-g3.txt + device-gray-g3.txt）
D3 G4 Host + Device A 已收口（gray-g4.txt + device-gray-g4.txt）；G4≠P5-D GO
D4 本批 CONSTRUCTION GO：逐源书面 hash，显式 importId，禁止 census.first / 批量迁，每源 allowlist-<hash>.txt
D5 已翻转。不要开 E。P6 已取消。D3 G4≠P5-D GO
```
