// Project imports:
import 'package:turna/domain/course/lesson.dart';

/// Playground 练习模式目录（计划 §5）。`smartMix` 为主推默认；
/// `dailyMix` 由每日挑战承载（P3）；`translation` 需要宽松判分（P4）。
enum PlaygroundMode {
  smartMix,
  wordMatch,
  quickChoice,
  listenAndPick,
  dictation,
  sentenceOrder,
  fillBlank,
  dailyMix,
  translation,
}

/// 自由练习的内容范围（计划 §4.3）。
enum PlaygroundContentScope {
  /// 最近学习的课程内容。P1 缺少可靠 lesson 完成记录，先回退当前单元。
  recent,

  /// 当前所在 Section 的当前 Unit。
  currentUnit,

  /// 当前语言课程全部语言 Section。
  wholeCourse,

  /// 错题快照与薄弱词条。
  weak,
}

/// 难度（影响智能混合的题型倾斜，计划 §5.1）。
enum PlaygroundDifficulty { easy, standard, challenge }

/// 答题方向（目标语→母语 / 母语→目标语 / 随机）。
enum PlaygroundDirection { targetToNative, nativeToTarget, mixed }

/// 一次 Playground 会话的固定配置。题量在启动前固化，避免设备性能差异
/// 导致完全不同的题量（计划 §4.3）。
class PlaygroundSessionConfig {
  final PlaygroundMode mode;
  final PlaygroundContentScope contentScope;
  final PlaygroundDifficulty difficulty;
  final PlaygroundDirection direction;
  final int targetQuestionCount;
  final bool endless;
  final bool audioEnabled;

  const PlaygroundSessionConfig({
    required this.mode,
    this.contentScope = PlaygroundContentScope.recent,
    this.difficulty = PlaygroundDifficulty.standard,
    this.direction = PlaygroundDirection.mixed,
    this.targetQuestionCount = 10,
    this.endless = false,
    this.audioEnabled = true,
  });

  /// 推荐默认配置（「智能开练」）：3 分钟 / 标准 / 双向随机 / 智能混合。
  factory PlaygroundSessionConfig.smart() => const PlaygroundSessionConfig(
        mode: PlaygroundMode.smartMix,
        contentScope: PlaygroundContentScope.recent,
        difficulty: PlaygroundDifficulty.standard,
        direction: PlaygroundDirection.mixed,
        targetQuestionCount: 10,
      );
}

/// 组装不可用的可解释原因（计划 §7.1）。
enum PlaygroundUnavailableReason {
  /// 当前课程不是语言课程（Anki / Official Anki scope）。
  ineligibleCourse,

  /// 范围内没有任何可用语言内容。
  noCourseContent,

  /// 范围有内容，但该模式没有可用题目。
  noItemsForMode,

  /// 目标 Section 加载失败（任何需要加载 Section 体的范围都可能出现）。
  sectionLoadFailed,

  /// 音频完全不可播放（听力模式）。
  audioUnavailable,
}

/// 已组装会话的元数据：实际题量与来源 lesson，供统计与错题归因。
class PlaygroundSessionMetadata {
  final int questionCount;
  final Set<String> sourceLessonIds;

  const PlaygroundSessionMetadata({
    required this.questionCount,
    required this.sourceLessonIds,
  });
}

/// 组装结果：成功返回 [PlaygroundReady]，失败返回带原因与替代项的
/// [PlaygroundUnavailable]，调用方绝不拿到空白 [Lesson] 当成功。
sealed class PlaygroundAssemblyResult {
  const PlaygroundAssemblyResult();
}

class PlaygroundReady extends PlaygroundAssemblyResult {
  final Lesson lesson;

  /// Word ids backing a word-match session (empty for interaction modes) —
  /// the match controller resolves them into `WordEntry` pairs. Match
  /// sessions do not render [lesson]; it carries an empty stage.
  final Set<String> wordIds;

  final PlaygroundSessionMetadata metadata;

  const PlaygroundReady({
    required this.lesson,
    required this.metadata,
    this.wordIds = const {},
  });
}

class PlaygroundUnavailable extends PlaygroundAssemblyResult {
  final PlaygroundUnavailableReason reason;

  /// 在当前内容下仍可用的模式，供 UI 推荐替代项。
  final Set<PlaygroundMode> availableAlternatives;

  const PlaygroundUnavailable({
    required this.reason,
    this.availableAlternatives = const {},
  });
}
