# 官方 Anki Core 迁移文档索引

> 状态：**唯一活跃施工入口 = [34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)**（Official 生产收口 + OHOS 产品 EOL）。
> 收口收据：[`34-cutover-receipt.md`](./34-cutover-receipt.md) · **验收返工计划**：[`34-remaining-construction-plan.md`](./34-remaining-construction-plan.md) · W9 HOLD：[`34-w9-legacy-deletion-hold.md`](./34-w9-legacy-deletion-hold.md) · OHOS ADR：[0041](../decisions/0041-ohos-product-eol.md)
> 准确口径：**Official Anki 迁移中**（不得写「迁移完成」——正式 release 观察与 Legacy 物理删除仍 HOLD）。
> 首发目标：Android arm64
> 总原则：官方 Anki Collection 是唯一 Anki 事实源，Turna 只维护课程投影；非 Android 不得以缺 Official Core 为由打开 Legacy 新写入
> 目录布局：active 施工文档在根目录，Phase 0–4 收口与 P5A/B/C/D1/E 的计划/报告归档到 [`archive/`](./archive/)，artifacts 一并归档。
> 历史执行记录：[`archive/02-phase-0-result-report.md`](./archive/02-phase-0-result-report.md)

## Active 文档（当前在跑）

| 顺序 | 文档 | 用途 | 当前状态 |
|---|---|---|---|
| **34** | [Official 生产收口与 OHOS 退役](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) | **唯一活跃施工入口**：W0–W10 止血、OHOS EOL、owner census、Official import/review、Legacy 迁移与分波删除 | **验收 NO-GO / 返工中**；Official-first、OHOS 主工程删除、arm64 构建骨架可保留；course scope、实时复习、due、W8、parity、数据出口与发布门禁见 [34-remaining](./34-remaining-construction-plan.md)；W9 HOLD |
| 28 | [P5-D 后续大施工计划](./28-p5d-remainder-construction-plan.md) | 历史 D2 手册 + 灰度锁 | **由 34 接管**；灰度 cohort /「OHOS 继续 Legacy」作废（ADR 0041） |
| 30 | [官方 Anki 卡按语言课体验投影与渲染](./30-course-like-card-experience-plan.md) | 在官方核心之上恢复自动题型识别、语言课渲染、翻面/展开动画；评分仍写官方 Scheduler | **已实施（Host / Unit 验证通过）**；生产默认与 chrome 见 **34** |
| 31 | [Anki 产品体验收口](./31-anki-product-experience-plan.md) | 历史产品体验规格 | **由 34 接管 / superseded**；勿再按本文件单独开施工波次 |
| 32 | [官方 Anki 与自研体验对齐](./32-official-anki-experience-parity-plan.md) | 历史 parity 规格 | **由 34 接管 / superseded**；残留 parity 面并入 34 W7 |
| 33 | [P5-F 官方先行导入施工计划](./33-official-first-import-construction-plan.md) | 历史 official-first 施工 | **由 34 接管 / superseded**；默认策略与 fail-closed 以 34 W0/W4 为准 |

## Archived 文档（Phase 0–4 + P5A/B/C/D1/E 收口记录，归档保留备查）

