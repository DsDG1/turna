# AI 伴学实现说明

本文件记录桌面《AI伴学功能优化与丰富化实施计划》在客户端中的落地边界，供后续维护、验收和平台适配使用。核实日期：2026-09-27（测试冗余清理批次后复核）。

## 2026-09-27 退役记录

「伴学持久化与离线推理簇」经审计确认在 lib/ 内**零生产 import**（仅被彼此与测试引用），已整体删除（19 个文件 1,834 行，见 `test/BASELINE.md` 2026-09-27「测试冗余清理批次」收据）：

- `AiCompanionRepository`（`lib/data/ai_companion_repository.dart`）——ai_sessions 等 9 张表的唯一读写方，从未被任何生产路径接线；
- `lib/application/ai/companion/`（`HintLadderController` / `DeterministicDiagnosisEngine` / `StudyPlanOrchestrator` / `AiNoteStudyTools`）——均只被测试引用；
- `lib/domain/ai_companion/` 全部 8 个域模型（`LearningEvidence`、`KnowledgeMastery`、`LearnerProfileSnapshot`、`AiCitation`、`AiLearningNote`、`AiRequestMetric`、`DiagnosisSnapshot`、`StudyPlan`）与 `lib/domain/repositories/` 的 6 个伴学仓储接口。

`course_database.dart` 中 `ai_sessions` / `ai_messages` / `learning_evidence` / `knowledge_mastery` / `diagnosis_snapshots` / `study_plans` / `study_plan_items` / `ai_notes` / `ai_request_metrics` 的建表 DDL 按 schema 稳定性原则保留，但**当前无任何 Dart 代码读写**；删表属 schema 迁移决策，不在代码清理批次内。

## 已落地的闭环

1. 学习者知识笔记：`AiSavedExplanationsStore`（`lib/application/ai/ai_saved_explanations.dart`）保存/检索/删除收藏正文与时间，随 hint 流程写入。
2. `AiGroundedResourceProvider`（`lib/application/ai/ai_grounded_resource_provider.dart`）把已有课程资源格式化为 Prompt 片段，并返回全部已加载资源 ID 供 Prompt 约束引用。**Top-K 检索与来源白名单校验未实现**。
3. tutor chat 会话为 JSON 序列化的内存模型（`lib/application/ai/ai_tutor_chat_session.dart`）；角色扮演以 `AiTutorChatMode.roleplay` 形态存在（`lib/application/ai/ai_tutor_chat_provider.dart`），页面提供 4 个场景 chip（用餐 / 问路 / 自我介绍 / 购物）。**A1 / A2 / B1 难度选择、纠错节奏、成功条件、结束复盘与 TTS 朗读均未实现；DB 会话持久化从未接线**（原计划的持久化路径即上面退役的仓储）。

## 安全与可观测性

- API Key 不写入普通偏好、配置 JSON、日志、导出或缓存；旧明文 Key 验证迁移成功后才删除（`lib/service/secure_credential_store.dart` + `AiEngineConfigHolder` 的迁移阶段机）。
- 学习者敏感缓存仅存内存；设置页提供「清除凭据」（`lib/views/ai/ai_api_config_page.dart`）。**独立的「清除 AI 学习数据」入口未实现**。
- 请求带功能名、Prompt 版本、超时（`ai_engine.dart` 默认 60s / 120s）与一次安全重试（`ai_http_client.dart`：服务端以 400 拒绝 `json_schema` 时降级为 `json_object` 重发一次，仅在 `StrictSchemaMode.auto` 下触发）。**幂等键未实现**。请求指标采集（`ai_request_metrics` 表）原经已删除的伴学仓储写入，**随其退役当前无写入方**。
- 请求节流由 `CompanionRateLimiter`（`lib/application/ai/companion_rate_limiter.dart`）做本地最小间隔去抖，防连点烧 token。**每日软 / 硬预算未实现**。

## 平台边界

- Android / iOS / macOS / Windows / Linux 使用 `flutter_secure_storage` 可用实现；Web 及缺少原生安全存储插件的平台仅会话内保留 Key，并在设置页提示。
- 当前 Web 启动路径本身不提供 Drift 课程库，因此课程检索按现有平台能力降级。
- 语音转文字、OCR 和图片场景任务仍属于计划中的后续平台试验；文本伴学和 TTS 不依赖这些能力。
- 不提供没有可靠评分模型支撑的口音或音素分数。

## 自动化验收

- AI 专项测试覆盖安全迁移（`test/application/ai/engine/ai_credential_migration_test.dart`）、引擎与 HTTP 层（`ai_engine_test.dart` / `ai_http_client_test.dart` / `ai_engine_config_test.dart`）、伴学单元（提示/取消/过期、tutor chat、词典富化、限流：`ai_hint_provider_test.dart` / `companion_unit_test.dart`）、会话与流式（`ai_tutor_chat_session_test.dart` / `ai_tutor_chat_streaming_test.dart`）、资源接地（`ai_grounded_resource_language_test.dart`）与 Prompt 构造（`ai_prompts_and_presets_test.dart`）。
- 数据库 Schema 当前为 v27（`lib/data/course_database.dart` 的 `kSchemaVersion`）；`test/data/schema_migration_test.dart` 覆盖逐版本升级，以及用更高版本库验证「拒绝降级」。
