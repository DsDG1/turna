# P5-F 官方先行导入施工计划

> 文档代号：P5F
> 日期：2026-08-22
> 前置：[`28`](./28-p5d-remainder-construction-plan.md)（D5 已翻转）、[`29`](./archive/29-p5e-wave1-production-decoupling-report.md)（Wave 1 已收口）、[`32`](./32-official-anki-experience-parity-plan.md)
> 状态：**历史规格；勿按本文开施工波次。** OHOS Legacy 作废（[ADR 0041](../decisions/0041-ohos-product-eol.md)）；Official-first 是生产 bundle（无 `TURNA_OFFICIAL_ANKI_OFFICIAL_FIRST_IMPORT` dart-define）。默认策略与 fail-closed 以 [34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) W0/W4 为准；本文仅作 P5-F 历史施工记录。
> 目标：导入以官方 Collection 为先（官方 saga 先行、失败不吞）；official 路径课程树由官方投影生成（Dart apkg 解析退出 official 路径）；内置主课程零影响；其他功能经 parity 白名单证明一致。

## 0. 已定决策（2026-08-22 书面）

| 决策点 | 结论 |
|---|---|
| official 词进词典 | **受控写入**：投影发布时带 `official:$sourceId` 标签写 vocabulary，与旧管线行为一致 |
| 课程树归组 | **投影自带启发式**（deck 路径 + unit::/lesson:: 标签）；与旧管线智能归组的形状差异登记 parity 白名单 |
| 施工范围 | **全量四片** ①顺序翻转 ③清理面 ②投影替换 ④parity 门禁与灰度 |

## 1. GO 板

```text
本次书面 GO（2026-08-22）
  P5F-1 CONSTRUCTION GO    顺序翻转：official-first 分支默认关（opt-in flag），不改生产流量
  P5F-3 CONSTRUCTION GO    清理面修复：卸载 substring/seeder 重播/catalog deleteSource（真 bug，独立于 flag）
  P5F-2 CONSTRUCTION GO    投影替换 Dart 解析：仅在 official-first flag 开启的分支生效
  P5F-4 CONSTRUCTION GO    parity harness 进 CI（host job）；灰度序列另按档出回执

施工进度（2026-08-22，Host 工作区完成，提交被 Mimosa git 门禁拦截至待放行）
  P5F-11/12/13 已施工   flag+policy+顺序翻转+反向半态守卫；3 widget 测试
  P5F-31/32/33 已施工   卸载分流+deleteSource+seeder 护栏+vocabulary 通道；6 测试
  P5F-21/22/23/24/25 已施工  向导官方路径重排+publishFromProjection+媒体接通+退役 cutover；widget 全流程测试
  P5F-41 已施工         启动一次性 re-anchor；1 测试
  P5F-42 已施工         parity harness（2 冻结 fixture 双管线）+白名单；CI dart job 自动覆盖该目录
  验证：flutter test --exclude-tags golden = 1299/0（基线 1266，+33）；analyze 改动文件 0 新增 issue
  未做：真机回执（待灰度放行）、host job 真实 rslib 版 parity（fake 引擎只验证管线，见白名单 card-id-parity-scope）

明确 NO-GO / HOLD
  生产默认开启 official-first        NO-GO（须单独立项：内部 → g1 → g4 每档 artifact 回执）
  删除 Legacy AnkiImporter/Assembler  HOLD（沿用 28 的 P5-E Wave 2–4 HOLD）
  P6 AnkiWeb                          已取消（不变）
```

判定规则：所有改动挂 `TURNA_OFFICIAL_ANKI_OFFICIAL_FIRST_IMPORT`（默认 false）双分支；flag 关闭时现有 5 步向导与双写顺序原样。任何 `fromEnvironment` 默认值翻转须另 go。

## 2. 现状（为什么施工）

- 生产向导是 Dart 先行双写：`AnkiImporter.parse` → 课程树 + NoteStore 事务 → 官方 saga 镜像（失败仅 debugPrint 吞掉，`anki_import_screen.dart:1673`）→ 存在"投影成功、官方无卡"半态。
- 官方投影服务（P3）已能从官方 Collection 独立生成完整课程树（`official_anki_projection_service.dart`），无生产向导入口。
- 已知三洞：`uninstallDeck:236` substring 误删、seeder 重播清 section 留 stale manifest 导致指纹 no-op 永不重建、官方源无卸载路径。

## 3. 任务清单

### Slice ① 顺序翻转（P5F-1）

| ID | 内容 | 关键落点 |
|---|---|---|
| P5F-11 | 新增 opt-in flag `officialFirstImport` + 组合门 `allowsOfficialFirstImport` | `official_anki_feature_flags.dart` |
| P5F-12 | 抽 `_runOfficialImport()`；official-first 分支官方 saga 前移至 Turna 写入之前，失败整体失败零写入；alreadyImported → noOp done | `anki_import_screen.dart` `_executeImport` |
| P5F-13 | 反向半态守卫：官方成功 + Turna 事务失败 → 官方留 active、记 reconciliation 日志、`filterShells` 隐藏未投影源、可重试 | 同上 catch 路径 |

