# 08. AI 引擎、教材导入与 GUI 编辑器

> 路径：`lib/application/ai/`（应用层 AI 能力）、`tool/gui/`（PySide6 桌面编辑器）、`tool/*.py`（Python 工具链）

Varnamala 内置一套完整的 AI 能力用于**课程生成、内容校对、学习辅助**。所有 AI 调用通过统一的 [`AiEngine`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_engine.dart) choke point，**不在运行时**依赖任何云端课程生成（仅在作者工具中调用）。

> 📘 **GUI 编辑器详情**：本文侧重运行时 AI 与应用层 Provider；GUI 桌面编辑器（CourseAdapter / ai_pipeline / ai_phased / ai_fixer / ai_stream / ai_usage / ai_cache / 精修流水线 / 课程工坊 / Git 协作 / 测试套件 / PyInstaller 打包）的完整架构请见 [12. Varnamala GUI 课程编辑器](./12-tool-gui.md)。

---

## 8.1 AI 引擎架构

### 8.1.1 分层结构

```
┌─────────────────────────────────────────────┐
│  UI 层（ai_hub_page / chat_bubble / sheet） │
├─────────────────────────────────────────────┤
│  Feature Providers（course / wish / hint）  │  ← 业务逻辑
├─────────────────────────────────────────────┤
│  AiCourseService（编排）                     │  ← Prompt 拼装 + 结果解析
├─────────────────────────────────────────────┤
│  AiEngine（choke point）                     │  ← HTTP + Cache + Stream + Cancel
├─────────────────────────────────────────────┤
│  AiHttpClient / AiCache（基础设施）          │
├─────────────────────────────────────────────┤
│  Provider Preset（OpenAI / DeepSeek / 等）   │
└─────────────────────────────────────────────┘
```

### 8.1.2 关键模块

| 文件 | 职责 |
|---|---|
| [`ai_engine.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_engine.dart) | AI 引擎 choke point：`chat()` / `requestJson()` / `probeConnection()` |
| [`ai_http_client.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_http_client.dart) | HTTP 客户端：流式响应、取消、json_schema fallback |
| [`ai_cache.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_cache.dart) | 内存/磁盘缓存，key = `sha256(model \| messages \| responseFormat)` |
| [`ai_cache_disk_io.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_cache_disk_io.dart) | 磁盘 I/O 实现（移动端） |
| [`ai_cache_disk_web.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_cache_disk_web.dart) | Web 平台实现 |
| [`ai_cancel_token.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_cancel_token.dart) | 流式调用的取消令牌 |
| [`ai_engine_config.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_engine_config.dart) | 引擎配置（API key / base URL / 模型 / cache 开关） |
| [`ai_engine_config_holder.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_engine_config_holder.dart) | UI 可见的 ChangeNotifier 配置 |
| [`ai_engine_result.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_engine_result.dart) | 统一返回结构 |
| [`ai_provider_preset.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_provider_preset.dart) | OpenAI / DeepSeek / 自定义 endpoint 预设 |
| [`ai_recent_tasks_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_recent_tasks_provider.dart) | 最近 AI 任务列表 |
| [`ai_stream_chunk.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_stream_chunk.dart) | 流式响应分片 |

### 8.1.3 AiEngine 公开 API

```dart
class AiEngine {
  /// 纯文本对话（alignment / explanation / hint / tutor chat）
  Future<AiEngineResult> chat({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.5,
    void Function(String delta)? onChunk,    // 流式回调
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  });

  /// JSON 模式（course / lesson / transform / extract）
  Future<AiEngineResult> requestJson({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    required Map<String, dynamic> jsonSchema,
    void Function(String delta)? onChunk,
    AiCancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 90),
  });

  /// 测试连接
  Future<AiEngineResult> probeConnection({required AiEngineConfig config});
}
```

**关键设计**：
- `cacheEnabled` 时 cache 命中直接返回；stream 调用时缓存内容作为单个 fragment 推送
- cache key **不包含** API key，避免泄露
- domain 方法（生成 / 抽取 / 转换）由 [`AiCourseService`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_course_service.dart) 提供，引擎本身不感知课程 schema

---

## 8.2 AI 课程生成

### 8.2.1 Feature Providers

