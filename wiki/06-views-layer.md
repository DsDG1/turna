# 06. UI 层（Views Layer）

> 路径：`lib/views/`
>
> UI 层按 feature 划分子目录。每个 feature 目录下有 `*_page.dart`（页面）、`components/`（组件）、`widgets/`（小部件）。

---

## 6.1 根 Widget 与全局设置

### 6.1.1 [views/app.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/app.dart)

`VarnamalaApp` 顶层 Widget：

```dart
class VarnamalaApp extends StatelessWidget {
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: providers,    // 来自 application/providers.dart
      child: _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  Widget build(BuildContext context) {
    // 监听 ThemeProvider + AccessibilityProvider
    // 选择 light/dark + highContrast + dyslexiaFont
    // 包裹 MediaQuery 注入 textScaler / reduceMotion
    return MaterialApp.router(
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      routerConfig: _routeConfig,
      builder: (context, child) {
        // 应用 MediaQuery 覆盖（textScaler, accessibleNavigation, disableAnimations）
        return MediaQuery(data: mq.copyWith(...), child: child!);
      },
    );
  }
}
```

### 6.1.2 [views/theme.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/theme.dart)

`VarnamalaTheme` 提供 light/dark/highContrast ThemeData + 语义化颜色 helper：

| 常量 / Helper | 用途 |
|---|---|
| `peacockDeep` / `peacockTeal` / `peacockCyan` | 主色 |
| `peacockTurquoise` / `peacockMint` | 强调色 |
| `primary` / `primaryLight` / `primaryDark` | Material 3 ColorScheme seed |
| `secondary` / `secondaryLight` | 副色 |
| `error` / `success` / `warning` / `info` | 语义 |
| `background` / `surface` / `scaffoldBackground` / `cardBackground` | 背景 |
| `textPrimary` / `textSecondary` / `textHint` / `textOnPrimary` | 文本 |
| `leagueBronze/Silver/Gold/Amethyst/Pearl/Ruby/Emerald/Diamond` | 历史/竞赛色 |
| `peacockGradient` / `softGradient` / `courseTreeGradient` | 渐变 |
| `lightTheme` / `darkTheme` / `highContrastLightTheme` / `highContrastDarkTheme` | ThemeData |
| `cardBg(context)` / `scaffoldBg(context)` / `textHintColor(context)` / 等 | 自适应 helper |

### 6.1.3 [views/app_fonts.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/app_fonts.dart)

Dyslexia 字体 `AppFonts.lexendTextTheme(baseTheme)`。

---

## 6.2 路由树

[`lib/routing/routing.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/routing/routing.dart) 定义所有路由 + `CourseReadyGuard`。

### 6.2.1 路由清单

| 路由 | 页面 | Guard |
|---|---|---|
| `SplashRoute` | `views/splash/splash_page.dart` | — |
| `HomeRoute` | `views/home/home_page.dart` | `CourseReadyGuard` |
| `NewLessonRoute` | `views/lesson/new_lesson_screen.dart` | — |
| `SectionPickerRoute` | `views/courses/section_picker_page.dart` | — |
| `AiHubRoute` | `views/ai/ai_hub_page.dart` | `CourseReadyGuard` |
| `AiWishChatRoute` | `views/ai/ai_wish_chat_page.dart` | — |
| `AiHintChatRoute` | `views/ai/ai_hint_chat_page.dart` | — |
| `TextbookImportRoute` | `views/ai/textbook/textbook_import_page.dart` | — |
| `VowelAndConsonantLearningRoute` | `views/characters/character_drawing.dart` | — |
| `MatchWordsRoute` | `views/play/match_words.dart` | — |
| `DailyChallengeRoute` | `views/play/daily_challenge_screen.dart` | — |
| `SrsReviewRoute` | `views/review/srs_review_screen.dart` | — |
| `ReviewProgressRoute` | `views/review/review_progress_page.dart` | `CourseReadyGuard` |
| `GrammarReviewRoute` | `views/review/grammar_review_screen.dart` | — |
| `MistakeListRoute` | `views/review/mistake_list_page.dart` | — |
| `MistakePracticeRoute` | `views/review/mistake_practice_screen.dart` | — |
| `MistakeReviewRoute` | `views/review/mistake_review_page.dart` | `CourseReadyGuard` |
| `DictionaryRoute` | `views/dictionary/dictionary_page.dart` | `CourseReadyGuard` |
| `WeakWordsRoute` | `views/play/weak_words_page.dart` | `CourseReadyGuard` |
| `AnkiImportRoute` | `views/anki/anki_import_screen.dart` | — |
| `AnkiReviewRoute` | `views/anki/anki_review_screen.dart` | `CourseReadyGuard` |
| `AnkiReviewSessionRoute` | `views/anki/anki_review_session_page.dart` | `CourseReadyGuard` |
| `CourseManagementRoute` | `views/courses/course_management_page.dart` | `CourseReadyGuard` |

### 6.2.2 CourseReadyGuard

[`course_ready_guard.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/routing/course_ready_guard.dart) — 当 CourseProvider 的 sections 为空时，重定向到 SplashRoute。Splash 自身无 guard。

