// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:turna/application/diagnostics/system_health_policy.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/service/locator.dart';

enum SystemHealthLevel { normal, attention, critical }

/// Persistent, local-only abnormal-log monitor (state machine, Plan §15).
///
/// Concepts kept strictly separate:
///  * `detected`      — error groups exist inside the active window;
///  * `acknowledged`  — the user has seen the alert (never changes facts);
///  * `mitigation`    — safe mode enabled (runtime overlay);
///  * `checkPassed`   — the last self-check passed (DB integrity + recompute);
///  * `resolved`      — system evidence: check passed AND score decayed
///                      below the attention threshold;
///  * `expired`       — no recurrence for [SystemHealthPolicy.autoExpireAfter].
///
/// There is deliberately NO manual score deduction and NO forced page lock:
/// ordinary log errors can interrupt with a banner but can never trap the
/// user on a page. Only [reportDataIntegrityRisk] sets the separate
/// data-integrity flag, which signals a blocking hazard without reusing the
/// log-score machinery.
class SystemHealthMonitor extends ChangeNotifier {
  SystemHealthMonitor(this._prefs, {Future<String> Function()? integrityProbe})
      : _integrityProbe = integrityProbe;

  static const int alertThreshold = SystemHealthPolicy.criticalThreshold;

  final AppPrefs _prefs;
  final Future<String> Function()? _integrityProbe;
  ValueListenable<List<LogEntry>>? _source;
  bool _processing = false;
  bool _installed = false;
  String _appVersion = 'unknown';
  SystemHealthEvent _event = SystemHealthEvent.empty();

  SystemHealthEvent get event => _event;

  /// Severity aggregation of groups inside the active window. Decays by
  /// itself as groups age out — no user action involved.
  int get score => _event.effectiveScore;

  SystemHealthLevel get level => _event.effectiveLevel;

  bool get safeMode => _event.safeMode;

  String get currentAppVersion => _appVersion;

  bool get acknowledged => _event.acknowledged;

  /// System evidence that the problem cleared: last self-check passed and
  /// the decayed score is below the attention threshold.
  bool get resolved =>
      _event.checkPassed &&
      _event.effectiveScore < SystemHealthPolicy.attentionThreshold;

  /// No recurrence for the auto-expire window — treated as gone.
  bool get expired => SystemHealthPolicy.shouldExpire(
        lastAt: _event.lastAt,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );

  /// Unseen, still-active (non-decayed) problems → the UI may show a
  /// non-blocking banner/badge.
  bool get hasUnacknowledgedAlert =>
      !_event.acknowledged &&
      _event.effectiveScore >= SystemHealthPolicy.attentionThreshold;

  /// Dedicated data-integrity hazard flag (Plan §15.3 row 4). Set only via
  /// [reportDataIntegrityRisk] — never derived from log scores. Consumers
  /// must offer backup / export / safe-mode alongside any restriction.
  bool get hasDataIntegrityBlock => _event.dataIntegrityBlock;
  String get dataIntegrityReason => _event.dataIntegrityReason;

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
      final cutoff = DateTime.now().subtract(SystemHealthPolicy.activeWindow);
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
        if (next.id.isEmpty || next.expiredOrResolved) {
          next = SystemHealthEvent.fresh(
            appVersion: _appVersion,
            createdAt: entry.timestamp.millisecondsSinceEpoch,
          );
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
    groups[fingerprint] = SystemHealthErrorGroup(
      fingerprint: fingerprint,
      level: _levelName(entry.level),
      message: redact(entry.displayMessage),
      module: _moduleFor(entry),
      count: (prior?.count ?? 0) + 1,
      firstAt: prior?.firstAt ?? timestamp,
      lastAt: timestamp,
      lastScoredAt: timestamp,
    );
    return current.copyWith(
      firstAt: current.firstAt == 0 ? timestamp : current.firstAt,
      lastAt: timestamp,
      lastProcessedAt: timestamp,
      groups: groups,
      // A new detection reopens the acknowledgement and invalidates prior
      // self-check evidence.
      acknowledged: false,
      checkPassed: false,
    );
  }

  // ── user actions (none of them change detection facts) ──

