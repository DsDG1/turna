// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:turna/core/log_capture.dart';
import 'package:turna/service/locator.dart';

enum SystemHealthLevel { normal, attention, critical }

/// Persistent, local-only abnormal-log monitor. It scores deduplicated error
/// groups independently of the transparency page, so warnings are observable
/// even when the user never opens raw logs.
class SystemHealthMonitor extends ChangeNotifier {
  SystemHealthMonitor(this._prefs);

  static const int alertThreshold = 40;

  final AppPrefs _prefs;
  ValueListenable<List<LogEntry>>? _source;
  bool _processing = false;
  bool _installed = false;
  String _appVersion = 'unknown';
  SystemHealthEvent _event = SystemHealthEvent.empty();

  SystemHealthEvent get event => _event;
  SystemHealthLevel get level => _event.level;
  int get score => _event.score;
  bool get safeMode => _event.safeMode;
  String get currentAppVersion => _appVersion;

  bool get isScoreExceeded => _event.score >= alertThreshold;

  bool get shouldForceRedirect =>
      !_event.handled && isScoreExceeded;

  bool get hasActiveAlert =>
      !_event.handled && (level != SystemHealthLevel.normal || isScoreExceeded);

  bool get shouldShowCriticalDialog =>
      hasActiveAlert &&
      level == SystemHealthLevel.critical &&
      !_event.dialogShown;

  Future<void> install(ValueListenable<List<LogEntry>> source) async {
    if (_installed) return;
    _installed = true;
    _source = source;
    await _load();
    try {
      final package = await PackageInfo.fromPlatform();
      _appVersion = '${package.version}+${package.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    source.addListener(_onLogsChanged);
    await _process(source.value);
  }

  void _onLogsChanged() {
    final source = _source;
    if (source == null || _processing) return;
    unawaited(_process(source.value));
  }

  Future<void> _process(List<LogEntry> entries) async {
    if (_processing) return;
    _processing = true;
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final candidates = entries
          .where((entry) =>
              entry.isAbnormal &&
              entry.timestamp.isAfter(cutoff) &&
              entry.timestamp.millisecondsSinceEpoch > _event.lastProcessedAt)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (candidates.isEmpty) return;

      var next = _event;
      for (final entry in candidates) {
        if (next.id.isEmpty || next.handled) {
          final remainingScore = next.score;
          next = SystemHealthEvent.fresh(
            appVersion: _appVersion,
            createdAt: entry.timestamp.millisecondsSinceEpoch,
          ).copyWith(score: remainingScore);
        }
        next = _addEntry(next, entry);
      }
      _event = next;
      await _save();
      notifyListeners();
    } catch (_) {
      // Never log through the app logger here: monitor failures must not feed
      // back into the monitor and create an alert storm.
    } finally {
      _processing = false;
      final source = _source;
      if (source != null &&
          source.value.any((entry) =>
              entry.isAbnormal &&
              entry.timestamp.millisecondsSinceEpoch >
                  _event.lastProcessedAt)) {
        scheduleMicrotask(_onLogsChanged);
      }
    }
  }

  SystemHealthEvent _addEntry(SystemHealthEvent current, LogEntry entry) {
    final fingerprint = fingerprintFor(entry);
    final groups = Map<String, SystemHealthErrorGroup>.of(current.groups);
    final prior = groups[fingerprint];
    final timestamp = entry.timestamp.millisecondsSinceEpoch;
    final scoreDelta = entry.level == Level.fatal
        ? alertThreshold
        : prior != null && timestamp - prior.lastScoredAt < 60000
            ? 0
            : entry.level == Level.error
                ? 3
                : 1;
    groups[fingerprint] = SystemHealthErrorGroup(
      fingerprint: fingerprint,
      level: _levelName(entry.level),
      message: redact(entry.displayMessage),
      module: _moduleFor(entry),
      count: (prior?.count ?? 0) + 1,
      firstAt: prior?.firstAt ?? timestamp,
      lastAt: timestamp,
      lastScoredAt: scoreDelta == 0 ? prior!.lastScoredAt : timestamp,
    );
    final score = entry.level == Level.fatal
        ? current.score < alertThreshold
            ? alertThreshold
            : current.score + 10
        : current.score + scoreDelta;
    return current.copyWith(
      score: score,
      firstAt: current.firstAt == 0 ? timestamp : current.firstAt,
      lastAt: timestamp,
      lastProcessedAt: timestamp,
      groups: groups,
      level: score >= alertThreshold
          ? SystemHealthLevel.critical
          : score >= 10
              ? SystemHealthLevel.attention
              : SystemHealthLevel.normal,
    );
  }

  Future<void> markDialogShown() async {
    if (_event.dialogShown) return;
    _event = _event.copyWith(dialogShown: true);
    await _save();
    notifyListeners();
  }