| Provider | 职责 |
|---|---|
| [`AiCourseProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_course_provider.dart) | 普通模式 + Genre 批量生成 |
| [`AiWishProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_wish_provider.dart) | "许愿模式"（多轮对话 + 附件） |
| [`AiGroundedResourceProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_grounded_resource_provider.dart) | 资源合规校验（确保 wordId / expressionId / grammarPointId 引用真实存在） |
| [`AiLessonHelperProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_lesson_helper_provider.dart) | 课内 AI 深度辅导 |
| [`AiHintProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_hint_provider.dart) | 课内 AI 提示（chat 风格） |

### 8.2.2 普通模式流程

```
用户在 AiHubPage 配置：
  - 语言 / CEFR 等级 / 单元数 / 主题 / Genre 标签
  ↓
AiCourseProvider.generateCourse(...)
  ↓
AiCourseService.buildPrompt() + AiPromptBuilder
  ↓
AiEngine.requestJson(jsonSchema: CourseSchema)
  ↓
解析 + 校验：
  - CourseValidator（id 唯一、引用完整、schema 合规）
  - AiGroundedResourceProvider（wordId 引用真实词汇）
  - AI Fixer（自动修复 id 冲突、引用断裂）
  ↓
Preview → 用户编辑 → 导入
```

### 8.2.3 许愿模式流程

```
多轮对话 + 附件上传（图片 / PDF / Word / 文本）
  ↓
AiWishProvider 每轮 chat() → 累积对话历史
  ↓
用户点 "我感觉差不多了"
  ↓
AiEngine.requestJson() 输出完整课程 JSON + 解释
  ↓
Preview → 导入
```

### 8.2.4 Genre 标签

[`ai_genre.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_genre.dart) — 在主题中插入 `[intro]`/`[practice]`/`[listening]`/`[reading]`/`[review]`/`[mastery]` 标签，一次生成多种模板的课。

### 8.2.5 护栏

| 护栏 | 实现 |
|---|---|
| id 全局唯一 | id 只读；rename 只改 name；validate 兜底查重；导入冲突弹窗 |
| scale ceiling | 复用 `course_cli.py` 的 `MAX_UNITS_PER_SECTION=60` / `MAX_LESSONS_PER_UNIT=40` |
| 引用完整性 | `wordId`/`expressionId`/`grammarPointId` 从已加载资源下拉选 |
| 保存前校验 | `validate --format json` 失败 → 禁用保存 + 高亮问题节点 |
| 密钥不落盘 | API key / base URL / model **仅存内存**；附件用临时文件 |

---

## 8.3 AI 提示与辅导

### 8.3.1 课程内 AI 提示（[`AiHintProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_hint_provider.dart)）

`HintSheet` 显示当前 interaction 的上下文 + AI 生成的提示。`HintGenre` 决定提示类型（[`hint_genres.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/hint_genres.dart)）。

### 8.3.2 深度辅导员（[`AiLessonHelperProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_lesson_helper_provider.dart)）

基于近期错题 + 当前 lesson 进度的多轮对话辅导。

### 8.3.3 个性化 SRS 辅导（[`SrsTutorProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/srs_tutor_provider.dart)）

聚合 MistakeProvider / SrsProvider / SrsStateDao.recentReviews() → 构造 AI 上下文 → AI 给出个性化建议。

---

## 8.4 教材导入

[`lib/application/ai/textbook/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook) — 从外部教材（PDF / Word / 图片 / 文本）多阶段提取并导入。

### 8.4.1 模块

| 文件 | 职责 |
|---|---|
| [`textbook_import_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/textbook_import_provider.dart) | 导入任务状态机 |
| [`import_plan.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/import_plan.dart) | 导入计划结构 |
| [`knowledge_schema.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/knowledge_schema.dart) | 抽取结果 schema |
| [`knowledge_prompt.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/knowledge_prompt.dart) | 抽取 prompt |
| [`knowledge_merger.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/knowledge_merger.dart) | 跨章节去重合并 |
| [`markdown_chopper.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/markdown_chopper.dart) | 大 Markdown 自动分段 |
| [`textbook_to_course.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/textbook_to_course.dart) | 知识条目 → 课程 JSON |
| [`textbook_presets.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/textbook_presets.dart) | 预设语言对 / CEFR / 题型偏好 |

### 8.4.2 五阶段向导

```
1. 选材    拖入 PDF/Word/图片/文本 → 抽取可读文本（PDF → PyPDF2；Word → python-docx；图片 → base64 → vision API）
2. 提取    AI 逐章识别词汇/表达/语法点/对话/练习 → KnowledgeExtractor 按 KnowledgeSchema 输出
3. 合并    KnowledgeMerger 跨章节去重，处理同一词汇的多次出现 / 释义冲突 / 例句归并
4. 预览    BulkImportPreviewPanel 展示拟导入条目，支持逐条确认/编辑/排除，按资源类型分 tab
5. 导入    写入 vocab.json / expressions.json / grammar_points.json，并生成对应 lesson
```

### 8.4.3 导入策略

| 策略 | 新建 | 冲突 | 缺失 |
|---|---|---|---|
| 保守 | 跳过 | 跳过 | 跳过 |
| 激进 | 新建 | 覆盖 | 补充 |
| 交互式 | 确认 | 确认 | 确认 |

---

## 8.5 PySide6 GUI 编辑器

[`tool/gui/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/) — 基于 PySide6 的桌面可视化编辑器。**JSON 仍是唯一真理源**。