---

## 6.3 主页与底部导航

### 6.3.1 [views/home/home_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/home_page.dart)

```dart
class HomePage extends StatefulWidget {
  // 5 个 Tab:
  final screens = [
    const CourseTree(),     // Learn
    const PlayHubScreen(),  // Play
    const ProfilePage(),    // Profile
    const SettingsPage(),   // Settings
    const AiHubPage(),      // AI
  ];
  int currentIndex = 0;
}
```

通过 `TabRouter` 服务跨页面跳转 Tab。`initSession()` 初始化语言 provider + 触发每日会话（streak 检查等）。

### 6.3.2 [views/home/components/](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/components)

- [`bottom_navigator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/components/bottom_navigator.dart) — 自定义 5 tab 底部导航
- [`stat_app_bar.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/components/stat_app_bar.dart) — Learn tab 顶栏（streak / XP / 宝石 chip）
- [`profile_app_bar.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/components/profile_app_bar.dart) — Profile tab 顶栏
- [`mala_welcomes.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/mala_welcomes.dart) — Mascot 吉祥物（mala）
- [`streak_broken_dialog.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/home/streak_broken_dialog.dart) — 连胜中断提示

---

## 6.4 课程树（Learn Tab）

### 6.4.1 [views/courses/course_tree.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/courses/course_tree.dart)

`CourseTree` 是 Learn Tab 的主页面，渲染 Section → Unit → Lesson 树。

**关键设计**：

```dart
class _CourseTreeState extends State<CourseTree> {
  // 防御性 body load —— idempotent
  final Set<String> _scheduledEnsure = {};

  // Accordion：同一时刻最多展开一个 Unit
  String? _expandedUnitId;

  Widget build(BuildContext context) {
    return Consumer<CourseProvider>(
      builder: (context, courseState, _) {
        final sections = courseState.sections;

        if (sections.isEmpty) {
          if (courseState.isLoaded) {
            return _buildErrorMessage(context, ..., onRetry: courseState.reloadCourse);
          }
          return const Center(child: _LoadingIndicator());
        }

        // SliverList 渲染 sections，virtualized
        return CustomScrollView(
          slivers: [
            SliverAppBar(...),
            SliverList.builder(
              itemBuilder: (context, index) => _buildSectionTile(sections[index]),
            ),
          ],
        );
      },
    );
  }
}
```

**Section 加载状态**：

- `SectionLoadState.initial` → 触发 `ensureSectionLoaded`（防御性）
- `SectionLoadState.loading` → 显示 loading
- `SectionLoadState.loaded` → 显示内容
- `SectionLoadState.error` → 显示错误 + 重试按钮

### 6.4.2 [views/courses/components/](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/courses/components)

- `section_switcher.dart` — 顶部 section 选择器
- `section_visuals.dart` — section 图标 / 颜色 / 进度环
- `unit_header.dart` — unit 折叠/展开头部

### 6.4.3 [views/courses/section_picker_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/courses/section_picker_page.dart)

跨所有 Section 的统一选择视图（CEFR 等级分组）。

### 6.4.4 [views/courses/course_management_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/courses/course_management_page.dart)

Anki 导入 / 卸载管理页面。

---

## 6.5 课程内播放（Lesson Player）

### 6.5.1 [views/lesson/new_lesson_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/lesson/new_lesson_screen.dart)

课程播放主屏幕，承载整个 LessonViewModel 生命周期：

```dart
class NewLessonScreen extends StatefulWidget {
  final Lesson lesson;
  final bool practiceMode;
  ...
}
```

主要职责：

1. **生命周期管理**：initState 时调用 `lessonViewModel.startLesson(lesson)`；dispose 时清理
2. **进度展示**：进度条 + 当前 stage 标题 + 当前 interaction 序号
3. **Renderer 调度**：通过 `lookupRenderer(renderers, interaction)` 找到对应 `InteractionRenderer`
4. **底部动作按钮**：根据 `autoAdvance` 决定是否显示 "Continue"
5. **完成总结**：lesson 完成时展示统计 + 跳转

### 6.5.2 [views/lesson/components/interactions/](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/lesson/components/interactions)

**13 个 Renderer**，每个 `@injectable`，注册到 [`renderer_module.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/di/renderer_module.dart)：

