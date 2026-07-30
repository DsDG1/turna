# 09. 核心工具与扩展

> 路径：`lib/core/`、`lib/service/`、`lib/utils/`

本节覆盖 Core 层的所有工具类、SRS 算法、调度器、扩展函数、横切服务。

---

## 9.1 Core 文件总览

[`lib/core/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/)：

| 文件 | 职责 |
|---|---|
| [`achievement_config.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/achievement_config.dart) | 成就解锁配置（XP / streak 阈值 + gem 奖励） |
| [`enums.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/enums.dart) | 通用枚举（CEFR 等级等） |
| [`extensions.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/extensions.dart) | Dart 内置类型扩展 |
| [`fsrs_engine.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/fsrs_engine.dart) | FSRS 调度器实现（生产默认） |
| [`fsrs_optimizer.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/fsrs_optimizer.dart) | FSRS 个性化权重优化器 |
| [`fsrs_relearn.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/fsrs_relearn.dart) | FSRS 同日 relearn 阶梯 |
| [`logger.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/logger.dart) | 全局 logger（基于 `package:logger`） |
| [`result.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/result.dart) | `Result<T, E>` 错误处理包装 |
| [`sm2.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/sm2.dart) | SM-2 调度器（保留可用） |
| [`spacing.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/spacing.dart) | Material 间距常量 |
| [`srs_scheduler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/srs_scheduler.dart) | `SrsScheduler` 抽象接口 |
| [`streak_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/streak_resolver.dart) | 纯函数 streak 状态机 |
| [`text_styles.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/text_styles.dart) | 全局 TextStyle 常量 |
| [`utils.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/utils.dart) | 通用工具函数 |
| [`verbose.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/verbose.dart) | `veryVerbose` 调试开关 |

---

## 9.2 SRS 调度器（详见 [07-srs-engine.md](./07-srs-engine.md)）

- `SrsScheduler` — 抽象接口
- `Sm2Engine` — SM-2 二元评分调优版
- `FsrsEngine` — FSRS 连续记忆模型（生产默认）
- `FsrsOptimizer` — 用户个性化权重优化

---

## 9.3 Streak 状态机

[`lib/core/streak_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/streak_resolver.dart)：

```dart
class StreakResolution {
  final int newStreak;
  final bool broken;
}

StreakResolution resolveStreakOnPractice({
  required int oldStreak,
  required DateTime? oldDate,
  required DateTime today,
}) {
  if (oldDate == null) {
    return StreakResolution(
      newStreak: oldStreak == 0 ? 1 : oldStreak,
      broken: false,
    );
  }
  final last = DateTime(oldDate.year, oldDate.month, oldDate.day);
  final day = DateTime(today.year, today.month, today.day);
  final gap = day.difference(last).inDays;

  if (gap <= 0) {
    return StreakResolution(newStreak: oldStreak, broken: false);
  }
  if (gap == 1) {
    return StreakResolution(newStreak: oldStreak + 1, broken: false);
  }
  return const StreakResolution(newStreak: 1, broken: true);
}
```

**纯函数，无 I/O**——便于单元测试。

---

## 9.4 成就配置

[`lib/core/achievement_config.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/achievement_config.dart) — 集中所有成就解锁阈值：

```dart
class AchievementConfig {
  static const List<AchievementMilestone> xp = [
    AchievementMilestone(id: 'xp_1000', threshold: 1000, gemReward: 25),
    AchievementMilestone(id: 'xp_10000', threshold: 10000, gemReward: 100),
    AchievementMilestone(id: 'xp_50000', threshold: 50000, gemReward: 250),
  ];

  static const List<AchievementMilestone> streak = [
    AchievementMilestone(id: 'streak_3', threshold: 3, gemReward: 15),
    AchievementMilestone(id: 'streak_7', threshold: 7, gemReward: 50),
    AchievementMilestone(id: 'streak_30', threshold: 30, gemReward: 200),
    AchievementMilestone(id: 'streak_100', threshold: 100, gemReward: 500),
    AchievementMilestone(id: 'streak_365', threshold: 365, gemReward: 1000),
  ];

  static int gemsForThreshold(
    List<AchievementMilestone> list,
    int value,
    Set<String> achievements,
  );
}
```

---

## 9.5 Result 类型

[`lib/core/result.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/result.dart)：

```dart
sealed class Result<T, E> {
  bool get isOk;
  bool get isErr;
  T? get value;
  E? get error;

  factory Result.ok(T value);
  factory Result.err(E error);
}

class Ok<T, E> extends Result<T, E> { ... }
class Err<T, E> extends Result<T, E> { ... }
```

**用途**：替代 throw/catch，统一错误返回。

---

## 9.6 Logger

[`lib/core/logger.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/logger.dart) — 基于 `package:logger` 的全局 logger：

```dart
final Logger logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

logger.i('info');
logger.w('warn');
logger.e('error', error: e, stackTrace: st);
```

