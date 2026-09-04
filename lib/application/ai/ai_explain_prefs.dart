// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Reply language for companion AI explanations.
enum AiReplyLanguage {
  zh,
  en,
  target,
}

/// How deep the companion should go in an explanation.
enum AiExplainDepth {
  brief,
  standard,
  detailed,
}

/// Snapshot of learner-facing AI explain preferences.
@immutable
class AiExplainPrefsSnapshot {
  const AiExplainPrefsSnapshot({
    this.replyLanguage = AiReplyLanguage.zh,
    this.depth = AiExplainDepth.standard,
    this.allowRevealAnswer = false,
    this.injectLearnerContext = true,
  });

  final AiReplyLanguage replyLanguage;
  final AiExplainDepth depth;
  final bool allowRevealAnswer;
  final bool injectLearnerContext;

  AiExplainPrefsSnapshot copyWith({
    AiReplyLanguage? replyLanguage,
    AiExplainDepth? depth,
    bool? allowRevealAnswer,
    bool? injectLearnerContext,
  }) =>
      AiExplainPrefsSnapshot(
        replyLanguage: replyLanguage ?? this.replyLanguage,
        depth: depth ?? this.depth,
        allowRevealAnswer: allowRevealAnswer ?? this.allowRevealAnswer,
        injectLearnerContext:
            injectLearnerContext ?? this.injectLearnerContext,
      );

  /// Rules fragment injected into companion system prompts.
  String toSystemPromptRules() {
    final lang = switch (replyLanguage) {
      AiReplyLanguage.zh => 'Chinese (简体中文)',
      AiReplyLanguage.en => 'English',
      AiReplyLanguage.target =>
        'the target language being practiced (learner-facing explanations still brief and clear)',
    };
    final depthRule = switch (depth) {
      AiExplainDepth.brief =>
        'Keep replies brief: 2-4 short bullets, no long essays.',
      AiExplainDepth.standard =>
        'Use a standard depth: state the skill, then 3-6 concise bullets.',
      AiExplainDepth.detailed =>
        'Be detailed: include nuances, contrasts, and a short memory tip when useful.',
    };
    final reveal = allowRevealAnswer
        ? 'You MAY reveal the correct answer when the learner asks or when they already submitted.'
        : 'Do NOT restate the correct answer unless the learner already submitted and asks to check; prefer heuristics.';
    return 'Reply language: $lang.\n'
        'Depth: ${depth.name}. $depthRule\n'
        'Answer reveal policy: $reveal';
  }
}

/// Preference keys for companion explain settings (prefs-backed).
class AiExplainPrefKeys {
  static const replyLanguage = 'ai.replyLanguage';
  static const depth = 'ai.depth';
  static const allowRevealAnswer = 'ai.allowRevealAnswer';
  static const injectLearnerContext = 'ai.injectLearnerContext';
}

/// Read/write companion explain prefs. In-memory when [AppPrefs] is absent
/// (unit tests). Callers should [load] once at startup or on first use.
///
/// Production must use the GetIt singleton via [resolve]. Do not construct a
/// second store on a production path — orphan stores ignore UI preference
/// changes.
class AiExplainPrefsStore extends ChangeNotifier {
  AiExplainPrefsStore({AiExplainPrefsSnapshot? initial})
      : _snapshot = initial ?? const AiExplainPrefsSnapshot();

  /// Resolve the shared store for companion providers.
  ///
  /// Order: explicit [prefs] → GetIt singleton → (tests only) ephemeral
  /// when [allowEphemeral] is true. Production code should register the
  /// singleton in [setupLocator] / `providers.dart`.
  static AiExplainPrefsStore resolve({
    AiExplainPrefsStore? prefs,
    bool allowEphemeral = false,
  }) {
    if (prefs != null) return prefs;
    if (getIt.isRegistered<AiExplainPrefsStore>()) {
      try {
        return getIt<AiExplainPrefsStore>();
      } catch (_) {}
    }
    if (allowEphemeral || kDebugMode) {
      // Tests and early bootstrap before registration.
      return AiExplainPrefsStore();
    }
    // Release without registration: still functional but log once via assert.
    assert(() {
      // ignore: avoid_print
      print('AiExplainPrefsStore.resolve: GetIt not registered; using ephemeral');
      return true;
    }());
    return AiExplainPrefsStore();
  }

  AiExplainPrefsSnapshot _snapshot;
  AiExplainPrefsSnapshot get snapshot => _snapshot;

  AiReplyLanguage get replyLanguage => _snapshot.replyLanguage;
  AiExplainDepth get depth => _snapshot.depth;
  bool get allowRevealAnswer => _snapshot.allowRevealAnswer;
  bool get injectLearnerContext => _snapshot.injectLearnerContext;