| Renderer | 文件 | 对应 Interaction |
|---|---|---|
| `ShowWordRenderer` | `show_word_renderer.dart` | `ShowWord` |
| `MultipleChoiceRenderer` | `multiple_choice_renderer.dart` | `MultipleChoice` |
| `MultiSelectRenderer` | `multi_select_renderer.dart` | `MultiSelect` |
| `FillBlankRenderer` | `fill_blank_renderer.dart` | `FillBlank` |
| `TranslateSentenceRenderer` | `translate_sentence_renderer.dart` | `TranslateSentence` |
| `ListenAndPickRenderer` | `listen_and_pick_renderer.dart` | `ListenAndPick` |
| `TypeTheWordRenderer` | `type_the_word_renderer.dart` | `TypeTheWord` |
| `ListenOnlyRenderer` | `listen_only_renderer.dart` | `ListenOnly` |
| `ReorderSentenceRenderer` | `reorder_sentence_renderer.dart` | `ReorderSentence` |
| `ReadingMcqRenderer` | `reading_mcq_renderer.dart` | `ReadingMcq` |
| `ReadingTrueFalseRenderer` | `reading_true_false_renderer.dart` | `ReadingTrueFalse` |
| `ReadingShortAnswerRenderer` | `reading_short_answer_renderer.dart` | `ReadingShortAnswer` |
| `AnkiCardRenderer` | `anki_card_renderer.dart` | `AnkiCard` |

**Renderer 抽象**：

```dart
abstract class InteractionRenderer {
  Type get handlesType;
  bool get autoAdvance;  // true = 提交后自动下一题（ShowWord / ListenOnly）

  Widget build(
    Interaction interaction,
    InteractionState state,        // submitted / correct / userAnswerText
    OnInteractionSubmit onSubmit,  // 回调
  );
}
```

**Dispatcher**：

```dart
InteractionRenderer lookupRenderer(
  Iterable<InteractionRenderer> renderers,
  Interaction interaction,
) {
  final target = _handlesTypeFor(interaction);   // sealed switch
  return renderers.firstWhere(
    (r) => r.handlesType == target,
    orElse: () => throw StateError(
      'No InteractionRenderer registered for $target. '
      'Did you forget to @injectable it?',
    ),
  );
}
```

### 6.5.3 [views/lesson/components/](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/lesson/components)

- `lesson_stage_widgets.dart` — stage 容器（进度条、stage 切换）
- `lesson_practice_card.dart` — 练习卡片外框
- `lesson_dialogs.dart` — 完成 / 退出确认对话框
- `ai_hint_sheet.dart` — 课程内 AI 提示 BottomSheet
- `ai_depth_tutor_sheet.dart` — 深度 AI 辅导 BottomSheet
- `tutor_launch_sheet.dart` — AI 辅导员启动入口
- `cached_asset_image.dart` — 缓存优化的图片 widget
- `anki_media_strip.dart` — Anki 媒体缩略图条

---

## 6.6 复习页面（Play Tab 子页）

