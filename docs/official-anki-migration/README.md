# 官方 Anki Core 迁移文档索引

> 状态：**上位唯一活跃总入口 = [34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)**（Official 生产收口 + OHOS 产品 EOL）；**导入生命周期新设计轴 = [42](./42-staging-first-official-import-lifecycle-plan.md)**（staging-first，ADR 0042，取代 41 的导入链路部分）；**删除与物理回收专项施工入口 = [41](./41-official-anki-lifecycle-and-storage-remediation-plan.md)**（保留 S3/S4/S5/S7/S8 与存量善后）。
> 收口收据：[`34-cutover-receipt.md`](./34-cutover-receipt.md)（**本目录唯一状态真源**；含「W9 HOLD 解除记录与证据台账」与「W9-E 破例记录」两节） · **验收返工计划**：R0–R8 已闭环（**2026-09-27 归档，2026-10-19 已删原文，结论速查见 [`archive/README.md`](./archive/README.md)**） · **生命周期/存储修复**：[`41`](./41-official-anki-lifecycle-and-storage-remediation-plan.md) · **staging-first 重设计**：[`42`](./42-staging-first-official-import-lifecycle-plan.md) · W9 HOLD 已于 2026-08-27 由负责人决策解除（原独立 HOLD 文件已于 2026-09-27 并入收据对应章节） · OHOS：EOL [ADR 0041](../decisions/0041-ohos-product-eol.md) → 伴生版 [ADR 0047](../decisions/0047-ohos-companion-lite-build.md) → Official Anki 接线 [ADR 0050](../decisions/0050-ohos-official-anki.md)（步 0–4 于 2026-10-08 取得基础探针收据；2026-10-13 补修生产接缝；步 5b 复习器已施工并于 2026-10-14 夜取得真机首卡收据；2026-10-16 评分回执与三批修复、2026-10-17 协议/对等性/O1/R2/T1、2026-10-18 评分档二档对齐均已施工；**2026-10-19 已追加「入口白屏修复与顶栏精简」批（撤除 P0-1 预热与 D8 顶栏四键），真机通过，P0-1/D8 两条已作废**（详见 34 收据「鸿蒙复习页白屏修复与顶栏精简（2026-10-19，真机通过）」节）；余项：真机导入、课程学习解锁、步 6 独立 CI）
> 准确口径：**Official Anki 迁移中，生产验收 NO-GO**（不得写「迁移完成」「删除已彻底释放空间」，亦不得写「Android 可正常使用」）。已发生：Legacy 复刻层代码按 doc 35 L0–L3 删除（2026-08-27）；doc 41 Dart host 行为已施工；Android arm64 `.so` 已重建（`verify_symbols.sh` pass）；**schema drop（W9-E）与 NoteStore 读退役已由 2026-09-24 架构简化批次 P1/P2 完成**（course.db v27 DROP `anki_notetypes/anki_notes/anki_cards_meta`，`AnkiNoteDao`/`IAnkiNoteStore` 删除；W9-E 破例已记档）。**设备会话已有两次**：2026-09-02 Android 真机 PLG110（debug 构建，写侧成立；同夜 F6 阻断「进一个课时」，已修但修后未复跑）、2026-09-26 iPhone 17 模拟器（真 .apkg 导入 + 复习器 Q→A）——逐条覆盖范围见收据「真机 / 模拟器证据台账」。仍未发生：任何正式发版（存量用户为零）、**Android 生产 bundle 完整用户流**、release 真机矩阵（干净/升级安装/迁移包/备份恢复/强杀恢复）、iOS 真机（非模拟器）验收。当前版本：Official catalog **v14** / contract **1.13**。
> 首发目标：**Android arm64 + iOS**（iOS 于 2026-09-26 经 `ec0170ae` 启用官方 Anki 引擎：静态链接 rslib 的 `TurnaAnki.xcframework` + WKWebView reviewer，见 [`native/turna_anki_core/README.md`](../../native/turna_anki_core/README.md)）
> 总原则：官方 Anki Collection 是唯一 Anki 事实源，Turna 只维护课程投影；非 Android 不得以缺 Official Core 为由打开 Legacy 新写入
> 目录布局：active 施工文档在根目录（**当前只剩 34 收据 / 34 主计划 / 41 / 42 / 44 五篇**）；已被 34 接管或收口的历史计划/报告（Phase 0–4、P5A/B/C/D1/E、28/30/31/32/33/34-remaining/35/36/37/38/39/40）已于 **2026-10-19 精简为 [`archive/README.md`](./archive/README.md) 的结论速查表**（原文已删，git tag `docs-cleanup-backup-2026-10-19` 可恢复）；`archive/artifacts/` 同批精简至 4 个有真实引用方的证据文件。
> 历史执行记录：Phase 0–4 / P5 各阶段结论速查见 [`archive/README.md`](./archive/README.md)（原文已删，git tag `docs-cleanup-backup-2026-10-19` 可恢复）