  /// Marks the alert as seen. Banner/badge hidden until the next detection.
  Future<void> acknowledge() async {
    if (_event.acknowledged) return;
    _event = _event.copyWith(acknowledged: true, dialogShown: true);
    await _save();
    notifyListeners();
  }

  Future<void> markDialogShown() async {
    if (_event.dialogShown) return;
    _event = _event.copyWith(dialogShown: true);
    await _save();
    notifyListeners();
  }

  /// Safe mode is a runtime overlay (mitigation). It never rewrites the
  /// user's Anki settings, so exiting restores the exact pre-safe-mode
  /// values.
  Future<void> setSafeMode(bool enabled) async {
    _event = _event.copyWith(safeMode: enabled);
    await _save();
    notifyListeners();
  }

  // ── system-evidence resolution ──

  /// Runs the self-check (database integrity probe + score recompute).
  /// `resolved` only becomes true when the probe passes AND the decayed
  /// score fell below the attention threshold — clicking nothing can fake
  /// it (Plan §15.4).
  Future<bool> runSelfCheck() async {
    var integrityOk = true;
    String integrityResult = 'ok';
    final probe = _integrityProbe ?? _defaultIntegrityProbe;
    try {
      integrityResult = await probe();
      integrityOk = integrityResult.toLowerCase() == 'ok';
    } catch (error) {
      integrityOk = false;
      integrityResult = '检查失败：$error';
    }
    final nowScore = score;
    final checkPassed =
        integrityOk && SystemHealthPolicy.resolvesAtScore(nowScore);
    _event = _event.copyWith(
      checkPassed: checkPassed,
      dataIntegrityBlock: integrityOk ? false : _event.dataIntegrityBlock,
    );
    await _save();
    notifyListeners();
    if (!integrityOk) {
      debugPrint('SystemHealth self-check integrity: $integrityResult');
    }
    return checkPassed;
  }

  /// Dedicated data-integrity hazard report (Plan §15.3 "data-integrity
  /// blocking"). Only call sites with direct evidence of possible data
  /// corruption may invoke this — never log-score heuristics.
  Future<void> reportDataIntegrityRisk(String reason) async {
    _event = _event.copyWith(
      dataIntegrityBlock: true,
      dataIntegrityReason: redact(reason),
      acknowledged: false,
    );
    await _save();
    notifyListeners();
  }