`main.dart` 中 `_installGlobalErrorHandlers()` 把 `FlutterError.onError` 和 `PlatformDispatcher.instance.onError` 都路由到这里。

---

## 9.7 文本样式与间距

- [`lib/core/text_styles.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/text_styles.dart) — 全局 `AppTextStyles` 常量
- [`lib/core/spacing.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/spacing.dart) — Material 间距规范

---

## 9.8 扩展与工具

- [`lib/core/extensions.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/extensions.dart) — Dart 内置类型扩展（如 `String.capitalize()`）
- [`lib/core/utils.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/utils.dart) — 通用工具函数
- [`lib/core/verbose.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/verbose.dart) — `veryVerbose` 全局开关（默认 false）

---

## 9.9 Service 层

[`lib/service/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/)：

### 9.9.1 AppPrefs / LocalStateKeys

[`lib/service/locator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/locator.dart) — 封装 `StreamingSharedPreferences`，提供 `AppPrefs`：

```dart
class AppPrefs {
  final StreamingSharedPreferences preferences;
  final Preference<LocalUser> authUser;
  final Preference<String> currentLanguage;     // "turkish"
  final Preference<String> courseScope;         // '' | 'anki:<id>'

  Future<bool> setBool(String key, {required bool value});
  Future<bool> setInt(String key, int value);
  Future<bool> setString(String key, String value);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> setCustomValue<T>(String key, T value, PreferenceAdapter<T> adapter);
  Future<bool> setLocalUser(LocalUser user);
}
```

**`LocalStateKeys`** — 全部 prefs key 常量：

```dart
class LocalStateKeys {
  static const String score = 'game.score';
  static const String streak = 'game.streak';
  static const String lastStreakDate = 'game.lastStreakDate';
  static const String completedLessonIds = 'progress.completedLessonIds';
  static const String perfectLessonIds = 'progress.perfectLessonIds';
  static const String gems = 'currency.gems';
  static const String achievements = 'achievements.unlocked';

  // SRS
  static const String srsState = 'srs.state';                  // legacy blob (v7 前)
  static const String srsDesiredRetention = 'srs.desiredRetention';
  static const String srsFsrsParameters = 'srs.fsrsParameters';
  static const String srsFsrsOptimizedAt = 'srs.fsrsOptimizedAt';
  static const String srsFsrsOptimizedReviews = 'srs.fsrsOptimizedReviews';
  static const String lessonWordLinks = 'srs.lessonWordLinks';
  static const String grammarReviewState = 'grammarReview.state';

  // Mistake
  static const String mistakeLog = 'mistake.log';

  // Settings
  static const String themeMode = 'settings.themeMode';
  static const String soundEffects = 'settings.soundEffects';
  static const String haptic = 'settings.haptic';
  static const String ttsSpeed = 'settings.ttsSpeed';
  static const String ttsEngine = 'settings.ttsEngine';           // legacy
  static const String ttsAvailabilityPromptShown = '...';

  // Reminder
  static const String dailyReminderEnabled = 'settings.dailyReminderEnabled';
  static const String dailyReminderHour = 'settings.dailyReminderHour';
  static const String dailyReminderMinute = 'settings.dailyReminderMinute';

  // AI
  static const String aiCacheEnabled = 'settings.aiCacheEnabled';
  static const String aiRecentTasks = 'ai.recentTasks';

  // Xiaoyi hint
  static const String useXiaoyiHint = 'settings.useXiaoyiHint';
}
```

### 9.9.2 `setupLocator()`

```dart
Future<void> setupLocator() async {
  final prefs = await StreamingSharedPreferences.instance;
  getIt.registerSingleton<AppPrefs>(AppPrefs(prefs));

  final tts = FlutterTts();
  await tts.setLanguage('tr');
  await tts.setSpeechRate(0.5);
  getIt.registerSingleton<FlutterTts>(tts);

  // CourseDatabase + DatabaseSeeder
  final db = CourseDatabase(_queryExecutor());
  getIt.registerSingleton<CourseDatabase>(db);
  await DatabaseSeeder(db).seedIfNeeded();

  // ... other singletons
}
```

### 9.9.3 TabRouter

[`lib/service/tab_router.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/tab_router.dart) — 跨页面 Tab 切换的 ValueNotifier：

```dart
class TabRouter {
  final ValueNotifier<int> index = ValueNotifier(0);

  void go(int i);
  void goHome();
  void goPlay();
  void goProfile();
  void goSettings();
  void goAi();
}
```

`HomePage` 监听 `index` → `setState`。其他页面用 `TabRouter.go(0)` 跳转。

### 9.9.4 LocalReminderService

