# 官方 Anki Core 迁移文档索引

> 状态：Phase 0 + Phase 1 **TECHNICAL CONDITIONAL GO**；Phase 2 + Phase 3 **TECHNICAL NO-GO**；Phase 4 **ENTRY NO-GO**
> 首发目标：Android arm64  
> 总原则：官方 Anki Collection 是唯一 Anki 事实源，Turna 只维护课程投影  
> 执行记录：[02-phase-0-result-report.md](./02-phase-0-result-report.md)

## 文档列表

| 顺序 | 文档 | 用途 | 当前状态 |
|---|---|---|---|
| 00 | [总体迁移方案](./00-overall-migration-plan.md) | 目标架构、数据所有权、渲染、调度、Legacy 迁移和完整阶段划分 | 提案 |
| 01 | [第一阶段实施方案](./01-phase-0-implementation-plan.md) | Android arm64 技术 Spike 的逐任务施工、验收和 Go/No-Go 门禁 | 已收口 |
| 02 | [第一阶段结果报告](./02-phase-0-result-report.md) | 基线、命令、指标、Conditional Go | 已决策 |
| 03 | [第二阶段实施方案](./03-phase-1-implementation-plan.md) | 稳定 Engine、contract v1、官方导入 Saga、恢复与生产入口门禁 | 已实施（技术修补后见 06） |
| 04 | [第二阶段结果报告](./04-phase-1-result-report.md) | 基线、命令、指标、Conditional Go | 已降级；以 06 为准 |
| 05 | [Phase 0 + Phase 1 技术修补计划](./05-phase-0-phase-1-technical-remediation-plan.md) | 排除 License 后的 ABI、Engine、Saga、Android、CI 与文档联合收口 | 已实施 |
| 06 | [Phase 0 + Phase 1 技术修补结果](./06-phase-0-phase-1-technical-remediation-result.md) | Host 真实 FFI、Saga、backup、CI 与技术决策 | TECHNICAL CONDITIONAL GO |
| 07 | [Phase 2 官方原卡渲染实施计划](./07-phase-2-implementation-plan.md) | P1 遗留修补、官方 render contract、安全 Reviewer、media origin、AV/TTS、Typed Answer、MathJax 与验收 | 已实施施工；见 08 |
| 08 | [Phase 2 结果报告](./08-phase-2-result-report.md) | Host/Dart/Android 产物、未测项和 Go/No-Go | IMPLEMENTATION IN PROGRESS；TECHNICAL NO-GO |
| P2FIX | [Phase 2 官方原卡渲染修补计划](./p2fix.md) | 修复媒体 base/IRI/Range、MathJax 打包、真实 AV、脚本隔离、生命周期与 Android 验收 | 施工中；TECHNICAL ACCEPTANCE NO-GO |
| 09 | [P2 必要补齐 + Phase 3 课程投影实施计划](./09-p2-entry-remediation-and-phase-3-plan.md) | 先关闭 P3 开工所需的 P2 硬阻断，再实施 contract 1.2、字段 mapping、可重建课程投影和设备验收 | HOST CONSTRUCTION GO；STRICT ENTRY NO-GO |
| P3FIX | [Phase 3 官方 Anki 课程投影修补计划](./p3fix.md) | 修复 Android contract 产物、source 分页一致性、job/recovery、mapping wizard、Interaction 和 CourseProvider 端到端接入 | P3 FIX CONSTRUCTION GO；TECHNICAL ACCEPTANCE NO-GO |
| 10 | [Phase 3 修补结果报告](./10-phase-3-fix-result-report.md) | 记录 P3 Host 施工、Android 产物、测试证据和未通过的设备硬门禁 | P3 TECHNICAL/PRODUCTION NO-GO |
| 11 | [P3 阻断修补 + Phase 4 官方 Scheduler 实施计划](./11-p3-remediation-and-phase-4-scheduler-plan.md) | 先关闭 P3 生产接线、job、课程推进、容量和 mapping 阻断，再正式化官方 Scheduler contract、session、UI 与设备验收 | P3 REMEDIATION REQUIRED；P4 ENTRY NO-GO |

## 阶段命名

为了避免“第一阶段”和“Phase 1”产生歧义，本目录统一采用以下命名：

```text
第一阶段 = Phase 0：技术 Spike
第二阶段 = Phase 1：稳定 Engine 与官方导入
第三阶段 = Phase 2：官方原卡渲染
第四阶段 = Phase 3：课程投影
第五阶段 = Phase 4：官方 Scheduler
第六阶段 = Phase 5：Legacy 迁移与删除
第七阶段 = Phase 6：可选 AnkiWeb Sync
```

第一阶段不修改生产导入默认行为，也不删除 Legacy 代码。它只回答以下问题：

1. 官方 `rslib` 能否在当前 Android/OHOS Flutter 分支的构建环境下编译为 arm64 `.so`？
2. Flutter release APK 能否稳定加载它？
3. 能否完成 open、import、render、queue、answer、undo 的最小闭环？
4. Unicode、Reverse、Cloze 和媒体是否能按官方语义工作？
5. APK 体积、冷启动、内存和大牌组性能是否可接受？
6. AGPL 与源码分发是否存在阻止产品发布的障碍？

只有 [第一阶段实施方案](./01-phase-0-implementation-plan.md) 的全部硬门禁通过，才能开始第二阶段。

## 文档维护规则

- 总体架构变化先修改 `00-overall-migration-plan.md`。
- 当前阶段的施工变化修改对应阶段文档。
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