| 顺序 | 文档 | 用途 | 归档前状态 |
|---|---|---|---|
| 00 | [总体迁移方案](./archive/00-overall-migration-plan.md) | 目标架构、数据所有权、渲染、调度、Legacy 迁移和完整阶段划分 | 提案 |
| 01 | [第一阶段实施方案](./archive/01-phase-0-implementation-plan.md) | Android arm64 技术 Spike 的逐任务施工、验收和 Go/No-Go 门禁 | 已收口 |
| 02 | [第一阶段结果报告](./archive/02-phase-0-result-report.md) | 基线、命令、指标、Conditional Go | 已决策 |
| 03 | [第二阶段实施方案](./archive/03-phase-1-implementation-plan.md) | 稳定 Engine、contract v1、官方导入 Saga、恢复与生产入口门禁 | 已实施（技术修补后见 06） |
| 04 | [第二阶段结果报告](./archive/04-phase-1-result-report.md) | 基线、命令、指标、Conditional Go | 已降级；以 06 为准 |
| 05 | [Phase 0 + Phase 1 技术修补计划](./archive/05-phase-0-phase-1-technical-remediation-plan.md) | 排除 License 后的 ABI、Engine、Saga、Android、CI 与文档联合收口 | 已实施 |
| 06 | [Phase 0 + Phase 1 技术修补结果](./archive/06-phase-0-phase-1-technical-remediation-result.md) | Host 真实 FFI、Saga、backup、CI 与技术决策 | TECHNICAL CONDITIONAL GO |
| 07 | [Phase 2 官方原卡渲染实施计划](./archive/07-phase-2-implementation-plan.md) | P1 遗留修补、官方 render contract、安全 Reviewer、media origin、AV/TTS、Typed Answer、MathJax 与验收 | 已实施施工；见 08 |
| 08 | [Phase 2 结果报告](./archive/08-phase-2-result-report.md) | Host/Dart/Android 产物、未测项和 Go/No-Go | IMPLEMENTATION IN PROGRESS；TECHNICAL NO-GO |
| P2FIX | [Phase 2 官方原卡渲染修补计划](./archive/p2fix.md) | 修复媒体 base/IRI/Range、MathJax 打包、真实 AV、脚本隔离、生命周期与 Android 验收 | 施工中；TECHNICAL ACCEPTANCE NO-GO |
| 09 | [P2 必要补齐 + Phase 3 课程投影实施计划](./archive/09-p2-entry-remediation-and-phase-3-plan.md) | 先关闭 P3 开工所需的 P2 硬阻断，再实施 contract 1.2、字段 mapping、可重建课程投影和设备验收 | HOST CONSTRUCTION GO；STRICT ENTRY NO-GO |
| P3FIX | [Phase 3 官方 Anki 课程投影修补计划](./archive/p3fix.md) | 修复 Android contract 产物、source 分页一致性、job/recovery、mapping wizard、Interaction 和 CourseProvider 端到端接入 | P3 FIX CONSTRUCTION GO；TECHNICAL ACCEPTANCE NO-GO |
| 10 | [Phase 3 修补结果报告](./archive/10-phase-3-fix-result-report.md) | 记录 P3 Host 施工、Android 产物、测试证据和未通过的设备硬门禁 | P3 TECHNICAL/PRODUCTION NO-GO |
| 11 | [P3 阻断修补 + Phase 4 官方 Scheduler 实施计划](./archive/11-p3-remediation-and-phase-4-scheduler-plan.md) | 先关闭 P3 生产接线、job、课程推进、容量和 mapping 阻断，再正式化官方 Scheduler contract、session、UI 与设备验收 | P3 REMEDIATION REQUIRED；P4 ENTRY NO-GO |
| 12 | [Phase 4 官方 Anki Scheduler 实施计划](./archive/12-phase-4-official-scheduler-implementation-plan.md) | 独立定义 Scheduler contract 1.3、opaque token、正式复习状态机、Undo/Redo、Bury/Suspend、差分测试及设备发布门禁 | 已实施 Host；见 13 |
| 13 | [Phase 4 结果报告](./archive/13-phase-4-result-report.md) | Host/contract/session 证据和诚实的 Technical/Production NO-GO | P4 HOST GO；TECHNICAL ACCEPTANCE NO-GO；PRODUCTION NO-GO |
| 14 | [Phase 4 验货、修补与 Phase 5 Legacy 迁移实施计划](./archive/14-phase-4-audit-remediation-and-phase-5-execution-plan.md) | 复核 P4 源码、测试、APK/设备证据，定义 P4R2 修补包、P5 migration registry、分批切换、回滚和删除门禁 | Formal Reviewer 结论以 16 / artifact 为准；P5 CUTOVER/DELETE 仍 NO-GO |
| 15 | [P5-A Legacy 依赖盘点](./archive/15-p5-legacy-inventory.md) | 只读列出 Legacy 30 个文件与目录外生产引用 | 已落地；不改变用户 engine |
| 16 | [P4R3 生产门禁收口与 P5-B 准备计划](./archive/16-p4r3-production-gate-and-p5b-prep-plan.md) | Device A 剩余硬证据、不可渲染卡、hash 闭环、补完 P5-B Saga；不开 cutover | 已收口闭环 |
| 17 | [P4R3 结果报告](./archive/17-p4r3-result-report.md) | 记录 P4R3 真机闭环、性能抽样、P5-B Saga 落盘与收口决策 | P5-C HOLD；生产仍 NO-GO |
| 18 | [P4R3 验货报告](./archive/18-p4r3-audit.md) | 对照 16/17、测试复跑、APK `.so`、artifact；撤销过早的 P5-C GO | 验货口径；GO 须能复算 |
| 19 | [P4R3 / P5-B 实施手册](./archive/19-p4r3-implementation-playbook.md) | 逐项怎么改、怎么跑设备、怎么写 artifact；P5-C 仅写准入 | timeout 已修；P5-C 施工见 21 |
| 20 | [P4 其余完善计划](./archive/20-p4-remaining-polish-plan.md) | remount、20/100 门禁、内部页 worker 口径；不开 P5 | Device A 20/100 已记入 artifact |
| 21 | [P5-C Fixture Pilot 施工手册](./archive/21-p5c-fixture-pilot-implementation-playbook.md) | 单来源 fixture Saga 到 observing；不改生产路由、不删 Legacy | 规格可用；早期验货看 23，收口结论看 25 |
| 22 | [P5-C Fixture Pilot 结果报告](./archive/22-p5c-result-report.md) | 记录单来源 Pilot 状态机、真实物理备份、WriteGuard 拦截与 Host 验证收据 | **GO 作废**；见 23 |
| 23 | [P5-C 验货报告](./archive/23-p5c-audit.md) | 对照 14/21/22、源码、artifact；撤销过早的 Device A / Host GO | **验货口径**（后续设备进度以 `archive/artifacts/p5c/` 为准） |
| 24 | [P5 收口、生产切换与 P6 AnkiWeb 计划](./archive/24-p5-remainder-and-p6-ankiweb-plan.md) | P5-C 收口票、P5-D/E 门禁；原 P6 段已取消 | §4 已收口（见 25）；P5-D D1 已收口（见 27）；§7 P6 **CANCELLED** |
| 25 | [P5-C 收口结果报告（对齐 24 §4）](./archive/25-p5c-closeout-result-report.md) | 24 §4 P5C-14…20 已落地对照，HOST CONDITIONAL GO + DEVICE RE-VERIFIED；继续 P5 USER CUTOVER NO-GO | 已收口（不覆写 23） |
| 26 | [P5-D Sprint D1 生产路由施工手册](./archive/26-p5d-production-routing-playbook.md) | 方案 B；cutover define 默认 false；Review/Import/due 按 source 分流 | 规格；收口以 27 为准 |
| 27 | [P5-D Sprint D1 验货](./archive/27-p5d-d1-audit.md) | 对照 24/26、源码、点名测试、Device A 评分；不写 P5-D GO | **D1 HOST+DEVICE CONDITIONAL GO**（仅 fixture）；P5-D GO NO |
| 29 | [P5-E Wave 1 生产解耦与架构约束报告](./archive/29-p5e-wave1-production-decoupling-report.md) | 断生产引用、提取 LegacyAnkiIdentifiers、建立 Forbidden Import CI 约束测试 | **Wave 1 已收口**；Wave 2–4 HOLD |

Phase 0–4 与 P5 收口的构建/真机证据（截图、日志、APK 采样）随归档保留在 [`archive/artifacts/`](./archive/artifacts/)，原文相对路径保持不变以方便回查。


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

只有 [第一阶段实施方案](./archive/01-phase-0-implementation-plan.md) 的全部硬门禁通过，才能开始第二阶段。

## 文档维护规则

- 总体架构变化先修改 `00-overall-migration-plan.md`（已归档；现行架构以 34 与 ADR 0036/0037/0041 为准）。
- 当前施工变化修改 [34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) 与 [`34-cutover-receipt.md`](./34-cutover-receipt.md)，不要改 archive 里的历史报告。
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