## Active 文档（当前在跑）

| 顺序 | 文档 | 用途 | 当前状态 |
|---|---|---|---|
| **34 收据** | [34 Cutover receipt](./34-cutover-receipt.md) | **本目录唯一状态真源**：Done 表、架构简化 P0–P4 批次记录、iOS 启用批次、**鸿蒙 Official Anki 接线批次步 0–4**、**真机/模拟器证据台账**、**两项固有限制开放状态**、W9 HOLD 解除记录与证据台账、W9-E 破例记录、Held 表、准确口径行。**改状态只改这里**，再由 34 主计划反向引用 | **活跃且准确**（2026-09-27 二次更新：补记 iOS 启用与两次设备会话、订正 Held 表「无设备会话」过期表述、新增「Android 可正常使用」禁止口径与限制①②开放状态；2026-10-08 补记鸿蒙接线批次步 0–4 并同步 Held 表「鸿蒙 Official Anki」行；2026-10-19 补记鸿蒙复习页白屏修复与顶栏精简（撤除 P0-1 预热与 D8 顶栏四键，真机通过）） |
| **34** | [Official 生产收口与 OHOS 退役](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) | **唯一活跃施工入口**：W0–W10 止血、OHOS EOL、owner census、Official import/review、Legacy 迁移与分波删除 | **验收 NO-GO**；2026-08-25 一次性施工完成 R0–R8 host 侧并全绿（analyze 0 issue / 全量 1852:0 / golden 4:4 / native 68:0 / arm64 APK 56.1MB），形成工作树生产候选；真机矩阵与外部事实未验收，明细见 [收据](./34-cutover-receipt.md) 的「Done」与「证据台账」两节（34-remaining §18 原文已归档删除，结论已并入收据）；W9 HOLD 已解除（2026-08-27 负责人决策） |
| **41** | [Official Anki 导入生命周期与存储回收修复](./41-official-anki-lifecycle-and-storage-remediation-plan.md) | **P0 专项**：修复导入后退出/强杀形成隐藏 source、cancel 无补偿、startup recovery 未接线、删除后全局 deck/notetype/mapping 污染、Official 媒体与 rollback checkpoint 无界保留、SQLite 逻辑删除不回收物理字节；含 verified uninstall、media GC、bounded checkpoint、compact、存量 census/repair center 与真机强杀矩阵 | **施工中（2026-08-31）**：Dart host 行为已落地（**当前 catalog v14 / contract 1.13**）；Android arm64 `.so` 已重建（`verify_symbols.sh` pass）；Android 强杀矩阵未跑；生产验收 NO-GO。**导入链路部分（S1/S2 导入分支/S6）由 42 取代**（ADR 0042）；本文件保留范围为删除与物理回收（S3/S4/S5/S7）+ 存量善后（S8/§7.4/§11.4），S8 UI 子实现已并入 §13.3.1（原 doc 43） |
| **42** | [Staging-first Official 导入生命周期重设计](./42-staging-first-official-import-lifecycle-plan.md) | **导入设计轴反转**：导入先落一次性 staging collection（独立 isolate），预览/映射在 staging 上做，用户确认后才对 live Collection 执行唯一一次 import；取消 = 删 staging 目录。修复四症状（取消落盘/清理卡死/needsMapping 死循环/映射确认不可用）的结构性根因；含 P0 失败测试门禁、强杀矩阵、doc 41 范围交接表 | **P4 已施工（2026-08-31）**：生产导入只走 staging → `commitLive`；旧 live-first `importFile` 已删。P0 四门禁绿。ADR 0042 已接受 |
| **44** | [鸿蒙复习入口：时延、打扰与安卓对齐审查](./44-ohos-review-entry-latency-and-parity-audit.md) | **审查 + 实施设计 + 施工记录**（不改状态口径）：只审「点复习 → 首卡可读」一段。给出 9 段串行时序、9 条缺陷（D1–D9）、**P0/P1/D8 逐项 8 子项的可执行设计**（D1 / P0-1 预热 / P0-2 分批 / P1-3 媒体 / P1-4 暖帧 / D8 工具栏，P2-5、P2-6 只到测量方案）、减少打扰四原则、与安卓的 15 维差异表（已订正 3 行判定、新增 3 项缺口） | **审查完成 + 两批施工（2026-10-18）**：结论为「复习器能跑、入口段最差」。已施工——D7 评分档改对齐安卓二档（`again`/`good`）、D1 错误出口、P1-3 媒体单次 IO + 有界并发、P1-4 暖帧、P0-2 首屏窗口 8；**其中 P0-1 预热与 D8 工具栏三键已于 2026-10-19 撤除**（预热是复习入口白屏的根因，四键与二档产品口径不符；见 [34 收据](./34-cutover-receipt.md)「鸿蒙复习页白屏修复与顶栏精简（2026-10-19，真机通过）」）；其余项已真机通过，仍不改 34 收据 Held 口径。**剩余：P2-5 / P2-6 两个测量项（只测量不施工）**——四项形态差异（UI-15 源徽章 / 高对比度主题 / 工具栏启用判定；UI-16 完成屏交棒）已施工且 ArkTS 有编译器收据（其中「工具栏启用判定」随四键于 2026-10-19 撤除）；2026-10-18 夜真机复验暴露的**推进缺陷已修通**（根因是复习器为独立 ability、盖住 Flutter 页面时 Flutter 不产帧 → 新卡无人装载；改为 binding 原地 `presentInPlace` + 补 `acceptPresentation`，评分与三键都接；真机连评 6 张 0 stall，见 [34 收据](./34-cutover-receipt.md)「同夜第三轮」） |