### 6.6.1 [views/play/play_hub_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/play/play_hub_screen.dart)

Play Tab 的 Hub 页，4 个入口卡片：

- Match Madness（限时配对）
- SRS Review（间隔重复复习）
- Mistakes（错题本）
- Weak Words（弱词复习）

### 6.6.2 [views/play/match_words.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/play/match_words.dart) + `match_levels.dart`

Match Madness 游戏 UI（基于 `MatchProvider`）。`match_levels.dart` 是关卡 / 配置。

### 6.6.3 [views/play/daily_challenge_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/play/daily_challenge_screen.dart)

每日挑战：从课程树随机抽题合成挑战课，模拟交错练习。

### 6.6.4 [views/play/weak_words_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/play/weak_words_page.dart)

弱词复习（30 天内错误 ≥2 次 → 10 题 quiz），由 `WeakWordQuizAssembler` 拼装。

### 6.6.5 [views/play/play_app_bar.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/play/play_app_bar.dart)

Play 页面统一 AppBar。

---

## 6.7 复习页面（独立路由）

### 6.7.1 [views/review/srs_review_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/srs_review_screen.dart)

SRS 闪卡复习（FSRS 生产算法）。流程：due words → 一次一词 → 用户自评（4 按钮：Again / Hard / Good / Easy，对应 SM-2 0/3/4/5）→ next。

### 6.7.2 [views/review/grammar_review_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/grammar_review_screen.dart)

语法点复习 Explain → Practice → Rate 三段流。

### 6.7.3 [views/review/mistake_list_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/mistake_list_page.dart)

错题列表（30 条 FIFO），可进入错题重做。

### 6.7.4 [views/review/mistake_practice_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/mistake_practice_screen.dart)

错题练习（复用 LessonViewModel，`practiceMode: true`）。

### 6.7.5 [views/review/mistake_review_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/mistake_review_page.dart)

错题复习入口。

### 6.7.6 [views/review/review_progress_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/review_progress_page.dart)

复习进度概览（待复习 / 已学 / 弱词统计）。

### 6.7.7 [views/review/components/](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/components)

- `retention_curve_chart.dart` — fl_chart 记忆曲线
- `review_components.dart` — 通用组件

---

## 6.8 Profile Tab

### 6.8.1 [views/profile/profile_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/profile_screen.dart)

Profile 主页面：

- AccountWidget（账号头像 + 名称）
- 学习统计仪表盘（[`learning_stats.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/widgets/learning_stats.dart)）
- Achievements（[`achievements.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/widgets/achievements.dart)）
- Statistics（[`statistics.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/widgets/statistics.dart)）
- Share Progress Card（[`share_progress_card.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/widgets/share_progress_card.dart)）
- Quick Actions（[`profile_quick_actions.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/widgets/profile_quick_actions.dart)）

### 6.8.2 学习统计仪表盘

[`learning_stats.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/widgets/learning_stats.dart) 展示：

- **7 日 XP 趋势**：fl_chart LineChart
- **时长 / 准确率 / 课数 / 弱词分析**：四象限
- **90 天 StudyLog 表格**

### 6.8.3 [views/profile/utils/share_image_generator.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/profile/utils/share_image_generator.dart)

生成可分享的进度图片（Canvas API）。

---

## 6.9 Settings Tab

### 6.9.1 [views/settings/settings_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/settings_page.dart)

设置主页，按 section 组织：

- [`settings_account_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_account_section.dart) — 账号信息
- [`settings_appearance_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_appearance_section.dart) — 主题 / 字体
- [`settings_sound_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_sound_section.dart) — 音效 / 触感
- [`settings_learning_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_learning_section.dart) — FSRS retention / 优化
- [`settings_reminder_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_reminder_section.dart) — 每日提醒时间
- [`settings_accessibility_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_accessibility_section.dart) — 无障碍
- [`settings_fun_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_fun_section.dart) — 彩蛋
- [`settings_xiaoyi_tile.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_xiaoyi_tile.dart) — "小蚁" AI 助手开关
- [`settings_about_section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/widgets/settings_about_section.dart) — 关于

### 6.9.2 子页面

- [`about_varnamala_page.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/about_varnamala_page.dart) — 项目信息
- [`changelog_page.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/changelog_page.dart) — 更新日志
- [`ai_api_config_sheet.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/settings/ai_api_config_sheet.dart) — AI API 配置 sheet