  Future<String> _defaultIntegrityProbe() async {
    if (!getIt.isRegistered<CourseDatabase>()) return 'ok';
    try {
      final db = getIt<CourseDatabase>();
      final rows = await db.customSelect('PRAGMA integrity_check').get();
      final first = rows.isNotEmpty ? rows.first.data.values.first : 'ok';
      return first.toString();
    } on Object catch (error) {
      return 'probe-error: $error';
    }
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
    required this.firstAt,
    required this.lastAt,
    required this.lastProcessedAt,
    required this.groups,
    required this.dialogShown,
    required this.acknowledged,
    required this.safeMode,
    required this.checkPassed,
    required this.dataIntegrityBlock,
    required this.dataIntegrityReason,
    required this.appVersion,
  });

  factory SystemHealthEvent.empty() => const SystemHealthEvent(
        id: '',
        firstAt: 0,
        lastAt: 0,
        lastProcessedAt: 0,
        groups: {},
        dialogShown: false,
        acknowledged: false,
        safeMode: false,
        checkPassed: false,
        dataIntegrityBlock: false,
        dataIntegrityReason: '',
        appVersion: 'unknown',
      );

  factory SystemHealthEvent.fresh({
    required String appVersion,
    required int createdAt,
  }) =>
      SystemHealthEvent(
        id: 'health-$createdAt',
        firstAt: createdAt,
        lastAt: createdAt,
        lastProcessedAt: createdAt - 1,
        groups: const {},
        dialogShown: false,
        acknowledged: false,
        safeMode: false,
        checkPassed: false,
        dataIntegrityBlock: false,
        dataIntegrityReason: '',
        appVersion: appVersion,
      );

  final String id;
  final int firstAt;
  final int lastAt;
  final int lastProcessedAt;
  final Map<String, SystemHealthErrorGroup> groups;
  final bool dialogShown;

  /// The user has seen this alert. Never changes detection facts — a new
  /// log entry clears it.
  final bool acknowledged;

  /// Mitigation flag (safe-mode runtime overlay).
  final bool safeMode;

  /// The last self-check passed.
  final bool checkPassed;

  /// Dedicated data-integrity hazard (Plan §15.3), independent from log
  /// scores.
  final bool dataIntegrityBlock;
  final String dataIntegrityReason;
  final String appVersion;

  /// Severity aggregation via the policy — decays as groups age out of the
  /// active window.
  int get effectiveScore => SystemHealthPolicy.effectiveScore(
        groups: groups.values.map((group) =>
            (level: group.level, lastAt: group.lastAt, count: group.count)),
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );

  SystemHealthLevel get effectiveLevel {
    final score = effectiveScore;
    if (score >= SystemHealthPolicy.criticalThreshold) {
      return SystemHealthLevel.critical;
    }
    if (score >= SystemHealthPolicy.attentionThreshold) {
      return SystemHealthLevel.attention;
    }
    return SystemHealthLevel.normal;
  }

  /// Whether a fresh detection should start a new event window instead of
  /// accumulating into a resolved/expired one.
  bool get expiredOrResolved =>
      SystemHealthPolicy.shouldExpire(
        lastAt: lastAt,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      ) ||
      (checkPassed && effectiveScore < SystemHealthPolicy.attentionThreshold);

  List<SystemHealthErrorGroup> get topGroups {
    final result = groups.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return result.take(3).toList(growable: false);
  }

  SystemHealthEvent copyWith({
    int? firstAt,
    int? lastAt,
    int? lastProcessedAt,
    Map<String, SystemHealthErrorGroup>? groups,
    bool? dialogShown,
    bool? acknowledged,
    bool? safeMode,
    bool? checkPassed,
    bool? dataIntegrityBlock,
    String? dataIntegrityReason,
  }) =>
      SystemHealthEvent(
        id: id.isEmpty ? 'health-${firstAt ?? this.firstAt}' : id,
        firstAt: firstAt ?? this.firstAt,
        lastAt: lastAt ?? this.lastAt,
        lastProcessedAt: lastProcessedAt ?? this.lastProcessedAt,
        groups: groups ?? this.groups,
        dialogShown: dialogShown ?? this.dialogShown,
        acknowledged: acknowledged ?? this.acknowledged,
        safeMode: safeMode ?? this.safeMode,
        checkPassed: checkPassed ?? this.checkPassed,
        dataIntegrityBlock: dataIntegrityBlock ?? this.dataIntegrityBlock,
        dataIntegrityReason: dataIntegrityReason ?? this.dataIntegrityReason,
        appVersion: appVersion,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstAt': firstAt,
        'lastAt': lastAt,
        'lastProcessedAt': lastProcessedAt,
        'groups': groups.map((key, value) => MapEntry(key, value.toJson())),
        'dialogShown': dialogShown,
        'acknowledged': acknowledged,
        'safeMode': safeMode,
        'checkPassed': checkPassed,
        'dataIntegrityBlock': dataIntegrityBlock,
        'dataIntegrityReason': dataIntegrityReason,
        'appVersion': appVersion,
      };

  factory SystemHealthEvent.fromJson(Map<String, dynamic> json) {
    final groupsJson = Map<String, dynamic>.from(json['groups'] as Map? ?? {});
    return SystemHealthEvent(
      id: json['id'] as String? ?? '',
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
      // Legacy events (pre-state-machine) only had `handled`; map it so an
      // acknowledged alert stays acknowledged after the upgrade.
      acknowledged: (json['acknowledged'] as bool? ?? false) ||
          (json['handled'] as bool? ?? false),
      safeMode: json['safeMode'] as bool? ?? false,
      checkPassed: json['checkPassed'] as bool? ?? false,
      dataIntegrityBlock: json['dataIntegrityBlock'] as bool? ?? false,
      dataIntegrityReason: json['dataIntegrityReason'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? 'unknown',
    );
  }
}
