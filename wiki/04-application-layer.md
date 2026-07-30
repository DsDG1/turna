# 04. 应用层（Application / Providers）

> 路径：`lib/application/`
>
> 应用层全部由 `ChangeNotifier` 子类组成，通过 `provider` 包注入到 widget 树。所有 `@lazySingleton` 标注的 Provider 在 GetIt 中也是单例，确保 GetIt 与 Provider 共用同一实例。

---

## 4.1 Provider 总览

[`providers.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/providers.dart) 集中注册了所有 Provider，按职责可分为 4 组：

### 4.1.1 课程与复习状态

| Provider | 职责 | 关键依赖 |
|---|---|---|
| [`CourseProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/course_provider.dart) | 课程树加载 + 当前选择 + Scope 过滤 | `ICourseRepository`, `AppPrefs` |
| [`LessonViewModel`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_viewmodel.dart) | 单节课内 stage / interaction 推进 | 多个 SRS / Mistake provider |
| [`SrsProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/srs_provider.dart) | 单词 / 表达 SRS 队列（FSRS 生产） | `SrsStateDao`, `LessonLinkStore` |
| [`GrammarReviewProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/grammar_review_provider.dart) | 语法点 SRS 队列（与 SrsProvider 并行） | 同上 |
| [`SrsTutorProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/srs_tutor_provider.dart) | AI 个性化辅导员上下文聚合 | 多个 provider |
| [`MistakeProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/mistake_provider.dart) | 30 条 FIFO 错题本 | `AppPrefs` |
| [`ProgressProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/progress_provider.dart) | 综合学习进度聚合 | 多个 provider |

### 4.1.2 学习统计与游戏状态

| Provider | 职责 | 关键依赖 |
|---|---|---|
| [`StudyStatsProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/study_stats_provider.dart) | 日/周学习统计 + StudyLog 聚合 | `StudyLogRepository`, `MistakeProvider` |
| [`MemoryCurveProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/memory_curve_provider.dart) | 记忆曲线 / 保持率可视化 | `SrsStateDao` |
| [`ReviewProgressProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/review_progress_provider.dart) | 复习进度概览 | 多个 provider |
| [`ScoreProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/score_provider.dart) | 总 XP 分数 | `AppPrefs` |
| [`StreakProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/streak_provider.dart) | 连胜状态 | `AppPrefs`, `StreakResolver` |
| [`LessonProgressProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_progress_provider.dart) | 已完成 / 完美 Lesson 集合 | `AppPrefs` |
| [`GameMilestoneProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/game_milestone_provider.dart) | 成就 / 宝石里程碑 | `AppPrefs` |
| [`GemsProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/gems_provider.dart) | 宝石数量（虽不消费但作为 facade 成员） | `AppPrefs` |
| [`AchievementsProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/achievements_provider.dart) | 成就列表 | `AppPrefs` |
| [`GameProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/game_provider.dart) | **Facade**：score / streak / progress / milestone 聚合 | 注入上述 4 个 |
| [`MatchProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/match_provider.dart) | Match Madness 游戏状态 | `AudioController`, `AppPrefs` |

### 4.1.3 用户偏好

| Provider | 职责 |
|---|---|
| [`ThemeProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/theme_provider.dart) | light / dark / system 主题 |
| [`SettingsProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/settings_provider.dart) | 全部用户设置（音效 / 提醒 / TTS 速度 / FSRS retention 等） |
| [`AccessibilityProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/accessibility_provider.dart) | 无障碍（文字缩放 / 减少动画 / 高对比度 / Dyslexia 字体） |
| [`LanguageProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/language_provider.dart) | 当前语种（当前固定 Turkish） |

### 4.1.4 AI 引擎与教材