  Future<void> acknowledge() async {
    _event = _event.copyWith(acknowledged: true, dialogShown: true);
    await _save();
    notifyListeners();
  }

  /// Reduces the current system health score by [delta] (defaults to 40),
  /// never dropping below 0. If the remaining score is below [alertThreshold],
  /// the active interrupt/alert lock is resolved.
  Future<void> confirmAndDeductScore([int delta = alertThreshold]) async {
    final nextScore = math.max(0, _event.score - delta);
    final nextLevel = nextScore >= alertThreshold
        ? SystemHealthLevel.critical
        : nextScore >= 10
            ? SystemHealthLevel.attention
            : SystemHealthLevel.normal;
    final isResolved = nextScore < alertThreshold;
    _event = _event.copyWith(
      score: nextScore,
      level: nextLevel,
      handled: isResolved,
      acknowledged: true,
      dialogShown: true,
      safeMode: isResolved ? false : _event.safeMode,
    );
    await _save();
    notifyListeners();
  }

  /// Starts a new scoring window without deleting raw logs.
  Future<void> markHandled() async {
    await confirmAndDeductScore(alertThreshold);
  }

  /// Safe mode is a runtime overlay. It never rewrites the user's Anki
  /// settings, so exiting restores the exact pre-safe-mode values.
  Future<void> setSafeMode(bool enabled) async {
    _event = _event.copyWith(safeMode: enabled);
    await _save();
    notifyListeners();
  }

