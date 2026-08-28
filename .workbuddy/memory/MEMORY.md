# MEMORY.md — Turna 项目长期约定

## 文档可信度：会漂移，勿全信

`docs/project-guide.md` 自称单一真理源，但实测与代码有系统性漂移。接手判断或回答
"某功能是否还在"时，**一律以代码为准**，不要引用文档数字。

**判读方法（已验证有效）**：
1. 类名 grep 出 **0 引用 = 已删除**。若只剩注释/字符串/dart doc 提及，即已删的历史痕迹。
2. 大重构只记录在 `docs/official-anki-migration/NN-*-plan.md` 这类施工文档的
   **§10「施工实录：与计划的差异」**里，主文档通常没同步。想了解现状先读这里。
3. **代码在 ≠ 功能在**：删除重构常留僵尸机制（如回调零传入方、缓存读方法零调用点）。
   核查要顺着调用链找消费者，不能只看实现是否还在。

## Anki 子系统现状（2026-08-28 核对）

- Legacy 复刻层已于 2026-08-27 由 doc 35 L0–L3 物理删除，**`lib/application/anki/` 已清空**
  （guard test 有终态断言）。只剩 `anki_import/` / `anki_practice/` / `anki_official/`。
- 导入执行计划三态：`officialFirst` / `failClosed` / `unsupported`，无 legacy 兜底。
- 官方保真渲染仍活跃：`official_formal_review_coordinator` →
  `study_session/anki_review_content.dart` → `official_template_webview_body` →
  `AnkiHtmlCardView`（全项目唯一 WebView 使用点）。
- `ankiHtmlCard` 语义分裂：Official 复习用它渲染 HTML；lesson 体/错题重放里的存量卡
  走 `anki_html_card_retired_renderer` 降级为占位卡。改这块时注意区分两条路径。
- 已知失活：「智能去解密」pre-render 缓存（`onCaptured` 零传入方，缓存永不写入）。
  2026-08-28 全量核查确认这是**四环死链**：`onCaptured` 零传入 →
  `upsertPrerenderedFace`(anki_note_dao:727) 生产零调用 → `prerenderCacheStats`/
  `deletePrerenderedByPrefix` 永远作用于空表 → `ankiPreRenderEnabled`
  (settings_provider:33) 有 prefs 读写和设置页 UI，但**不控制任何行为分支**。

## 垃圾代码家底（2026-08-28 全量审计）

报告：`.workbuddy/reports/code-junk-audit-2026-08-28.md`。基线数据，供后续清理对照。

- **lint 层极干净**：`flutter analyze` 全项目只 4 条 `unnecessary_const`（均在 test）。
  0 TODO、0 注释代码块、0 `avoid_print` 违规、0 硬编码密钥。别再花时间找这类。
- **9 个完全孤儿 dart 文件**（1,252 行）：`ai_companion_feature_flags`、
  `companion_prompt_registry`、`course_knowledge_retriever`、`learner_profile_assembler`、
  `courses/languages/languages`、`textbook_conflict_preview`、`textbook_review_panel`、
  `onboarding_screen`、`turna_toast`。其中 `AiCompanionFeatureFlags` 整类死透（零实例化）。
- **另 10 个「仅 test 引用」文件**（1,397 行），最大 `data/ai_companion_repository.dart`(779 行)。
- **已验证的僵尸符号**：`onSourceRefreshNeeded`(official_formal_due_repository:197，与
  onCaptured 同构)、`courseOf`/`pathsOf`/`activeSectionIds`(official_anki_course_entry)、
  `CanonicalCard`、`PresentationCandidate`、`AnkiImportCompletion` typedef、
  flag 字段 `legacyMirror`/`diagnostics`/`courseGradesScheduler`（后两者环境变量无效）。
- **`lib/core/extensions.dart` 是杂物抽屉**：16 个 extension 里 17 个死成员，建议整文件立项。
- **死资源**：`assets/images/turna/` 5 个 PNG（2.52 MB，进包）；8 个 `turna_*.jpg` 是
  `tool/convert_mascot_to_png.py` 输入源，应移出 assets 而非删。
- **`debugPrint` 110 处绕开日志管线**：`log_capture.dart:81` 只监听 `logger.*`，
  所以 debugPrint 不会进用户导出的诊断日志。这是诊断盲区，不是 lint 问题。
- **`.gitignore` 斜杠锚定漏洞**：规则写成 `.mimosa/hook-state/`（含斜杠）被锚定到仓库根，
  匹配不到 `tool/gui/.mimosa/` 等嵌套路径 → **442 个 .mimosa + 13 个 .zcode 文件已进版本库**。
- **OHOS 残留**（ADR 0041 EOL）：`build/ohos/` 99 MB、`.deveco/` 57 MB、
  `pubspec_overrides.yaml.disabled`（注释声称的 OHOS git forks 在 pubspec 已 0 命中）。

## 约定

- 文档更新类需求：改用「以代码反查文档」的全量扫描法，见用户级技能 `doc-drift-audit`。
- 分层架构有 15 处依赖倒置破口（views→data 10 处、domain→application 3 处、core 被污染 2 处），
  最严重的是 `domain/repositories/i_course_repository.dart` 引了 `data/course_database.dart`。
  改动涉及分层时留意，但项目无 CI 强制检查，属"演进式"Clean Architecture。
