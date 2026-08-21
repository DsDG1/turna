# 施工计划：官方先行导入（代号 P5F）

按仓库惯例立 `docs/official-anki-migration/33-official-first-import-construction-plan.md`（文档代号 P5F、GO/NO-GO 板、任务编号 P5F-NN、每片独立回执进 `artifacts/p5f/`）。施工顺序 **①→③→②→④**（③中的 vocabulary 通道是②的前置）。已定决策：vocabulary 受控写入（对齐旧管线）、归组用投影自带启发式（差异进 parity 白名单）、全量四片。

**总开关**：`official_anki_feature_flags.dart` 新增 opt-in flag `officialFirstImport`（dart-define `TURNA_OFFICIAL_ANKI_OFFICIAL_FIRST_IMPORT`，无 defaultValue）+ 组合 getter `allowsOfficialFirstImport`（要求 import+projection+courseEntry 全开）。flag 关 = 现行为原样保留，全部改动双分支可回退。

---

## Slice ① 顺序翻转（P5F-1）：官方先行，消除"镜像失败被吞"半态

**P5F-11 flag 与判定**
- `lib/application/anki_official/official_anki_feature_flags.dart`：按现有模式加 `officialFirstImport` 字段 + fromEnvironment + copyWith + `allowsOfficialFirstImport` getter。
- 测试：默认 false、dart-define 开启、组合门。

**P5F-12 `_executeImport` 顺序翻转**（`lib/views/anki/anki_import_screen.dart`）
- 把现有 official 镜像块（1606–1678 行）抽成 `_runOfficialImport()` 方法。
- official-first 分支（officialCapable && allowsOfficialFirstImport && 非样例 && `.apkg`）：官方 saga 前移到媒体拷贝/事务**之前**；`state != active` 且非 alreadyImported → 整体失败，Turna 侧零写入，错误走 `_mapOfficialErrorToHuman` 回 step2；成功 → 继续 Turna 事务，跳过旧镜像块（bookkeeping 用返回值）。
- alreadyImported → 直接 noOp done。flag 关/非 official 决策 → 旧序不动。

**P5F-13 反向半态守卫**
- official 成功但后续 Turna 事务失败：官方 source 留 active、记 reconciliation 日志（复用 `_persistClassifiedFailure` 语义）；课程入口由 `filterShells` 天然隐藏未投影 source；重试走 catalog noOp 路径重建 Turna 侧。

测试：官方失败→`anki_imports`/`srs_states`/sections 零行；flag off 旧序回归；assembler 注错→官方保留+UI 可重试。

## Slice ③ 清理面修复（P5F-3，独立于 flag 的真 bug）

**P5F-31 卸载分流 + substring 修复**
- `anki_deck_manager.dart:236`：`contains` 改精确前缀 `anki-$importId-`。
- 新增 `uninstallOfficialSource(sourceId)`（第一期软卸载，不动官方 collection 数据）：`CourseRepository.deleteOfficialProjection`（已有）+ `AnkiUnificationDao` 新增按 courseId 清 placements/presentations/introductions + `OfficialAnkiSourceDao` 新增 `deleteSource`（清 anki_sources/anki_source_cards/attempts(+notes)/projection_mappings/projection_state）。
- `course_management_page._confirmDelete` 按 section 来源分流（`official-anki-` 前缀 → 官方路径），UI 文案说明"可从源管理重新生成课程"。

**P5F-32 seeder 重播护栏**
- `course_database_seeder.dart` `_clearCourseTables` 补删同库的 `official_anki_projection_index` + `official_anki_projection_manifest` → 重播后指纹 no-op 失效、下次 projectSource 全量重建。
- 测试：投影→重播种→projectSource 断言非 noop、树重建。

**P5F-33 vocabulary 受控写入通道**（②的前置）
- `OfficialAnkiProjectionStore.replaceOfficialProjection` 在同一事务内可选写 vocabulary：plan items 的 term/translation 写行（tag `official:$sourceId`），replace 语义=先 deleteByTag 再插，绝不触碰内置行。
- 测试：写入/替换清理/内置 vocabulary 零影响。

## Slice ② 投影替换 Dart 解析（P5F-2，主体工程）