## Archived 文档（Phase 0–4 + P5 收口记录：2026-10-19 已精简为结论速查）

> **2026-10-19 精简**：原 `archive/` 下的 43 篇阶段施工文档（计划 / 结果报告 / 施工手册 / 验货报告）与 169 个构建真机证据文件已删除——它们全部只被本目录内部互引，结论均已被下方收据取代。
>
> **每篇文档的结论速查表**（决策溯源保留）见 [`archive/README.md`](./archive/README.md)；原文可经 git tag `docs-cleanup-backup-2026-10-19` 恢复。
>
> 保留的 4 个证据文件（`apk-sha256.txt` / `native-hash-manifest.txt` / `recognizer-diff-report-2026-08-29.md` / `p5f/README.md`）有仓库内真实引用方，清单见 [`archive/README.md`](./archive/README.md)。

| 编号 | 主题 | 归档前状态（均已被收据取代，勿据此判断当前进度） |
|---|---|---|
| 00 | 总体迁移方案 | 提案；141 个未勾选框是计划状态，非未施工 |
| 01 / 02 | Phase 0 实施方案 / 结果报告 | Phase 0 已收口，Conditional Go |
| 03 / 04 | Phase 1 实施方案 / 结果报告 | 生产切流状态：禁止；已降级，以 06 为准 |
| 05 / 06 | Phase 0+1 技术修补计划 / 结果 | 已实施；TECHNICAL CONDITIONAL GO |
| 07 / 08 / P2FIX | Phase 2 官方原卡渲染 | 已施工；TECHNICAL ACCEPTANCE NO-GO |
| 09 / 10 / P3FIX | Phase 3 课程投影 | HOST CONSTRUCTION GO；P3 TECHNICAL / PRODUCTION NO-GO |
| 11 / 12 / 13 | P3 修补 + Phase 4 官方 Scheduler | 计划冻结；P4 HOST GO / TECHNICAL ACCEPTANCE NO-GO |
| 14 | Phase 4 验货 + Phase 5 Legacy 迁移 | P5 CUTOVER/DELETE 仍 NO-GO |
| 15 | P5-A Legacy 依赖盘点 | 已落地；不改变用户 engine |
| 16–20 | P4R3 门禁收口与 P5-B 准备 | 已收口闭环 |
| 21–25 | P5-C Fixture Pilot 试点与收口 | 23 撤销过早 GO；25 收口（HOST CONDITIONAL GO，USER CUTOVER NO-GO） |
| 26 / 27 | P5-D Sprint D1 生产路由 | D1 HOST+DEVICE CONDITIONAL GO（仅 fixture）；P5-D GO NO |
| 28 | P5-D 后续大施工 | 由 34 接管；灰度 cohort /「OHOS 继续 Legacy」作废（ADR 0041） |
| 29 | P5-E Wave 1 生产解耦 | Wave 1 已收口；Wave 2–4 HOLD |
| 30 | 官方 Anki 卡按语言课体验投影与渲染 | Host / Unit 已通过；生产默认与 chrome 见 34；题型识别部分由 37 取代 |
| 31 / 32 / 33 | 产品体验收口 / 体验对齐 / P5-F 官方先行导入 | 历史规格，由 34 接管 / superseded |
| 34-remaining | R0–R8 一次性收口返工 | R0–R8 已由收据全部闭环；未勾框不代表未施工 |
| 35 | Legacy 复刻层清理（L0–L3） | 已施工（2026-08-27）；W9-E schema drop 不在其内，由 2026-09-24 批次完成 |
| 36 | 投影课程树顺序与限额修复 | 已施工（2026-08-28）；成果由 CHANGELOG 记录 |
| 37 | 通用卡片识别器重设计 | 已施工（2026-08-29），diff 门禁 16/16；现行实现见 `lib/application/anki_import/recognition/` |
| 38 | 集成减负与性能批次一 | 已施工并验货（2026-08-30，零回归）；P4-B 按计划条件推迟 |
| 39 | 集成减负与性能批次二 | 部分施工（2026-08-30）；余项移交 40 |
| 40 | doc 39 收尾施工计划 | 已施工（2026-08-30）；Rust 四波复验待工具链主机 |