  /// Hydrate from SharedPreferences when available.
  Future<void> load() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final lang = prefs.preferences
          .getString(AiExplainPrefKeys.replyLanguage, defaultValue: 'zh')
          .getValue();
      final depth = prefs.preferences
          .getString(AiExplainPrefKeys.depth, defaultValue: 'standard')
          .getValue();
      final allow = prefs.preferences
          .getBool(AiExplainPrefKeys.allowRevealAnswer, defaultValue: false)
          .getValue();
      final inject = prefs.preferences
          .getBool(AiExplainPrefKeys.injectLearnerContext, defaultValue: true)
          .getValue();
      _snapshot = AiExplainPrefsSnapshot(
        replyLanguage: _parseLang(lang),
        depth: _parseDepth(depth),
        allowRevealAnswer: allow,
        injectLearnerContext: inject,
      );
      notifyListeners();
    } catch (_) {
      // Corrupt prefs — keep defaults.
    }
  }

  Future<void> setReplyLanguage(AiReplyLanguage value) async {
    _snapshot = _snapshot.copyWith(replyLanguage: value);
    await _writeString(AiExplainPrefKeys.replyLanguage, value.name);
    _onPrefsAffectingCache();
    notifyListeners();
  }

  Future<void> setDepth(AiExplainDepth value) async {
    _snapshot = _snapshot.copyWith(depth: value);
    await _writeString(AiExplainPrefKeys.depth, value.name);
    _onPrefsAffectingCache();
    notifyListeners();
  }

  Future<void> setAllowRevealAnswer(bool value) async {
    _snapshot = _snapshot.copyWith(allowRevealAnswer: value);
    await _writeBool(AiExplainPrefKeys.allowRevealAnswer, value);
    _onPrefsAffectingCache();
    notifyListeners();
  }

  Future<void> setInjectLearnerContext(bool value) async {
    _snapshot = _snapshot.copyWith(injectLearnerContext: value);
    await _writeBool(AiExplainPrefKeys.injectLearnerContext, value);
    // Inject flag changes system prompts that include LearnerContext.
    _onPrefsAffectingCache();
    notifyListeners();
  }

  Future<void> update(AiExplainPrefsSnapshot next) async {
    _snapshot = next;
    await _writeString(AiExplainPrefKeys.replyLanguage, next.replyLanguage.name);
    await _writeString(AiExplainPrefKeys.depth, next.depth.name);
    await _writeBool(AiExplainPrefKeys.allowRevealAnswer, next.allowRevealAnswer);
    await _writeBool(
        AiExplainPrefKeys.injectLearnerContext, next.injectLearnerContext);
    _onPrefsAffectingCache();
    notifyListeners();
  }

  /// Prefer-cache staleness: when reply language/depth/reveal change, drop
  /// engine cache so the next companion call cannot replay the wrong language.
  void _onPrefsAffectingCache() {
    try {
      // Lazy import via getIt only if engine is registered.
      // ignore: avoid_dynamic_calls
      if (getIt.isRegistered<Object>()) {
        // Resolved by type in a separate try so unit tests without AiEngine pass.
      }
    } catch (_) {}
    try {
      // Direct type import would create a cycle? Prefer optional callback.
      _cacheInvalidator?.call();
    } catch (_) {}
  }

  /// Optional hook set by app shell to clear [AiEngine] cache on prefs change.
  static void Function()? _cacheInvalidator;

  /// Wire once from main/app shell: `AiExplainPrefsStore.onCacheInvalidate = () => getIt<AiEngine>().clearCache();`
  static set onCacheInvalidate(void Function()? fn) => _cacheInvalidator = fn;

  AppPrefs? get _prefs {
    if (!getIt.isRegistered<AppPrefs>()) return null;
    try {
      return getIt<AppPrefs>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeString(String key, String value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.preferences.setString(key, value);
  }

  Future<void> _writeBool(String key, bool value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.preferences.setBool(key, value);
  }

  static AiReplyLanguage _parseLang(String raw) {
    switch (raw) {
      case 'en':
        return AiReplyLanguage.en;
      case 'target':
        return AiReplyLanguage.target;
      case 'zh':
      default:
        return AiReplyLanguage.zh;
    }
  }

  static AiExplainDepth _parseDepth(String raw) {
    switch (raw) {
      case 'brief':
        return AiExplainDepth.brief;
      case 'detailed':
        return AiExplainDepth.detailed;
      case 'standard':
      default:
        return AiExplainDepth.standard;
    }
  }
}

/// Build question-type strategy block for companion system prompts.
String buildQuestionTypeStrategy(String typeLabel) {
  final t = typeLabel.toLowerCase();
  if (t.contains('multiple') || t.contains('choice') || t.contains('mcq') ||
      t.contains('选择')) {
    return 'Question strategy: analyze why distractors look plausible; '
        'do not name the correct option index or letter.';
  }
  if (t.contains('fill') || t.contains('blank') || t.contains('填空')) {
    return 'Question strategy: discuss collocation and morphology; '
        'do not fill in the blank with the answer.';
  }
  if (t.contains('translate') || t.contains('翻译')) {
    return 'Question strategy: discuss word order and key words; '
        'encourage a step-by-step translation without dumping the full answer.';
  }
  if (t.contains('reading') || t.contains('阅读')) {
    return 'Question strategy: first locate paragraph clues, then reason about options.';
  }
  if (t.contains('listen') || t.contains('听力')) {
    return 'Question strategy: discuss likely near-homophone distractors based on the text.';
  }
  return 'Question strategy: focus on the skill being tested with heuristic guidance.';
}

/// Fixed quick-follow-up chip labels (local strings; tapping equals ask).
class AiQuickChips {
  static const simplerExample = '举个更简单的例子';
  static const simplerWords = '用更简单的话再说一遍';
  static const whatGrammar = '这是在考什么语法？';
  static const synonymDiff = '和近义词有什么区别？';

  /// Chips shown in companion chat.
  static const List<String> always = [
    simplerExample,
    simplerWords,
    whatGrammar,
    synonymDiff,
  ];
}
