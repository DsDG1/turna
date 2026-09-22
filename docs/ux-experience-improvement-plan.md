# Turna 体验改良施工计划（收据）

> 源计划：`C:\Users\DsDogs\Desktop\Turna体验改良施工计划.md`（2026-09-21 代码审查，约 41 工单）。
> 状态：**B1–B7 可编码项已落地**。2026-09-22 补上计划里仍标未做的四项：启动阶段文案、聊天气泡 Markdown（自研子集，不新增依赖）、改课 JSON 快照、导师会话列表。
> 验证：见 `test/BASELINE.md` 最新条目。

产品禁区未动：二元评分（ADR 0028）、课程树不硬锁、无社交/Hearts、无云端推送、无全局错误弹窗。未引入新依赖。

## 批次结果

| 批次 | 结果 |
|------|------|
| B1 三个真 bug | 完成 |
| B2 复习会话 | 完成（语法复习接入统一 controller 仍按计划不做） |
| B3 启动与首页 | 完成；播种在首帧后，Splash 显示「准备 / 校验」；迁移仍在 `runApp` 前，避免换库句柄 |
| B4 课时快赢 | 完成 |
| B5 AI 反馈面 | 完成。助手气泡渲染 Markdown 子集；改课快照写入 prefs；导师聊天保留会话列表 |
| B6 危险操作 | 完成 |
| B7 一致性清扫 | 完成；见下方残留 |

## 工单勾选

- [x] B1-1 土耳其语判分：`lib/core/turkish_text.dart` `foldTurkish`；四渲染器 `_matches`；`test/core/turkish_text_test.dart`
- [x] B1-2 错题刷新：`MistakeProvider.reloadFromPrefs` 清缓存后 `await ensureLoaded()`
- [x] B1-3 星期标签：`AppStrings.weekdayShortLabel`；`learning_stats` 用 `day.date.weekday`
- [x] B2-1 退出确认 + 按比例 `SessionSettlementService.settle`；完成态 X 可 pop
- [x] B2-2 乐观推进 + `isPersisting` 禁 undo；`answer(cachedPreview:)` 跳过重复 preview
- [x] B2-3 `SettingsProvider.reviewBatchSize` ∈ {20,25,30}；完成页 `remainingDue` + 继续
- [x] B2-4 完成页撤销 + 评分后底部撤销条
- [x] B2-5 `previewError` / `writeError` 分流
- [x] B2-6 新卡 `maybeAutoSpeak`；官方模板卡角落朗读
- [x] B3-1 已初始化且课程 loaded → Splash `replaceAll(HomeRoute)`
- [x] B3-2 Get Started busy；未 loaded 挂起点击
- [x] B3-3 Learn `DueChip`：语言课四项之和；Anki 课官方+legacy due；Home `OfficialAnkiHomeDueSync.refresh`
- [x] B3-4 next-up 展开（见偏差）
- [x] B3-5 弹窗预算 TTS > 断签 > 内容更新；内容更新改 Home 横幅
- [x] B3-6 播种在首帧回调；失败可重试；Splash 显示准备/校验文案（`splashStartupStatusLabel`）
- [x] B4-1 七渲染器提交后隐藏核对按钮
- [x] B4-2 type/translate/reading_short_answer `unfocus`
- [x] B4-3 AppBar `X/Y`
- [x] B4-4 listen_and_pick / type_the_word / listen_only `maybeAutoSpeak`
- [x] B4-5 ShowWord submitted + 300ms
- [x] B4-6 `SpeakerButton` 订阅 `speakingListenable`，播放中禁点
- [x] B4-7 提示改 `lightbulb_rounded`
- [x] B5-1 用户气泡 `SelectableText`；助手气泡 `parseSimpleMarkdown`（标题/列表/代码/粗斜体），不引入 `flutter_markdown`
- [x] B5-2 各 AI provider 存 `AiErrorMapping` + 词典/改课/卡讲解/hint sheet `AiErrorBanner`
- [x] B5-3 流式时输入框可用，发送改停止
- [x] B5-4 诊断页 `cancel()`
- [x] B5-5 改课确认 + 预览；写入后 SnackBar 撤销，并把改前 JSON 存入 `AiLessonUndoStore`，课时页可再撤销一次
- [x] B5-6 词典防抖专属文案 + 停止/复制/收藏
- [x] B5-7 Hub 继续区过滤 wish/textbook；导师聊天 prefs 会话列表，进页恢复当前会话，可另开或切回旧会话
- [x] B5-8 保存讲解 SnackBar 撤销 + 本地化元数据 + 复制
- [x] B6-1 内容更新 reset 二次确认 + 导出入口
- [x] B6-2 账户重置「先导出备份」
- [x] B6-3 JSON 导入 spinner
- [x] B6-4 透明度清空后果文案 + 危险确认 + 复制全部
- [x] B6-5 课程管理 `_busy`
- [x] B6-6 `officialSchemaForPreviewNode`（牌组名匹配 schema.name，再 archetypeLabel）
- [x] B7-1…B7-10：`relearnPreviewLabel` 走 AppStrings；`PracticeSessionBody` 接入课时/每日/弱词/错题重做

## 实现偏差（有意）

1. **B3-4**：仅当该 Section 已有任意完成课时才自动展开 next-up，避免全新用户/既有折叠测试被展开第一节。
2. **B3-3**：Anki 课 due 与 Play 相同（`aggregatedAnkiDue`，unavailable 当 0）；语言课仍含表达 due（Play Hub `totalDue` 不含表达）。
3. **B5-2**：wish / textbook 页面仍是创作退场 tombstone，provider 已存 mapping 但无独立错误页。

## 明确未做 / 残留

| 项 | 说明 |
|----|------|
| 语法统一会话 | 计划写明本批不做：语法复习仍不接入 `ReviewSessionController`；评分后有一步撤销 |

## 关键落点

| 主题 | 路径 |
|------|------|
| 土耳其语判分 | `lib/core/turkish_text.dart` |
| 复习会话 | `lib/application/review/review_session_controller.dart` |
| 退出结算 | `lib/application/study_session/session_settlement_service.dart` |
| 自动朗读门控 | `lib/application/smart_speech.dart` `maybeAutoSpeak` |
| AI 错误条 | `lib/views/ai/components/ai_error_banner.dart` |
| 聊天气泡 Markdown | `lib/core/simple_markdown.dart` |
| 改课撤销快照 | `lib/application/ai/ai_lesson_undo_store.dart` |
| 导师会话列表 | `lib/application/ai/ai_tutor_chat_session.dart` |
| 练习脚手架 | `lib/views/lesson/components/practice_session_body.dart` |