| Provider | 职责 |
|---|---|
| [`AiCourseProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_course_provider.dart) | AI 课程生成主流程 |
| [`AiWishProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_wish_provider.dart) | AI "许愿模式"（多轮对话生成） |
| [`AiGroundedResourceProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_grounded_resource_provider.dart) | AI 资源合规校验 |
| [`AiLessonHelperProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_lesson_helper_provider.dart) | 课内 AI 助教（深度辅导） |
| [`AiHintProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/ai_hint_provider.dart) | 课程内嵌 AI 提示面板 |
| [`TextbookImportProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/textbook/textbook_import_provider.dart) | 教材导入任务管理 |
| [`AiEngineConfigHolder`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_engine_config_holder.dart) | AI 引擎配置（provider / model / 缓存开关） |
| [`AiRecentTasksProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/ai/engine/ai_recent_tasks_provider.dart) | AI 最近任务列表 |

---

## 4.2 核心 Provider 详解

### 4.2.1 CourseProvider

[`course_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/course_provider.dart) — 课程树状态机。

**核心数据结构**：

```dart
@lazySingleton
class CourseProvider extends ChangeNotifier {
  List<Section> _sections = const [];           // 当前 scope 过滤后的视图
  List<Section> _allSections = const [];        // 不带 scope 的全集（含 Anki）
  String? _currentSectionId;
  String? _selectedUnitId;
  String? _selectedLessonId;
  bool _isLoaded = false;
  String _courseScope = '';                     // '' = 内置；'anki:<importId>' = Anki scope

  final Set<String> _loadedSectionIds = {};     // 已加载 body 的 section
  final Map<String, Lesson> _lessonCache = {};   // O(1) lessonId → Lesson
  final Map<String, Future<void>> _sectionLoadFutures = {};  // 并发合并
  final Map<String, SectionLoadState> _sectionLoadStates = {};
  final Map<String, Object> _sectionLoadErrors = {};
}
```

**加载策略（lazy + coalesce）**：

- [`load()`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/course_provider.dart) — 加载 section shells（L0）+ 预加载第一个 section body（L1）
- [`ensureSectionLoaded(id)`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/course_provider.dart) — 按需加载某 section 的 body；如果正在加载则复用 future（coalesce）
- `findUnitById()` / `findLessonById()` — 只搜索已加载 body 的 section

**Scope 机制**：内置课程 `''` vs Anki 导入 `anki:<importId>`。Anki review hub、Daily challenge 等需要 scope-independent 的消费者读取 `allSections`。

### 4.2.2 LessonViewModel

[`lesson_viewmodel.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_viewmodel.dart) — 单节课内的 stage 推进。

**核心抽象**：

```dart
enum AnswerState { none, selected, correct, incorrect, readyForNext }

class QuestionResult {
  final String prompt;
  final bool correct;
  final String? userAnswer;
  final String? correctAnswer;
}

@lazySingleton
class LessonViewModel extends ChangeNotifier {
  Lesson? _lesson;
  int _currentStageIndex = 0;
  int _currentInteractionIndex = 0;
  AnswerState _state = AnswerState.none;
  List<QuestionResult> _results = [];
  bool _isPracticeMode = false;       // true = 错题重做

  Future<void> startLesson(Lesson lesson, {bool practiceMode = false});
  void onAnswer({...});              // 用户提交答案
  Future<void> goToNext();           // 推进到下一题
  void reset();
}
```

**关键设计**：所有 Lesson 类型（normal/listening/reading/review/challenge）都被建模为 `lesson.content.stages` 的线性列表。ViewModel 不需要按 type 分支，新增 LessonType 或 Interaction 不需要改这里。

**完成协调**：[`LessonCompletionCoordinator`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_completion_coordinator.dart) 处理 lesson 完成的副作用（XP、streak、StudyLog 记录）。

### 4.2.3 SrsProvider / GrammarReviewProvider

两者都继承自 [`SrsQueueProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/srs_queue_provider.dart)：