> **发布合规证据链不在 `archive/`**——在 `native/turna_anki_core/licenses/`（ANKI-LICENSE / SOURCE-OFFER.md / THIRD-PARTY-NOTICES-DRAFT.md），门禁为 `test/application/anki_official/official_anki_license_test.dart`。

## 阶段命名

为了避免“第一阶段”和“Phase 1”产生歧义，本目录统一采用以下命名：

```text
第一阶段 = Phase 0：技术 Spike
第二阶段 = Phase 1：稳定 Engine 与官方导入
第三阶段 = Phase 2：官方原卡渲染
第四阶段 = Phase 3：课程投影
第五阶段 = Phase 4：官方 Scheduler
第六阶段 = Phase 5：Legacy 迁移与删除
第七阶段 = Phase 6：已取消。不与 AnkiWeb / 官方 Anki 账号同步
```

第一阶段不修改生产导入默认行为，也不删除 Legacy 代码。它只回答以下问题：

1. 官方 `rslib` 能否在当前官方 Flutter / Android 构建环境下编译为 arm64 `.so`？
2. Flutter release APK 能否稳定加载它？
3. 能否完成 open、import、render、queue、answer、undo 的最小闭环？
4. Unicode、Reverse、Cloze 和媒体是否能按官方语义工作？
5. APK 体积、冷启动、内存和大牌组性能是否可接受？
6. AGPL 与源码分发是否存在阻止产品发布的障碍？

Phase 0 的全部硬门禁通过是进入 Phase 1 的前置条件（该方案原文已归档删除，结论速查见 [`archive/README.md`](./archive/README.md)）。

## 文档维护规则

- 总体架构变化先修改 `00-overall-migration-plan.md`（已归档；现行架构以 34 与 ADR 0036/0037/0041 为准）。
- 当前总收口变化修改 [34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) 与 [`34-cutover-receipt.md`](./34-cutover-receipt.md)；导入生命周期施工先更新 [42](./42-staging-first-official-import-lifecycle-plan.md) 的施工收据（§12），删除/物理回收与存量善后先更新 [41](./41-official-anki-lifecycle-and-storage-remediation-plan.md) 的施工收据，过各自门禁后再同步 34 准确口径。不要改 archive 里的历史报告。
- 已执行任务必须填写实际 commit、命令、指标和证据，不能只勾选复选框。
- 未验证的构建命令必须标注“候选”或“待验证”。
- 任何上游 Anki commit 变化都要重新运行 contract、fixture 和性能门禁。
- Legacy 删除必须有单独任务和恢复方案，不能作为顺手清理。
- 本目录记录的是迁移事实，不保留已经被否决的并行实现作为默认路径。

## 关键外部参考

- 官方 Anki：<https://github.com/ankitects/anki>
- Anki 架构：<https://github.com/ankitects/anki/blob/main/docs/architecture.md>
- AnkiDroid Backend：<https://github.com/ankidroid/Anki-Android-Backend>
- cargo-ndk：<https://github.com/bbqsrc/cargo-ndk>
- Flutter Android FFI：<https://docs.flutter.dev/platform-integration/android/c-interop>