---

## 6.10 AI Hub

### 6.10.1 [views/ai/ai_hub_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/ai_hub_page.dart)

AI 功能中心：

- AI Course Generator（普通模式 + 许愿模式）
- AI Hint（课程内嵌聊天）
- AI Depth Tutor（深度辅导）
- AI Hub AppBar（[`ai_hub_app_bar.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/components/ai_hub_app_bar.dart)）
- Recent Tasks（最近生成任务）

### 6.10.2 [views/ai/ai_wish_chat_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/ai_wish_chat_page.dart)

AI "许愿模式"：多轮对话 + 附件 → 用户点 "我感觉差不多了" → AI 生成 JSON。

### 6.10.3 [views/ai/ai_hint_chat_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/ai_hint_chat_page.dart)

课程内嵌 AI 提示聊天面板。

### 6.10.4 [views/ai/ai_lesson_helper_sheet.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/ai_lesson_helper_sheet.dart)

课程内 AI 助教 sheet。

### 6.10.5 [views/ai/chat_bubble.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/chat_bubble.dart)

聊天气泡 widget。

### 6.10.6 [views/ai/textbook/](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/ai/textbook)

- `textbook_import_page.dart` — 教材导入向导
- `textbook_conflict_preview.dart` — 冲突预览
- `textbook_review_panel.dart` — 审核面板

---

## 6.11 词典

[`views/dictionary/dictionary_page.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/dictionary/dictionary_page.dart) — 词典/搜索：

- 全文搜索词汇 / 表达 / 语法点
- 播放音频（通过 `VocabAudioResolver`）
- 点击进入 Anki 风格闪卡

---

## 6.12 Anki 导入与复习

### 6.12.1 [views/anki/anki_import_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/anki/anki_import_screen.dart)

Anki `.apkg` / `.colpkg` 导入向导：选文件 → notetype 映射 → AI 增强（可选）→ 提交。

### 6.12.2 [views/anki/anki_review_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/anki/anki_review_screen.dart)

Anki 复习 Hub（所有 Anki 导入的合集）。

### 6.12.3 [views/anki/anki_review_session_page.dart](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/anki/anki_review_session_page.dart)

Anki 单次复习会话（基于 AnkiCardRenderer + AnkiReviewAssembler）。

---

## 6.13 字符学习（Alphabet Learning）

[`views/characters/character_drawing.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/characters/character_drawing.dart) + `characters_app_bar.dart` — 字母（元音/辅音）学习。

> 当前主要针对泰米尔/Indic 文字设计；Turkish（拉丁字母）版本尚未启用。

---

## 6.14 启动与 Onboarding

- [`views/splash/splash_page.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/splash/splash_page.dart) — 启动页
  - 组件：`splash_background_painter.dart`、`center_display.dart`、`get_started_button.dart`
- [`views/onboarding/onboarding_screen.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/onboarding/onboarding_screen.dart) — 首次启动介绍

---

## 6.15 内容更新提示

[`views/content_update/content_update_dialog.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/content_update/content_update_dialog.dart) — 检测到 bundle 内课程 version 变化时弹出，提示用户是否重置进度。

---

## 6.16 通用组件与 Widget

- [`views/widgets/loader.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/widgets/loader.dart) — 通用加载动画
- [`views/widgets/gems_display.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/widgets/gems_display.dart) — 宝石展示 chip

---

## 6.17 国际化

[`lib/l10n/app_strings.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/l10n/app_strings.dart) 集中所有用户可见字符串常量（`AppStrings.xxx`）。

---

## 6.18 资源生成

[`lib/gen/assets.gen.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/gen/assets.gen.dart) 由 `flutter_gen` 自动生成，提供类型安全的资源引用（如 `Assets.images.appLogo.path`）。

---

## 6.19 工具类

[`lib/utils/ohos_file_picker.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/utils/ohos_file_picker.dart) — 鸿蒙平台的文件选择器 fallback。