```dart
@lazySingleton
class SrsProvider extends SrsQueueProvider {
  @override String get statePrefsKey => LocalStateKeys.srsState;
  @override String get queueId => 'srs';          // SQLite queue 列
  @override String get logTag => 'SrsProvider';

  // 公开 API
  void registerWord(String wordId);
  void registerAll(Iterable<String> wordIds);
  void registerExpression(String expressionId);
  Future<void> bulkImportStates(Map<String, SrsWord> states);  // Anki
  Future<void> removeByPrefix(String prefix);
  Future<void> recordLessonLinks({...});
  Future<SrsWord?> reviewWord(String wordId, int quality);
  Future<SrsWord?> reviewWithQuality(String wordId, ReviewGrade grade);
}

@lazySingleton
class GrammarReviewProvider extends SrsQueueProvider {
  @override String get statePrefsKey => LocalStateKeys.grammarReviewState;
  @override String get queueId => 'grammar';

  void registerGrammarPoint(String id);
  Future<void> markDueNow(String id);   // 错题 → 语法点跨路由
}
```

**SrsQueueProvider 提供的共享机制**：

- 内存 `Map<String, SrsWord>` 缓存（同步读取）
- 启动时 `ensureLoaded()`：从 SQLite hydrate（同时跑 v7 schema 迁移）
- 默认 FSRS scheduler（生产）；SM-2 仍可通过 `setSchedulerForTesting()` 注入
- `setDesiredRetention(double)`：重建 FSRS 引擎
- `setFsrsParameters(List<double>?)`：应用 FSRS 优化权重

详见 [07-srs-engine.md](./07-srs-engine.md)。

### 4.2.4 MistakeProvider

[`mistake_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/mistake_provider.dart) — 30 条 FIFO 错题本。

```dart
@lazySingleton
class MistakeProvider extends ChangeNotifier {
  static const int maxEntries = 30;
  static const String _prefsKey = LocalStateKeys.mistakeLog;

  List<MistakeEntry>? _cached;
  List<MistakeEntry>? _cachedView;

  List<MistakeEntry> get entries;                  // unmodifiable view
  int get count;

  List<MistakeEntry> recentMistakes({int max = 20});  // SrsTutor 使用

  Future<void> record(MistakeEntry entry);          // FIFO 添加
  Future<void> recordRewrite(String entryId);      // rewriteCount++；≥2 时清除
  Future<void> clear();
  Future<void> removeById(String entryId);
}
```

存储使用 `AppPrefs`（StreamingSharedPreferences）的字符串键，值为 JSON 编码的 MistakeEntry 数组。**没有 SQLite 表**——错题本小、临时，JSON 足够。

### 4.2.5 GameProvider — Facade

[`game_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/game_provider.dart) 是 score / streak / lesson progress / milestone 四个 Provider 的聚合 facade：

```dart
enum XPEvent {
  lessonComplete(base: 10),
  perfectLesson(base: 15),
  srsReviewSession(base: 5),
  grammarReviewSession(base: 5);
  final int base;
}

@lazySingleton
class GameProvider extends ChangeNotifier {
  // 转发到 ScoreProvider
  int get score;
  Future<int> addXp(XPEvent event, int sessionCount);

  // 转发到 StreakProvider
  int get streak;
  StreakCheckResult checkStreakOnAppOpen();
  Future<StreakResolution> applyPracticeDay(DateTime today);

  // 转发到 LessonProgressProvider
  bool isLessonCompleted(String id);
  bool isLessonPerfect(String id);

  // 转发到 GameMilestoneProvider
  List<Milestone> get milestones;

  Stream<UserGameState> get stateStream;
}
```

Facade 的目的（ADR 0015）：UI / tests 不需要注入 4 个 Provider；同时保留子 Provider 作为更细粒度的 API。

### 4.2.6 StudyStatsProvider