### Slice ③ 清理面修复（P5F-3，独立于 flag）

| ID | 内容 | 关键落点 |
|---|---|---|
| P5F-31 | substring → 精确前缀；新增 `uninstallOfficialSource`（软卸载：投影+catalog+unification 清理，不动官方 Collection 数据）；`OfficialAnkiSourceDao.deleteSource`；课程管理删除分流 | `anki_deck_manager.dart`、`official_anki_source_dao.dart`、`course_management_page.dart` |
| P5F-32 | seeder `_clearCourseTables` 补删 `official_anki_projection_index`/`manifest`（同库），重播后投影全量重建 | `course_database_seeder.dart` |
| P5F-33 | 投影 store 增加受控 vocabulary 写入通道（tag `official:$sourceId`，replace=deleteByTag+插，同事务，绝不碰内置行）——②的前置 | `official_anki_projection_store.dart` |

### Slice ② 投影替换 Dart 解析（P5F-2，主体）

| ID | 内容 | 关键落点 |
|---|---|---|
| P5F-21 | 向导官方路径重排：选文件 → 官方 saga 进度步（不再跑 AnkiImporter）→ schema 预览（`getProjectionSchemas`+`listDeckTree`+catalog 计数）→ 映射确认（suggestFor→confirmMapping/skipNotetype）→ `projectSource()` 执行 → done；去重改 catalog `findByHash`；官方路径隐藏四策略；colpkg/样例自动走 legacy | `anki_import_screen.dart` |
| P5F-22 | placements/presentations 换锚：`UnifiedAnkiImportOrchestrator.publishFromProjection(sourceId)` 读投影 index 1:1 发布；legacy 路径 `finalize` 不动 | `unified_anki_import_orchestrator.dart` |
| P5F-23 | 媒体解析接通：`official-anki-` wordId / 官方源裸文件名 audioAsset → `locatorPaths.mediaFolder` + `OfficialAnkiMediaResolver` 本地文件；修复 listenPick 落 TTS 读文件名 | `vocab_audio_resolver.dart` / `anki_audio_resolver.dart` |
| P5F-24 | done 页 summary 从投影结果组装；官方路径文案（重复导入 noOp 提示、colpkg 分流提示） | `anki_import_screen.dart` |
| P5F-25 | 退役 `OfficialAnkiNewImportCutover`（职责被 ①+② 取代）；p5d routing test 引用改指新流程 | `official_anki_new_import_cutover.dart` 删除 |

### Slice ④ parity 门禁与灰度（P5F-4）

| ID | 内容 | 关键落点 |
|---|---|---|
| P5F-41 | 存量 re-anchor 一次性任务（pref key `official_first_reanchor_v1`）：catalog active + 有 manifest 的源 → `publishFromProjection`；id 不一致存量 → census `blockedForRepair` 不动 | 启动任务（readOnly locator 之后） |
| P5F-42 | parity 白名单 harness：9 冻结 fixture + 2 p5c fixture 双管线跑，diff 卡/note 数、formalDue、placement/presentation 基数、每卡 kind 集、vocabulary 计数；白名单 `parity_allowlist.json`；挂 `official-anki-host` CI job | `test/application/anki_official/official_first_parity_test.dart`、`.github/workflows/official_anki.yml` |
| P5F-43 | 灰度回执模板（内部 → g1 → g4，每档 artifact）；README 索引更新 | `artifacts/p5f/` |

## 4. parity 白名单初始内容

1. 课程树形状（归组启发式差异：unit/lesson 划分与旧智能归组不同）
2. 一卡一 interaction kind（旧管线一卡可多练习投影）
3. official 路径无 NoteStore / 无 `anki_imports` 行 / 无 Turna SRS 写入（by design）

白名单外任何 diff = CI 红。白名单只增不改（增须在本文件记行）。

## 5. 验收（每片统一）

```bash
flutter analyze                                     # 改动文件 0 issue
flutter test --exclude-tags golden                  # 全量计数写入 test/BASELINE.md
cd native/turna_anki_core && PROTOC="$PWD/../tools/protoc/bin/protoc" cargo test
flutter test test/application/anki_official         # host ffi / parity（host .so 由 cargo test 产出）
```

- 每片独立 commit、独立可 revert；本文 GO 板随片更新。
- 真机回执按 P4R3 device-receipt 模式归档 `artifacts/p5f/`（导入→复习→卸载全流程）。

## 6. 回退

- flag 关闭即回旧序（①③保留双分支）；投影数据可 `deleteProjection` 清除。
- 换锚存量风险由 re-anchor + `blockedForRepair` 兜底；fresh import 官方保留包内 card id，与投影 index 天然一致。
