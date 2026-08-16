# 官方 Anki Core 迁移文档索引

> 状态：Phase 0 **Conditional Go**（`spike/official-anki-core-android`）  
> 首发目标：Android arm64  
> 总原则：官方 Anki Collection 是唯一 Anki 事实源，Turna 只维护课程投影  
> 执行记录：[02-phase-0-result-report.md](./02-phase-0-result-report.md)

## 文档列表

| 顺序 | 文档 | 用途 | 当前状态 |
|---|---|---|---|
| 00 | [总体迁移方案](./00-overall-migration-plan.md) | 目标架构、数据所有权、渲染、调度、Legacy 迁移和完整阶段划分 | 提案 |
| 01 | [第一阶段实施方案](./01-phase-0-implementation-plan.md) | Android arm64 技术 Spike 的逐任务施工、验收和 Go/No-Go 门禁 | 已收口 |
| 02 | [第一阶段结果报告](./02-phase-0-result-report.md) | 基线、命令、指标、Conditional Go | 已决策 |

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