[`study_stats_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/study_stats_provider.dart) — 学习统计聚合。

```dart
@lazySingleton
class StudyStatsProvider extends ChangeNotifier {
  StudyStatsProvider(this._repository, this._mistakeProvider);

  /// 记录一次学习活动（lesson 完成 / SRS 复习 / 游戏）
  Future<void> recordActivity({
    required StudyActivityType type,
    String? lessonId,
    int xpEarned = 0,
    int durationSeconds = 0,
    int correctCount = 0,
    int incorrectCount = 0,
    List<String> wordIds = const [],
  });

  Future<DailyStudyStats> getTodayStats();
  Stream<List<DailyStudyStats>> getWeeklyStatsStream();
  Future<List<DailyStudyStats>> getLastNDays(int n);
  Future<int> getTotalStudyMinutes();
  Future<double> getAccuracy({int sinceDays = 30});

  Stream<List<DailyStudyStats>> get _dailyStatsController;
}
```

驱动 Profile 页面的"学习统计仪表盘"（7 日 XP 趋势 + 90 天 StudyLog + 时长/准确率/课数/弱词分析）。

### 4.2.7 ThemeProvider / SettingsProvider / AccessibilityProvider

```dart
@lazySingleton
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode;     // light / dark / system
  ThemeData get currentTheme;
  void toggleTheme();
  void setLightMode() / setDarkMode() / setSystemMode();
}

@lazySingleton
class SettingsProvider extends ChangeNotifier {
  bool soundEffectsEnabled;
  bool hapticFeedbackEnabled;
  double ttsSpeed;                              // 0.5–2.0
  bool dailyReminderEnabled;
  TimeOfDay dailyReminderTime;                  // 默认 19:00
  bool useXiaoyiHint;
  double srsDesiredRetention;                   // FSRS target, 0.80–0.95
  bool hasCustomFsrsWeights;
  // ... setter methods with notifyListeners()
}

@lazySingleton
class AccessibilityProvider extends ChangeNotifier {
  TextScaler textScaler;
  bool reducedMotion;
  bool highContrast;
  bool dyslexiaFont;       // Lexend 字体
}
```

### 4.2.8 MatchProvider — Match Madness 游戏

[`match_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/match_provider.dart) 实现 Match Madness 单词配对游戏：

```dart
@lazySingleton
class MatchProvider extends ChangeNotifier {
  final ValueNotifier<int> countdownNotifier;   // 90s 倒计时（独立 rebuild）

  List<String> englishWords;        // 英文释义列
  List<String> targetWords;         // 目标语单词列
  Map<String, String> matchedPairs;
  String? selectedEnglishWord;
  String? selectedTargetWord;
  Set<String> matchedWords;
  bool isGameOver;
  int sessionScore;
  int roundsCompleted;
  int currentRoundMatches;

  void startNewRound();
  void selectEnglish(String word);
  void selectTarget(String word);     // 自动匹配判定
  void reset();
}
```

游戏机制：8 对/round，选英文 → 选目标语，匹配对则记分；超过 90s 或全部匹配则游戏结束。

### 4.2.9 CourseProvider.load 的初始化细节

```dart
Future<void> load() async {
  final shells = await _repository.sectionShells();   // L0
  _allSections = shells;
  _applyScopeFilter();                                 // 应用 scope 过滤
  _isLoaded = true;
  notifyListeners();

  // 预加载第一个 section（仅内置 scope）
  if (_courseScope.isEmpty && _sections.isNotEmpty) {
    await ensureSectionLoaded(_sections.first.id);
  }
}
```

幂等：可被 `ensureSectionLoaded` 的并发调用触发，结果稳定。

---

## 4.3 Provider 生命周期

### 4.3.1 启动顺序