### 8.5.1 运行

```bash
pip install PySide6
python tool/gui/src/main.py
```

### 8.5.2 打包

```bash
pip install pyinstaller
python tool/gui/build_gui.py              # onefile → dist/varnamala-gui.exe
python tool/gui/build_gui.py --onedir     # onedir
```

### 8.5.3 两种编辑视图

1. **教师视图**：线性三层次（课 → 环节 → 步骤 → 题目）
   - `LessonWizard` / `QuestionCards` / `TemplateEditors` / `VocabTable` / `ErrorMapper`
2. **传统视图**：
   - `CourseTree` / `LessonEditor` / `ResourceEditor` / `DetailPanel`

### 8.5.4 工作区（Workshop）窗口

独立于课程树的 Workshop 窗口（`workshop_window.py`），与 App Shell（`app.py`）松耦合，集中管理：

- 教材导入任务列表
- AI 批量生成队列
- 跨 section 内容迁移
- 操作日志查看

支持多任务并行，后台执行不阻塞主编辑器。

### 8.5.5 后端模块

| 模块 | 职责 |
|---|---|
| `backend/ai_generator.py` | 普通 + 许愿模式生成调度 |
| `backend/ai_stream.py` | SSE 流式响应处理 |
| `backend/ai_fixer.py` | 生成后自动修复 id 冲突 / 引用断裂 |
| `backend/ai_prompt_library.py` | 可复用 prompt 模板库 |
| `backend/ai_genre.py` | Genre 标签映射 |
| `backend/ai_presets.py` | 常用模型 / 参数预设 |
| `backend/ai_usage.py` | Token 用量追踪 |

### 8.5.6 测试

```
tool/gui/tests/
├── test_ai_bench.py
├── test_ai_cache.py
├── test_ai_fixer.py
├── test_ai_phased.py
├── test_ai_presets.py
├── test_ai_scope.py
├── test_ai_stream.py
├── test_ai_summary.py
├── test_ai_usage.py
├── test_app.py
├── test_diff_view.py
├── test_focus_ring.py
├── test_git_skill.py
├── test_goal_e3b1.py
├── test_goal_e3b2.py
├── test_goal_e3b3.py
├── test_intent_llm.py
├── test_job_tray.py
├── test_labels.py
├── test_policy.py
├── test_proactive.py
├── test_save_brief.py
├── test_save_host.py
├── test_settings.py
├── test_teacher.py
├── test_telemetry.py
├── test_theme.py
├── test_ui_guard.py
└── usability_smoke.py
```

---

## 8.6 Anki 导入

[`lib/application/anki/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki) — Anki `.apkg` / `.colpkg` 导入。

| 文件 | 职责 |
|---|---|
| [`anki_importer.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_importer.dart) | 主入口 |
| [`anki_card_adapter.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_card_adapter.dart) | Anki note → Interaction 转换 |
| [`anki_card_enhancer.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_card_enhancer.dart) | AI 增强（可选） |
| [`anki_deck_assembler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_deck_assembler.dart) | deck 装组 |
| [`anki_deck_manager.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_deck_manager.dart) | 多 deck 管理 |
| [`anki_models.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_models.dart) | 数据模型 |
| [`anki_notetype_ai.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_notetype_ai.dart) | AI notetype 映射 |
| [`anki_organization_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_organization_resolver.dart) | 子 deck → section 解析 |
| [`anki_review_assembler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_review_assembler.dart) | 复习会话拼装 |
| [`anki_sample_deck.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_sample_deck.dart) | 示例 deck |
| [`anki_srs_migrator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_srs_migrator.dart) | Anki SRS 状态 → Varnamala SRS 迁移 |
| [`anki_template_renderer.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/anki/anki_template_renderer.dart) | 模板渲染 |

**AnkiCard Interaction 变体**：见 [`domain/course/interaction.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/interaction.dart#L163) — front/back 通用，无语言语义。