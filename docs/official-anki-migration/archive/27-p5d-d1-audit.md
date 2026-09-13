# P5-D Sprint D1 验货报告

> 文档代号：P5D-D1-AUDIT  
> 日期：2026-08-19  
> 对照：[`24`](./24-p5-remainder-and-p6-ankiweb-plan.md) §5、[`26`](./26-p5d-production-routing-playbook.md)、源码、`artifacts/p5d/host-d1-closeout.txt`、`artifacts/p5d/device-a-official-rate.txt`  
> 口径与 [`23`](./23-p5c-audit.md) 相同：GO 必须能当场复算；复算失败则不作 GO。

## 1. 结论先行

```text
P5-D D1 HOST CONDITIONAL GO
P5-D D1 DEVICE CONDITIONAL GO（仅 fixture Official Rating）
P5 USER CUTOVER: NO-GO
P5-D GO / PRODUCTION GO: NO
P5-E: HOLD
P6: 已取消（本验货当时写 HOLD）
cutoverEnabled 默认 false（属实）
TURNA_OFFICIAL_ANKI_* 现有默认仍 false（属实）
预览 Cutover 按钮源码 disabled（属实）
用户既有牌组不在 allowlist（属实）
```

本轮收口当场复算：点名 12 项全绿；`flutter test --no-pub test/application/anki_official` **244 passed**；native `answer_non_head_card_retries_off_queue` + `queue_good_undo_reopen_and_stale_token` PASS。Device A 评分证据见 `device-a-official-rate.txt`，本轮未再碰用户库。

## 2. `26` 对照现码

| `26` 票 | 现码 | 验货 |
|---|---|---|
| P5D-01 `TURNA_OFFICIAL_ANKI_CUTOVER` 默认 false；`!cutover → always legacy` | `bool.fromEnvironment`；`!cutover` 直接 legacy | **PASS** |
| P5D-01 预览按钮不绑 define | `official_anki_migration_preview_page.dart` `onPressed: null` | **PASS** |
| P5D-02 official + Android + scheduler → `OfficialAnkiReviewPage` | `AnkiOfficialReviewGate` 从 Review hub / Session 接入；Device A 已打开并评分 | **PASS**（无 widget 测 push 页） |
| P5D-02 official 但能力不全 fail-closed | `decideOfficialReviewGate`：缺 catalog / target / capability → `failClosed` | **PASS** |
| P5D-03 Import 决策表 | `AnkiImportFacade.decisionFor` 与表一致 | **PASS**（Host） |
| P5D-04 due 不双计 | `legacyAnkiDueExcludingOfficial` + `officialDue`；Play / Profile / Anki hub 共用 `OfficialAnkiHomeDueSync` | **HOST PASS**；Device Play Hub 评分前显示 Official due 0 |
| P5D-05 / 06 | 未做 | 正确未做 |

Resolver 收紧：默认构建即使 `recordedKind=official` 也回 legacy。`p5d_default_build_still_routes_legacy` 覆盖。

## 3. 点名测试（本轮复跑）

```text
p5d_default_build_still_routes_legacy
p5d_cutover_and_recordedKind_official_routes_official
p5d_user_deck_without_recordedKind_stays_legacy
p5d_ohos_import_stays_legacy
p5d_due_does_not_double_count_official_source
p5d official review gate fail-closed when target missing
resolver keeps current engines and cutover stays false
new import stays fail-closed unless official gates are complete
cutoverEnabled_stays_false
preview_cutover_button_stays_disabled
recordedKind stays per source and cutoverEnabled false
ankiweb not linked from production routes
```

12 passed / 0 failed。

全量：`flutter test --no-pub test/application/anki_official` → **244 passed / 0 failed**（见 `artifacts/p5d/host-d1-closeout.txt`）。

native：`answer_non_head_card_retries_off_queue` PASS；`queue_good_undo_reopen_and_stale_token` PASS。

## 4. 仍然成立的红线

```text
[✓] cutoverEnabled 默认 false
[✓] TURNA_OFFICIAL_ANKI_ENGINE/IMPORT/… 默认 false
[✓] 预览 Cutover 源码 onPressed: null
[✓] 默认构建 resolver / Import 决策为 Legacy
[✓] 用户既有牌组无 p5c-fixture- 前缀、不在 fixture hash allowlist
[✓] README / 26 / 27 未写 P5-D GO / PRODUCTION GO
[✓] 未删 Legacy、未写 AnkiWeb 生产入口
[✓] 本轮收口未 wipe collection.anki2、未点用户牌组
```

## 5. 已记下、不挡 D1 CONDITIONAL GO 的缺口

1. 无 widget 测证明 `_startReview` 真的 push 了 `OfficialAnkiReviewPage`（Device A 已实开并评分）。
2. Play Hub「Official Anki due」评分前为 0；评分后 fixture 排到 4 天后，显示 0 与日程一致。
3. 工作区仍有未提交的 D1 / native 回退改动；收口不依赖已 push 的 commit。

## 6. 验货后的状态（以本文为准）

```text
P5-D D1 HOST CONDITIONAL GO
P5-D D1 DEVICE CONDITIONAL GO（fixture Official Rating only）
P5 USER CUTOVER: NO-GO
P5-D GO: NO
P5-E: HOLD
P6: 已取消（本验货当时写 HOLD）
```

下一步：D1 已收口。后续大施工见 [`28`](./28-p5d-remainder-construction-plan.md)；先 D2，不要直接开灰度 / 用户源 / E。P6 已取消。
