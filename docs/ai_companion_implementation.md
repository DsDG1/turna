# AI 伴学实现说明

本文件记录桌面《AI伴学功能优化与丰富化实施计划》在客户端中的落地边界，供后续维护、验收和平台适配使用。核实日期：2026-09-27。

## 已落地的闭环

1. `LearningEvidence`（`lib/domain/ai_companion/learning_evidence.dart`）以 `lesson / mistake / srs / aiHint / aiChat / roleplay / diagnosisCheck` 七类来源统一承接课内表现、错题、SRS、AI 提示与 AI 会话；`KnowledgeMastery.fromEvidence()` 是透明的首版掌握度计算（时间衰减 + 迁移加成，clamp 到 0–1）。持久化为 Drift 的 `learning_evidence` / `knowledge_mastery` 两张表（`lib/data/course_database.dart`），经 `ILearningEvidenceRepository` 访问。
2. `LearnerProfileSnapshot`（`lib/domain/ai_companion/learner_profile_snapshot.dart`）定义结构化画像字段（语言、CEFR、目标、偏好解释风格、纠错强度）与 `toPromptBlock(maxItems, maxChars)` 最小化 Prompt 摘要，并带 `personalizationEnabled` 开关。**当前无生产调用点**，画像尚未接入任何 Prompt 组装路径。
3. `HintLadderController`（`lib/application/ai/companion/hint_ladder_controller.dart`）用 `HintLadderStage` 单调推进 `conceptCue → ruleCue → contrastCue → partialReveal → fullExplain → verify`；`canAdvance()` 把无答案时的上限卡在 `contrastCue`，模型无法自行越级，`verify` 为终态。
4. Drift 侧已建 `ai_sessions` / `ai_messages` / `learning_evidence` / `knowledge_mastery` / `diagnosis_snapshots` / `study_plans` / `study_plan_items` / `ai_notes` / `ai_request_metrics`（`lib/data/course_database.dart`），由 `lib/data/ai_companion_repository.dart` 读写。会话在 tutor chat 侧支持列出、保存、恢复（`openSavedSession`）、激活与删除（`lib/application/ai/ai_tutor_chat_session.dart`）；**重命名、纯文本导出、历史摘要裁剪尚未实现**。
5. `DeterministicDiagnosisEngine`（`lib/application/ai/companion/deterministic_diagnosis_engine.dart`）只基于证据给出弱项、置信度与趋势；`StudyPlanOrchestrator`（同目录）按 `availableMinutes` 生成计划，分钟数 clamp 在 5–30。
6. `AiGroundedResourceProvider`（`lib/application/ai/ai_grounded_resource_provider.dart`）把已有课程资源格式化为 Prompt 片段，并返回全部已加载资源 ID 供 Prompt 约束引用。**Top-K 检索与来源白名单校验未实现**；`AiCitation` 域模型（`lib/domain/ai_companion/ai_citation.dart`）目前只以原始 `citations_json` 形式落库，未经白名单过滤。
7. 知识笔记保留旧收藏的正文与时间（`SavedExplanation`，`lib/application/ai/ai_saved_explanations.dart`），`AiLearningNote` 另带 `AiNoteStatus`（stillLearning / understood / pendingVerification / mastered）与 `nextReviewAt`（Drift `ai_notes` 表）。`AiNoteStudyTools`（`lib/application/ai/companion/ai_note_study_tools.dart`）纯本地生成 2–3 道离线验证题与可编辑的 Anki TSV 草案，不调用模型；**该工具目前只在测试中被引用，尚未接入页面**。
8. 情景对话以 `AiTutorChatMode.roleplay` 形态存在于 tutor chat（`lib/application/ai/ai_tutor_chat_provider.dart`），页面提供 4 个场景 chip（用餐 / 问路 / 自我介绍 / 购物）。**A1 / A2 / B1 难度选择、纠错节奏、成功条件、结束复盘与 TTS 朗读均未实现**；`StudyPlanItemKind.roleplay` 只作为计划项的标签存在。

## 安全与可观测性

- API Key 不写入普通偏好、配置 JSON、日志、导出或缓存；旧明文 Key 验证迁移成功后才删除（`lib/service/secure_credential_store.dart` + `AiEngineConfigHolder` 的迁移阶段机）。
- 学习者敏感缓存仅存内存；设置页提供「清除凭据」（`lib/views/ai/ai_api_config_page.dart`）。**独立的「清除 AI 学习数据」入口未实现**。
- 请求带功能名、Prompt 版本、超时（`ai_engine.dart` 默认 60s / 120s）与一次安全重试（`ai_http_client.dart`：服务端以 400 拒绝 `json_schema` 时降级为 `json_object` 重发一次，仅在 `StrictSchemaMode.auto` 下触发）。**幂等键未实现**。每次请求写入 `ai_request_metrics`，记录延迟、Token、缓存命中与结果。
- 请求节流由 `CompanionRateLimiter`（`lib/application/ai/companion_rate_limiter.dart`）做本地最小间隔去抖，防连点烧 token。**每日软 / 硬预算未实现**。

## 平台边界

- Android / iOS / macOS / Windows / Linux 使用 `flutter_secure_storage` 可用实现；Web 及缺少原生安全存储插件的平台仅会话内保留 Key，并在设置页提示。
- 当前 Web 启动路径本身不提供 Drift 课程库，因此课程检索和会话持久化按现有平台能力降级。
- 语音转文字、OCR 和图片场景任务仍属于计划中的后续平台试验；文本伴学和 TTS 不依赖这些能力。
- 不提供没有可靠评分模型支撑的口音或音素分数。

## 自动化验收

- AI 专项测试覆盖安全迁移（`test/application/ai/engine/ai_credential_migration_test.dart`）、引擎与 HTTP 层（`ai_engine_test.dart` / `ai_http_client_test.dart` / `ai_engine_config_test.dart`）、伴学仓储（`ai_companion_repository_test.dart`）、伴学域逻辑含提示阶梯（`test/application/ai/companion_unit_test.dart`）、会话恢复与流式（`ai_tutor_chat_session_test.dart` / `ai_tutor_chat_streaming_test.dart`）、资源接地（`ai_grounded_resource_language_test.dart`）与 Prompt 构造（`ai_prompts_and_presets_test.dart`）。
- 数据库 Schema 当前为 v27（`lib/data/course_database.dart` 的 `kSchemaVersion`）；`test/data/schema_migration_test.dart` 覆盖逐版本升级，以及用更高版本库验证「拒绝降级」。