  Future<void> _load() async {
    final raw = _prefs.preferences
        .getString(LocalStateKeys.systemHealthEvent, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return;
    try {
      _event = SystemHealthEvent.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      _event = SystemHealthEvent.empty();
    }
  }

  Future<void> _save() => _prefs.setString(
        LocalStateKeys.systemHealthEvent,
        jsonEncode(_event.toJson()),
      );

  static String fingerprintFor(LogEntry entry) {
    final stack = (entry.stackTrace ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(3)
        .join('|');
    return '${_levelName(entry.level)}|${_normalise(entry.message)}|'
        '${_normalise(entry.error ?? '')}|${_normalise(stack)}|${_moduleFor(entry)}';
  }

  static String _normalise(String value) => value
      .replaceAll(RegExp(r'[A-Za-z]:[\\/][^\s:]+'), '<path>')
      .replaceAll(RegExp(r'/(?:Users|home|data|storage)/[^\s:]+'), '<path>')
      .replaceAll(
        RegExp(r'\b[0-9a-f]{8}-[0-9a-f-]{27,}\b', caseSensitive: false),
        '<id>',
      )
      .replaceAll(RegExp(r'\b[0-9a-f]{16,}\b', caseSensitive: false), '<id>')
      .replaceAll(RegExp(r'\b\d{4,}\b'), '<n>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static String redact(String value) => value
      .replaceAll(
        RegExp(r'(sk-|key[-_ ]?|bearer )[A-Za-z0-9._-]{8,}',
            caseSensitive: false),
        '<redacted>',
      )
      .replaceAll(RegExp(r'[A-Za-z]:[\\/][^\s]+'), '<personal-path>')
      .replaceAll(RegExp(r'/(?:Users|home)/[^\s]+'), '<personal-path>');

  static String _moduleFor(LogEntry entry) {
    final text = '${entry.message} ${entry.stackTrace ?? ''}'.toLowerCase();
    if (text.contains('sqlite') || text.contains('database')) {
      return '数据库';
    }
    if (text.contains('webview') || text.contains('javascript')) {
      return 'WebView';
    }
    if (text.contains('anki')) {
      return 'Anki 渲染';
    }
    if (text.contains('tts') || text.contains('audio')) {
      return 'TTS / 音频';
    }
    if (text.contains('ai') || text.contains('http')) {
      return 'AI 网络';
    }
    if (text.contains('course') || text.contains('lesson')) {
      return '课程加载';
    }
    return '其他';
  }

  static String _levelName(Level level) {
    if (level == Level.fatal) return 'fatal';
    if (level == Level.error) return 'error';
    return 'warning';
  }
}

@immutable
class SystemHealthErrorGroup {
  const SystemHealthErrorGroup({
    required this.fingerprint,
    required this.level,
    required this.message,
    required this.module,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.lastScoredAt,
  });

  final String fingerprint;
  final String level;
  final String message;
  final String module;
  final int count;
  final int firstAt;
  final int lastAt;
  final int lastScoredAt;

  bool get ongoing => DateTime.now().millisecondsSinceEpoch - lastAt < 300000;

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'level': level,
        'message': message,
        'module': module,
        'count': count,
        'firstAt': firstAt,
        'lastAt': lastAt,
        'lastScoredAt': lastScoredAt,
      };

  factory SystemHealthErrorGroup.fromJson(Map<String, dynamic> json) =>
      SystemHealthErrorGroup(
        fingerprint: json['fingerprint'] as String? ?? '',
        level: json['level'] as String? ?? 'warning',
        message: json['message'] as String? ?? '',
        module: json['module'] as String? ?? '其他',
        count: (json['count'] as num? ?? 0).toInt(),
        firstAt: (json['firstAt'] as num? ?? 0).toInt(),
        lastAt: (json['lastAt'] as num? ?? 0).toInt(),
        lastScoredAt: (json['lastScoredAt'] as num? ?? 0).toInt(),
      );
}

@immutable
class SystemHealthEvent {
  const SystemHealthEvent({
    required this.id,
    required this.level,
    required this.score,
    required this.firstAt,
    required this.lastAt,
    required this.lastProcessedAt,
    required this.groups,
    required this.dialogShown,
    required this.acknowledged,
    required this.handled,
    required this.safeMode,
    required this.appVersion,
  });

  factory SystemHealthEvent.empty() => const SystemHealthEvent(
        id: '',
        level: SystemHealthLevel.normal,
        score: 0,
        firstAt: 0,
        lastAt: 0,
        lastProcessedAt: 0,
        groups: {},
        dialogShown: false,
        acknowledged: false,
        handled: false,
        safeMode: false,
        appVersion: 'unknown',
      );

  factory SystemHealthEvent.fresh({
    required String appVersion,
    required int createdAt,
  }) =>
      SystemHealthEvent(
        id: 'health-$createdAt',
        level: SystemHealthLevel.normal,
        score: 0,
        firstAt: createdAt,
        lastAt: createdAt,
        lastProcessedAt: createdAt - 1,
        groups: const {},
        dialogShown: false,
        acknowledged: false,
        handled: false,
        safeMode: false,
        appVersion: appVersion,
      );

  final String id;
  final SystemHealthLevel level;
  final int score;
  final int firstAt;
  final int lastAt;
  final int lastProcessedAt;
  final Map<String, SystemHealthErrorGroup> groups;
  final bool dialogShown;
  final bool acknowledged;
  final bool handled;
  final bool safeMode;
  final String appVersion;

  List<SystemHealthErrorGroup> get topGroups {
    final result = groups.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return result.take(3).toList(growable: false);
  }

  SystemHealthEvent copyWith({
    SystemHealthLevel? level,
    int? score,
    int? firstAt,
    int? lastAt,
    int? lastProcessedAt,
    Map<String, SystemHealthErrorGroup>? groups,
    bool? dialogShown,
    bool? acknowledged,
    bool? handled,
    bool? safeMode,
  }) =>
      SystemHealthEvent(
        id: id.isEmpty ? 'health-${firstAt ?? this.firstAt}' : id,
        level: level ?? this.level,
        score: score ?? this.score,
        firstAt: firstAt ?? this.firstAt,
        lastAt: lastAt ?? this.lastAt,
        lastProcessedAt: lastProcessedAt ?? this.lastProcessedAt,
        groups: groups ?? this.groups,
        dialogShown: dialogShown ?? this.dialogShown,
        acknowledged: acknowledged ?? this.acknowledged,
        handled: handled ?? this.handled,
        safeMode: safeMode ?? this.safeMode,
        appVersion: appVersion,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level.name,
        'score': score,
        'firstAt': firstAt,
        'lastAt': lastAt,
        'lastProcessedAt': lastProcessedAt,
        'groups': groups.map((key, value) => MapEntry(key, value.toJson())),
        'dialogShown': dialogShown,
        'acknowledged': acknowledged,
        'handled': handled,
        'safeMode': safeMode,
        'appVersion': appVersion,
      };

  factory SystemHealthEvent.fromJson(Map<String, dynamic> json) {
    final groupsJson = Map<String, dynamic>.from(json['groups'] as Map? ?? {});
    return SystemHealthEvent(
      id: json['id'] as String? ?? '',
      level: SystemHealthLevel.values
              .where((item) => item.name == json['level'])
              .firstOrNull ??
          SystemHealthLevel.normal,
      score: (json['score'] as num? ?? 0).toInt(),
      firstAt: (json['firstAt'] as num? ?? 0).toInt(),
      lastAt: (json['lastAt'] as num? ?? 0).toInt(),
      lastProcessedAt: (json['lastProcessedAt'] as num? ?? 0).toInt(),
      groups: {
        for (final entry in groupsJson.entries)
          entry.key: SystemHealthErrorGroup.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
      dialogShown: json['dialogShown'] as bool? ?? false,
      acknowledged: json['acknowledged'] as bool? ?? false,
      handled: json['handled'] as bool? ?? false,
      safeMode: json['safeMode'] as bool? ?? false,
      appVersion: json['appVersion'] as String? ?? 'unknown',
    );
  }
}
