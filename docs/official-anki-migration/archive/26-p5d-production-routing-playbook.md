# P5-D Sprint D1 生产路由施工手册

> 文档代号：P5D-HOWTO  
> 日期：2026-08-19  
> 前置：[`24`](./24-p5-remainder-and-p6-ankiweb-plan.md) §5、[`25`](./25-p5c-closeout-result-report.md)、`artifacts/p5c/rollback-drill.txt`  
> 产品指示：进入 P5-D。方案 B（Android 先行，OHOS 留 Legacy）。  
> 本文件是 **P5D-01…04 怎么改、怎么算过**。不是 P5D-05 灰度，不是 P5-E。P6 已取消。

## 1. 结论先行

```text
本轮：生产入口按 source resolver 分流；默认构建仍 Legacy
cutoverEnabled ← TURNA_OFFICIAL_ANKI_CUTOVER（默认 false）
TURNA_OFFICIAL_ANKI_ENGINE/IMPORT/… 默认仍 false
预览页 Cutover 按钮保持源码 disabled
用户既有牌组不进 allowlist
P5 USER CUTOVER: NO-GO
P5-E: HOLD
P6: 已取消（本手册当时写 HOLD）
Device B: out of scope
```

## 2. 方案 B 与 §10 豁免

平台：Android 可走 official；OHOS / iOS / Windows 导入与复习入口继续 Legacy。OHOS 上若某 source `recordedKind==official` 但无 official Reviewer：打开复习 **fail-closed**，禁止静默半套 Legacy 评分。

| `14` 条 | 本批为何可缺 |
|---|---|
| 10.1 全量用户迁移对账 | 不迁用户牌组；只认已 cutover fixture 与新 official 导入 |
| 10.2 100 卡 revlog | P4 Device A 已有；本批不重跑用户 100 张 |
| 10.3 两台设备 rollback | 只认 Device A；mutation=0/>0 已落盘 |

## 3. 硬约束

```text
不把 TURNA_OFFICIAL_ANKI_* 现有默认改 true
不写 cutoverEnabled 默认 true
不解预览 Cutover 按钮
不把首页 due 改成「全部官方队列」
不迁设备上既有用户牌组
不删 lib/application/anki 或 lib/views/anki
不 wipe collection.anki2
不做 1%→100% 灰度、不删 Legacy、不写 AnkiWeb
```

内部 APK 才加：

```bash
--dart-define=TURNA_OFFICIAL_ANKI_CUTOVER=true
```

可与现有 ENGINE/IMPORT/CATALOG/RUNTIME/PLATFORM/RENDERER/SCHEDULER 一起。CUTOVER 不是预览按钮开关。

## 4. Resolver（先改，再接线）

```text
!cutoverEnabled                    → always legacy
cutoverEnabled && kind==official   → official
cutoverEnabled && kind==legacy     → legacy
cutoverEnabled && kind==null
  && officialCatalogHasSource      → official
else                               → legacy
```

测试可传入 `cutoverEnabled:` 覆盖；生产读 `LegacyAnkiMigrationFlags.cutoverEnabled`。

## 5. 票

### P5D-01 flag + resolver

`LegacyAnkiMigrationFlags.cutoverEnabled = bool.fromEnvironment('TURNA_OFFICIAL_ANKI_CUTOVER')`。预览按钮 `onPressed: null`，不要绑这个 define。

### P5D-02 Review

`AnkiReviewPage._startReview` / `AnkiReviewSessionPage`：该 import 经 resolver=official **且** Android+`allowsOfficialScheduler` → `OfficialAnkiReviewPage`（该 source 的 deckId + `allowedCardIds`）。official 但 catalog/target/能力不全 → SnackBar fail-closed（`decideOfficialReviewGate`），**不要**掉回 Legacy Session。用户牌组无 `recordedKind` → 仍 Legacy。

### P5D-03 Import

`AnkiImportFacade.decisionFor`：

| 条件 | 决定 |
|---|---|
| `cutoverEnabled==false` | legacy |
| OHOS / iOS / Windows | legacy |
| Android + `allowsOfficialImport` | official |
| Android + cutover + 半套 flag | fail-closed |

### P5D-04 Due

Anki badge = Turna SRS 中 `anki-` 且 **非** official-routed import 的 due + official `countsForDeckToday`（仅 official-routed deck）。双写禁止。首页入口仍是 `AnkiReviewRoute`，不是「全部官方队列」。

## 6. 测试名

```text
p5d_default_build_still_routes_legacy
p5d_cutover_and_recordedKind_official_routes_official
p5d_user_deck_without_recordedKind_stays_legacy
p5d_ohos_import_stays_legacy
p5d_due_does_not_double_count_official_source
p5d official review gate fail-closed when target missing
preview_cutover_button_stays_disabled
ankiweb_not_linked_from_production_routes
```

`cutoverEnabled` 断言改为「默认 false」，不要再要求 `static const`。

## 7. 过线

```text
flutter test --no-pub test/application/anki_official
默认构建：resolver/Import/Review 全 Legacy
Cutover 按钮源码仍 disabled
不写 PRODUCTION GO / P5-D GO
```

Device A 换包装 CUTOVER 复算另开，不绑本批 Host 必过。
