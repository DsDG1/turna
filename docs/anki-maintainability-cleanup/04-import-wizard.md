# 导入向导 Controller 化

> 状态：已完成（2026-08-25）
> 历史阶段：原 Wave 4
> 相关文档：[总入口](README.md) · [验收凭据](05-verification-receipt.md)

## 结果

`AnkiImportPage` 已从超过 3300 行、同时拥有视图状态和导入编排的巨型 Widget，收敛为约 553 行的页面 shell。业务状态由 `AnkiImportController` 持有，Legacy 与 Official-first 分别由独立 flow 执行，步骤 Widget 只接收 model 和 callbacks。

```text
AnkiImportPage
  ↓ intent / state rendering
AnkiImportController
  ├─ LegacyAnkiImportFlow
  └─ OfficialFirstAnkiImportFlow
          ↓
  existing executors and services
```

本轮只移动状态所有权和编排，没有重写 importer、projection、mapping 算法或页面视觉。

## 原始问题

旧 `AnkiImportPage` 同时管理文件选择、临时目录、Legacy parse/preview/collision/import、Official-first schema/mapping/projection/publish、AI 识别、依赖解析、完成后的 catalog/order/navigation，以及全部步骤 UI。

流程状态通过大量 nullable 字段和约 50 处 `setState` 表达。Official/Legacy 路径依靠 `_officialSourceId != null` 等条件推断当前模式，异步回调、重复提交和页面 dispose 很难统一处理。

## 设计决策

### 状态模型

`AnkiImportWizardState` 是 sealed 状态，覆盖：

- Selecting：没有活动 collection、service 或临时目录；
- Parsing：持有冻结的 plan 和 path；
- Previewing：只持有一种 preview variant；
- Committing：提交 single-flight，重复 intent 不产生第二次写入；
- Completed：持有统一 summary；
- Failed：携带结构化 failure 和可返回状态。

Preview 也使用 sealed variant：`LegacyAnkiImportPreviewModel` 与 `OfficialAnkiImportPreviewModel` 不能同时存在。Official preview 不携带 Legacy collision strategy；Legacy preview 不持有 Official projection service。

pick-time execution plan 在整个 operation 中冻结。commit 不重新调用 planner，避免 feature flag 或依赖状态变化让预览和落盘走不同路径。

### Controller intent

Controller 对页面暴露面向用户意图的方法，包括：

- 选择文件、按路径继续和加载 sample；
- 编辑 Legacy mapping、调用 AI 识别；
- 确认或跳过 Official notetype mapping；
- commit、cancel、reset 和异步 dispose。

同一时间只允许一个长操作。每次 pick/reset 都增加 operation generation；parse、AI、projection 等异步回调在提交状态前检查 token，过期结果直接丢弃。

### Flow 边界

`LegacyAnkiImportFlow` 负责：

- parse/sample；
- recognition 和 organization preview；
- collision inspection；
- 调用 Legacy executor；
- 返回统一 completion summary。

`OfficialFirstAnkiImportFlow` 负责：

- `importThenPreview`；
- schema suggestion、confirm 和 skip；
- project/publish；
- 返回统一 completion summary。

Official flow 不访问 Legacy NoteStore/SRS writer；Legacy flow 不持有 Official projection service。两个 flow 都不直接导航。

### 依赖和 UI 边界

controller 依赖通过 `AnkiImportDependencies` 显式注入，包括 picker、planner、flow/executor factory、数据库/provider gateway、settings 和必要测试缝。本轮不更换项目的 Provider/GetIt 全局方案，但 Widget 不再现场拼装业务依赖。

`AnkiImportPage` 只保留 Scaffold、AppBar、step rendering、mapping route/dialog 和完成导航。拆出的 step Widget 不 import DAO、CourseDatabase、engine implementation 或 GetIt。

### 清理与完成导航

- 临时 media directory 由创建它的 flow/controller operation 拥有；
- cancel、reset 和 dispose 只清理当前 operation 的资源；
- stale operation 不能删除新 operation 的目录；
- commit 失败保留可重试所需的 active collection，取消或 dispose 时再释放；
- 完成后释放 collection 大对象；
- catalog reload 和 order persistence 由 completion coordinator 共用；
- “完成”不切 active course，“立即学习”才切换；查看牌组维持既有高亮语义。

## 已实现结构

`lib/application/anki/import_wizard/` 包含：

- `anki_import_controller.dart`：ChangeNotifier、single-flight、operation generation 和资源清理；
- `anki_import_wizard_state.dart`：sealed state 和 preview variants；
- `anki_import_dependencies.dart`：显式依赖与 planner 测试缝；
- `legacy_anki_import_flow.dart`；
- `official_first_anki_import_flow.dart`；
- `anki_import_completion_coordinator.dart`；
- mapping 和 view helper。

`lib/views/anki/import_wizard/` 包含共享 step widgets、Legacy/Official preview、映射编辑器和完成步骤。`anki_import_screen.dart` 只负责 shell、对话框、route intent 和完成导航。

## 不变量和失败语义

- 一个 controller operation 只能有一个 active flow；
- preview plan 和 commit plan 必须是同一冻结实例/语义；
- repeated commit 是 no-op，不触发第二次 executor；
- stale callback 不覆盖新选择或 reset 后状态；
- dispose 后不 notify UI；
- flag-off/fail-closed 的 Official-first 失败产生零 Legacy 写；
- cancel、failure 和 dispose 不泄漏临时目录或 collection；
- 页面不直接访问 importer、projection、DAO 或 engine；
- 业务步骤由 controller state 驱动，局部动画等纯 UI 状态才可使用 `setState`。

## 规模门禁

当前门禁继续作为防回流约束：

- `anki_import_screen.dart` 不超过 700 行；
- 单个 step Widget 不超过 500 行；
- controller 不超过 600 行；
- Legacy/Official flow 各不超过 500 行；
- 页面不包含 `getIt<`、data DAO import 或 importer/projection 直接调用。

行数不是设计目标本身，但用于防止把同一巨石简单改名或搬到另一个文件。

## 测试与验收

controller 和页面测试覆盖：

- picker cancel、非法扩展名和 sample；
- pick-time plan 全程冻结；
- Legacy parse、preview、AI mapping、collision 和 commit；
- Official preview、mapping、skip、project 和 publish；
- Legacy/Official preview variant 互斥；
- feature flag fail-closed 且零 Legacy 写；
- repeated commit single-flight；
- hanging parse 等 stale callback 场景；
- cancel、dispose 和 failure 的资源清理；
- completion course order；
- “完成”不切课、“立即学习”切课；
- 窄屏和放大文字下的 widget/golden 回归；
- 页面依赖和代码规模架构守卫。

精确命令和最终通过结果见[验收凭据](05-verification-receipt.md)。

## 剩余债务

- 100/5K 卡导入的 preview、commit 时间与内存趋势仍需真机/大样本采样；
- 全局 Provider/GetIt 方案保持不变，未来如调整 DI 应独立立项；
- projection service 内部职责拆分不属于本次 controller 化；
- 导入页视觉和 mapping 算法的产品改版应与状态治理分开进行。