[`lib/service/local_reminder_service.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/local_reminder_service.dart) — 基于 `flutter_local_notifications` 的本地提醒：

```dart
@lazySingleton
class LocalReminderService {
  Future<void> applyFromSettings({
    required bool enabled,
    required TimeOfDay time,
  });

  Future<void> cancel();
  Future<void> scheduleDaily({required int hour, required int minute});
}
```

**重要**：**不提供 streak repair**。

### 9.9.5 TtsAvailabilityChecker

[`lib/service/tts_availability_checker.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/tts_availability_checker.dart) — TTS 可用性检查 + Android 优先选 Google TTS：

```dart
@lazySingleton
class TtsAvailabilityChecker {
  Future<void> configureSystemEngine();   // Android → Google TTS
  Future<bool> isTurkishAvailable();
}
```

### 9.9.6 ExportService

[`lib/service/export_service.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/export_service.dart) — 学习进度 JSON 导出 / 导入。

### 9.9.7 XiaoyiService

[`lib/service/xiaoyi_service.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/xiaoyi_service.dart) — "小蚁" AI 助手服务（基于 useXiaoyiHint 设置）。

---

## 9.10 Utils

[`lib/utils/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/utils/)：

| 文件 | 用途 |
|---|---|
| [`ohos_file_picker.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/utils/ohos_file_picker.dart) | 鸿蒙平台原生文件选择器 fallback |

---

## 9.11 Course Loader / Validator

[`lib/courses/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/) — 课程加载与校验：

| 文件 | 职责 |
|---|---|
| [`course_loader.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/course_loader.dart) | 从 `assets/courses/turkish/` 加载 + 规范化 |
| [`course_validator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/course_validator.dart) | 课程结构 / 引用完整性校验 |
| [`alphabets/alphabet.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/alphabets/alphabet.dart) | 字母表数据 |
| [`alphabets/alphabets.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/alphabets/alphabets.dart) | 多语种字母表注册 |
| [`alphabets/resource.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/alphabets/resource.dart) | 字母表资源 |
| [`languages/course_lookup.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/languages/course_lookup.dart) | 全局同步查找表（vocab / grammar / expressions） |
| [`languages/vocab.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/languages/vocab.dart) | 词汇同步加载 |
| [`languages/grammar_points.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/languages/grammar_points.dart) | 语法点同步加载 |
| [`languages/expressions.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/Varnamalaplus/lib/courses/languages/expressions.dart) | 表达同步加载 |
| [`languages/dictionary.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/languages/dictionary.dart) | 词典全文索引 |
| [`languages/languages.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/languages/languages.dart) | 多语种注册 |
| [`languages/vocab_audio_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/languages/vocab_audio_resolver.dart) | 词汇音频解析（具体实现，配合 domain 抽象） |

### 9.11.1 CourseLoader

[`course_loader.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/course_loader.dart)：

```dart
class CourseLoader {
  static const String indexAsset = 'assets/courses/turkish/index.json';
  static const String vocabAsset = 'assets/courses/turkish/vocab.json';
  static const String grammarPointsAsset = 'assets/courses/turkish/grammar_points.json';
  static const String expressionsAsset = 'assets/courses/turkish/expressions.json';

  Future<List<Section>> loadAllSections();
  Section? loadSectionFromCache(String id);  // 内存缓存
  static void invalidateCaches();
}
```

### 9.11.2 CourseValidator

[`course_validator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/course_validator.dart)：

```dart
class CourseValidator {
  static const int MAX_UNITS_PER_SECTION = 60;
  static const int MAX_LESSONS_PER_UNIT = 40;

  /// Returns a list of validation errors. Empty = valid.
  static List<ValidationError> validate(Section section);

  /// Pretty JSON output
  static String formatErrorsJson(List<ValidationError> errors);
}
```

**校验规则**：
- Section ID / Unit ID / Lesson ID 唯一
- prerequisite id 存在
- vocabulary / grammarPoint / expression 引用存在
- interaction schema 合规
- 单元数 / 课数不超过 ceiling

---

## 9.12 服务装配流程

```dart
// lib/main.dart
Future<void> main() async {
  _installGlobalErrorHandlers();
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();   // 1. GetIt 注册 (@injectable)
  await setupLocator();      // 2. 异步初始化 (prefs / db / tts / seeder)
  runApp(const VarnamalaApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await loadVocabulary();           // 3. 同步查找表
    await loadGrammarPoints();
    await loadExpressions();

    await getIt<SrsProvider>().ensureLoaded();
    await getIt<GrammarReviewProvider>().ensureLoaded();

    await getIt<CourseProvider>().load();

    if (!kIsWeb) {
      await getIt<TtsAvailabilityChecker>().configureSystemEngine();
      // 4. 应用每日提醒设置
      try {
        final settings = getIt<SettingsProvider>();
        await getIt<LocalReminderService>().applyFromSettings(
          enabled: settings.dailyReminderEnabled,
          time: settings.dailyReminderTime,
        );
      } catch (_) {/* best-effort */}
    }
  });
}
```