**P5F-21 向导官方路径重排**（`anki_import_screen.dart`）
- 官方路径新步骤：选文件 → step1=官方导入进度（saga progress：hashing→backingUp→importing→indexing；**不再跑 AnkiImporter.parse**）→ preview 数据源改 `getProjectionSchemas` + `OfficialAnkiSourceDao` 计数 + `listDeckTree`；映射确认内联 source-management 模式（suggestFor→confirmMapping/skipNotetype）→ step3=`createProjectionService().projectSource()`（needsMapping 回映射步）→ scope `anki:$sourceId` + persistCourseOrder → done。
- 去重改 catalog `findByHash`（替代 `AnkiImportDao.findByHash`）；官方路径隐藏四策略选择（同 hash 重复=noOp 提示）；colpkg/样例自动走 legacy 分支。

**P5F-22 placements/presentations 换锚**
- `UnifiedAnkiImportOrchestrator` 新方法 `publishFromProjection({sourceId, sourceHash})`：读 `official_anki_projection_index` → `CanonicalCardKey(backend: official, sourceId, cardId: index.cardId)` 1:1 发布；官方路径调用它，legacy 路径 `finalize` 不动。

**P5F-23 媒体解析接通**
- `vocab_audio_resolver.dart`/`AnkiAudioResolver.resolve` 新分支：`official-anki-` wordId 或官方源的裸文件名 audioAsset → `OfficialAnkiCompositionRoot.locatorPaths.mediaFolder` + `OfficialAnkiMediaResolver.resolveRelativeName` 解析到本地文件（穿越防护复用现有）；locatorPaths 空 → 维持现状。
- 修复点：当前投影 listenPick 的裸文件名会落到 TTS 读文件名。

**P5F-24 完成页与文案适配**：done summary 从 projection result 组装；媒体计数；官方路径策略区文案。

**P5F-25 退役 `OfficialAnkiNewImportCutover`**：删除类，p5d routing test 引用改指新流程。

## Slice ④ parity 门禁与灰度（P5F-4）

**P5F-41 存量 re-anchor（一次性）**：启动时 versioned 任务（pref key `official_first_reanchor_v1`）：catalog active + 有 manifest 的源 → `publishFromProjection`；official cardId 与旧 Dart id 不一致的存量 → census 标 `blockedForRepair` 不动。

**P5F-42 parity 白名单 harness**
- 新 `test/application/anki_official/official_first_parity_test.dart`：9 个冻结 fixture + 2 个 p5c fixture 双跑（Dart 管线 vs 官方管线，各自 in-memory course db），diff：卡/note 数、formalDue（eligibility）、placement/presentation 基数、每卡 interaction kind 集、vocabulary 计数；白名单 `test/fixtures/anki_official/parity_allowlist.json`（归组形状差异、一卡一 kind）。
- CI：挂进 `.github/workflows/official_anki.yml` 的 `official-anki-host` job（该 job 已 build host .so）。

**P5F-43 灰度与回执**：内部 dart-define → g1 1% → g4 100%；每档 artifacts 回执（真机导入→复习→卸载全流程截图+命令输出）；回退=flag 关（①保留双分支）+ `deleteProjection` 清投影。

---

## 每片验收（统一纪律）
- `flutter analyze` 改动文件 0 issue；`flutter test --exclude-tags golden` 全量计数进 `test/BASELINE.md`。
- host 侧：`native/turna_anki_core` 内 `cargo test`（PROTOC 用 tools/protoc）+ `flutter test test/application/anki_official`（host ffi / parity）。
- 真机回执按 P4R3 device-receipt 模式归档 `docs/official-anki-migration/artifacts/p5f/`。
- 每片独立 commit、独立可 revert；文档 33 的 GO 板随片更新，README.md 索引同步。

## 风险与兜底
- ①官方失败 fail-closed 不写 Turna；②官方成功投影失败由 job 恢复 + filterShells 隐藏兜底（可重试投影，指纹幂等）。
- ②向导 UX 变化（官方导入先行、策略区简化）只出现在 official-first 分支，legacy 路径 5 步流程原样。
- ④换锚存量风险由 re-anchor + blockedForRepair 兜底；fresh import 官方保留包内 card id，与投影 index 天然一致。