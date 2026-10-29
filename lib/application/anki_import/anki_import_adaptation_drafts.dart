import 'package:flutter/foundation.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// 预览期确认的适配方案草稿（scopeKey → plan），只在会话内存在。
///
/// 刻意不写进 staging collection：`promoteStagingCollection` 是否连带搬配置区
/// 属于后端语义，不能假设。用户没提交就退出，这里什么都不落地——原卡与本地
/// 识别结果照旧可用（ADR 0057 §6）。
class AnkiImportAdaptationDrafts extends ChangeNotifier {
  final Map<String, CardAdaptationPlan> _plans = <String, CardAdaptationPlan>{};

  Map<String, CardAdaptationPlan> get plans =>
      Map<String, CardAdaptationPlan>.unmodifiable(_plans);

  bool get isEmpty => _plans.isEmpty;

  bool hasScope(String scopeKey) => _plans.containsKey(scopeKey);

  /// 该笔记类型下是否已有暂存方案（面板按组显示「已暂存」）。
  bool hasNotetype(int notetypeId) {
    final prefix = '$notetypeId:';
    return _plans.keys.any((key) => key.startsWith(prefix));
  }

  /// 同 scope 再次调用即替换（用户改主意）。
  void stage(String scopeKey, CardAdaptationPlan plan) {
    _plans[scopeKey] = plan;
    notifyListeners();
  }


  /// 「恢复原卡」按组操作：清掉这个笔记类型下所有暂存方案。
  void clearNotetype(int notetypeId) {
    final prefix = '$notetypeId:';
    final keys = [
      for (final key in _plans.keys)
        if (key.startsWith(prefix)) key,
    ];
    if (keys.isEmpty) return;
    for (final key in keys) {
      _plans.remove(key);
    }
    notifyListeners();
  }

  /// 方案已经落到 live 之后调用。
  void clearAll() {
    if (_plans.isEmpty) return;
    _plans.clear();
    notifyListeners();
  }
}