`lib/main.dart` 在 `runApp` 之后的 PostFrameCallback 中执行：

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  await loadVocabulary();           // 同步查找表
  await loadGrammarPoints();
  await loadExpressions();

  await getIt<SrsProvider>().ensureLoaded();        // SRS 状态 hydrate
  await getIt<GrammarReviewProvider>().ensureLoaded();

  await getIt<CourseProvider>().load();              // 课程树加载

  if (!kIsWeb) {
    await getIt<TtsAvailabilityChecker>().configureSystemEngine();
    try {
      await getIt<LocalReminderService>().applyFromSettings(
        enabled: settings.dailyReminderEnabled,
        time: settings.dailyReminderTime,
      );
    } catch (_) {/* best-effort */}
  }
});
```

### 4.3.2 单例保证

```dart
@LazySingleton(as: ICourseRepository)
class CourseRepository implements ICourseRepository { ... }

// providers.dart
ChangeNotifierProvider<CourseProvider>(
  create: (_) => getIt<CourseProvider>(),    // ← GetIt 单例
),
```

`@lazySingleton` 确保 `getIt<CourseProvider>()` 永远返回同一实例，避免状态分裂。

---

## 4.4 跨 Provider 协作模式

### 4.4.1 Lesson 完成流程

```
用户答完最后一道题
  ↓
LessonViewModel.notifyComplete()
  ↓
LessonCompletionCoordinator.handleCompletion()
  ├─ SrsProvider.reviewWord() × N          // 标记所有展示过的词
  ├─ MistakeProvider.record() × 错误数    // 错题入队
  ├─ LessonProgressProvider.recordLessonCompletion()
  ├─ ScoreProvider.addScore(XPEvent.lessonComplete)
  ├─ StreakProvider.applyPracticeDay(today)
  ├─ StudyStatsProvider.recordActivity({type: lesson})
  └─ GameMilestoneProvider.checkMilestones()
```

### 4.4.2 错题 → 语法复习路由

```
用户答错某题（带 grammarPointId）
  ↓
MistakeProvider.record(MistakeEntry(grammarPointId: 'gp-...'))
  ↓
GrammarReviewProvider.markDueNow('gp-...')
  ↓
用户从 mistake_list 进入 GrammarReviewScreen
  ↓
GrammarReviewProvider.reviewGrammarPoint('gp-...', quality)
```

---

## 4.5 Stream-based Provider

部分 Provider 暴露 Stream 而非仅 ChangeNotifier：

- `StudyStatsProvider.getWeeklyStatsStream()` — 7 日统计流
- `LessonProgressProvider.completedLessonsStream` — 完成 lesson 集合流
- `GameProvider.stateStream` — 完整 UserGameState 流
- `SrsProvider.dueWordsStream` — 待复习词条流（待复习 UI）

```dart
// UI 订阅
final stream = context.read<StudyStatsProvider>().getWeeklyStatsStream();
stream.listen((stats) => updateChart(stats));
```

---

## 4.6 Sub-facade 与工具类

| 文件 | 职责 |
|---|---|
| [`lesson_completion_coordinator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_completion_coordinator.dart) | Lesson 完成的副作用编排（不直接被 UI 调用） |
| [`lesson_link_store.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_link_store.dart) | 词汇/表达首次出现 Lesson 的内存查询表 |
| [`weak_word_quiz_assembler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/weak_word_quiz_assembler.dart) | 从 MistakeProvider 拼装弱词 quiz（30 天 / ≥2 错 / 10 题） |
| [`daily_challenge_assembler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/daily_challenge_assembler.dart) | 从课程树随机抽题合成每日挑战 |
| [`mistake_review_assembler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/mistake_review_assembler.dart) | 把错题重组成 Lesson 形式 |
| [`memory_curve_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/memory_curve_provider.dart) | 记忆曲线数据生成 |
| [`dictionary_search.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/dictionary_search.dart) | 词典全文搜索 |
| [`audio_controller.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/audio_controller.dart) | 统一接管 TTS 与音频播放 |
| [`fun_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/fun_provider.dart) | "Fun" UI 状态（彩蛋 / 表情） |