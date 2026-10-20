// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_prompt_catalog.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// 用户对系统提示词的追加要求（按功能分别保存）。
///
/// 存的是**追加块**，不是完整替换：默认提示词仍由 [AiPromptCatalog] 提供，
/// 面板里显示的「生效版本」= 默认 + 本 store 的文本。这样产品安全边界
/// （不许输出课程 JSON、未作答时不许直接给答案）不会因为一次自定义而失效。
///
/// 存储：SharedPreferences 单键 `ai.promptOverrides.v1`，值是
/// `{"freeChat": "...", ...}`。不进安全存储——这不是密钥。
class AiPromptOverridesStore extends ChangeNotifier {
  AiPromptOverridesStore({Map<AiPromptFeature, String>? initial})
      : _overrides = Map<AiPromptFeature, String>.from(initial ?? const {});

  /// Prefs key。带版本后缀：形状变了就换 key，旧值自然作废，不需要迁移逻辑。
  static const String prefsKey = 'ai.promptOverrides.v1';

  /// 进程内兜底实例。
  ///
  /// provider 与页面必须拿到**同一个** store，否则用户在面板里保存的文本
  /// 对已被构造出来的 provider 不可见。生产路径应当由
  /// `getIt<AiPromptOverridesStore>()` 提供；GetIt 未注册时（单测、早期
  /// bootstrap）退回到这个进程内单例，而不是每次新建。
  static AiPromptOverridesStore? _fallback;

  /// 取共享实例：显式传入 → GetIt → 进程内兜底。
  static AiPromptOverridesStore resolve({AiPromptOverridesStore? store}) {
    if (store != null) return store;
    if (getIt.isRegistered<AiPromptOverridesStore>()) {
      try {
        return getIt<AiPromptOverridesStore>();
      } catch (_) {
        // 可选依赖解析失败：继续走进程内兜底。
      }
    }
    return _fallback ??= AiPromptOverridesStore();
  }

  /// 仅供测试重置进程内兜底，避免用例之间互相污染。
  @visibleForTesting
  static void resetFallbackForTest() => _fallback = null;

  final Map<AiPromptFeature, String> _overrides;

  /// 当前功能的追加文本；没有自定义时是空串。
  String textFor(AiPromptFeature feature) => _overrides[feature] ?? '';

  bool isOverridden(AiPromptFeature feature) =>
      textFor(feature).trim().isNotEmpty;

  /// 有自定义的功能列表（面板上打点用）。
  List<AiPromptFeature> get customised => [
        for (final f in AiPromptFeature.values)
          if (isOverridden(f)) f,
      ];

  /// 保存追加文本。空串等价于清除。超长直接截断而不是静默丢弃：
  /// 用户看得见自己输入的最后一段被削掉，比「保存了但没生效」好。
  Future<void> setText(AiPromptFeature feature, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return clear(feature);
    _overrides[feature] = trimmed.length > kAiPromptOverrideMaxChars
        ? trimmed.substring(0, kAiPromptOverrideMaxChars)
        : trimmed;
    notifyListeners();
    await _persist();
  }

  Future<void> clear(AiPromptFeature feature) async {
    if (_overrides.remove(feature) == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    if (_overrides.isEmpty) return;
    _overrides.clear();
    notifyListeners();
    await _persist();
  }

  /// 启动时从 prefs 读回。损坏的 blob 全部丢弃（回到默认），不影响启动。
  Future<void> load() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final raw =
          prefs.preferences.getString(prefsKey, defaultValue: '').getValue();
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _overrides.clear();
      for (final entry in decoded.entries) {
        final feature = _parseFeature(entry.key.toString());
        final value = entry.value;
        if (feature == null || value is! String) continue;
        if (value.trim().isEmpty) continue;
        _overrides[feature] = value;
      }
      notifyListeners();
    } catch (e) {
      // 读取失败不是致命问题：按「全部默认」继续，用户重新输入即可。
      logger.w('AiPromptOverridesStore.load failed: $e');
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final payload = <String, String>{
      for (final entry in _overrides.entries) entry.key.name: entry.value,
    };
    await prefs.preferences.setString(prefsKey, jsonEncode(payload));
  }

  AppPrefs? get _prefs {
    if (!getIt.isRegistered<AppPrefs>()) return null;
    try {
      return getIt<AppPrefs>();
    } catch (_) {
      return null;
    }
  }

  static AiPromptFeature? _parseFeature(String name) {
    for (final f in AiPromptFeature.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}
