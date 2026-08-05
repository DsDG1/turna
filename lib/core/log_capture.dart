// Flutter imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 透明度报告用的本地日志捕获器。
///
/// 目的:让用户能直观看到「Turna 实际产生了什么日志」,与隐私详情页的承诺对应。
///
/// 设计原则:
///   - **仅捕获,不替换**:通过 `Logger.addLogListener` 拿事件,
///     绕开全局 `_ReleaseAwareFilter`(见 `core/logger.dart`),因此
///     debug / release 两种 build 都能拿到全量事件。
///   - **内存 ring buffer**:默认 200 条,超出淘汰最旧,O(1) 入队出队。
///   - **节流落盘**:500ms 内的多条日志合并成一次文件写,避免高频刷盘。
///   - **rotate**:单文件 > 1MB 时触发,最多保留 3 个文件
///     (`transparency_log.jsonl` 活跃,`.1.jsonl` / `.2.jsonl` 历史)。
///   - **仅本地**:不联网,不上传,文件位于应用沙箱 documents 目录。
class LogCapture {
  LogCapture._();

  static final LogCapture instance = LogCapture._();

  /// 内存中保存的最近日志,新到旧排序。
  final ValueNotifier<List<LogEntry>> entries =
      ValueNotifier<List<LogEntry>>(const []);

  /// 内存 ring buffer 上限。
  static const int maxEntries = 200;

  /// 落盘节流间隔。
  static const Duration _flushInterval = Duration(milliseconds: 500);

  /// 单文件大小上限,超过就 rotate。
  static const int _maxFileBytes = 1 * 1024 * 1024; // 1MB

  /// 最多保留的 rotate 文件数(不含活跃文件本身)。
  static const int _maxRotatedFiles = 2;

  /// rotate 冷却时间,避免异常情况下短时间内反复重试 rotate。
  static const Duration _rotateCooldown = Duration(seconds: 30);

  /// 活跃文件名,放在应用 documents 目录下。
  static const String _baseName = 'transparency_log';
  static const String _ext = '.jsonl';

  String get _activeFileName => '$_baseName$_ext';
  String _rotatedFileName(int index) => '$_baseName.$index$_ext';

  File? _cachedFile;
  bool _initialized = false;
  bool _installing = false;

  /// 上次 rotate 成功的时间戳;在冷却期内跳过 rotate,避免异常时反复重试。
  DateTime? _lastRotatedAt;

  // 节流落盘相关。
  Timer? _flushTimer;
  final List<LogEntry> _pending = <LogEntry>[];
  bool _flushInFlight = false;

  /// 在应用启动早期调用一次,完成以下工作:
  ///   1. 解析落盘文件路径(应用 documents 目录)
  ///   2. 把已有日志读回内存
  ///   3. 给全局 `Logger` 挂上 listener,后续事件进 buffer + 节流落盘
  Future<void> install() async {
    if (_initialized || _installing) return;
    _installing = true;
    try {
      final file = await _resolveFile();
      _cachedFile = file;
      final loaded = await _readFromFile(file);
      if (loaded.isNotEmpty) {
        entries.value = List.unmodifiable(loaded);
      }
      // 监听新事件。`addLogListener` 在 `Logger.log` 中早于 `_filter.shouldLog`
      // 调用,因此本 capture 接收所有 build 模式下的全量事件。
      Logger.addLogListener(_onLogEvent);
      // 起一个 500ms 周期 timer 合并写。
      _flushTimer ??= Timer.periodic(_flushInterval, (_) => _scheduleFlush());
      // 注册 lifecycle observer,App 退到后台/被挂起时立刻 flush,
      // 避免最后几百毫秒的日志因为 timer 没到而丢失。
      WidgetsBinding.instance.addObserver(_LifecycleFlusher());
      _initialized = true;
    } catch (e, st) {
      // 不让日志系统挂掉应用,只打印到控制台。
      debugPrint('LogCapture.install failed: $e\n$st');
    } finally {
      _installing = false;
    }
  }

  File? get fileForDisplay => _cachedFile;

  /// 全部清空(内存 + 活跃文件 + 所有 rotate 文件)。
  Future<void> clear() async {
    entries.value = const [];
    _pending.clear();
    try {
      final file = _cachedFile;
      if (file != null && await file.exists()) {
        await file.writeAsString('');
      }
      // 同步把历史 rotate 文件也清掉,避免「清空后还残留旧数据」。
      for (var i = 1; i <= _maxRotatedFiles; i++) {
        final rotated = File(
          '${file?.parent.path ?? ''}/${_rotatedFileName(i)}',
        );
        if (await rotated.exists()) {
          await rotated.delete();
        }
      }
    } catch (_) {
      // 忽略:清空失败不影响 UI 行为。
    }
  }

  /// 立即落盘未刷的日志(供测试或退出流程使用)。
  Future<void> flushNow() => _flush();

  /// 同步 flush 然后 dispose,用于测试或显式卸载。
  Future<void> dispose() async {
    await _flush();
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<File> _resolveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_activeFileName');
  }

  Future<List<LogEntry>> _readFromFile(File file) async {
    if (!await file.exists()) return const [];
    try {
      final raw = await file.readAsString();
      final lines = const LineSplitter().convert(raw);
      final out = <LogEntry>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final level = _parseLevel(json['level'] as String?);
          final ts = DateTime.fromMillisecondsSinceEpoch(
            (json['ts'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          );
          out.add(LogEntry(
            timestamp: ts,
            level: level,
            message: (json['msg'] as String?) ?? '',
            error: json['err'] as String?,
            stackTrace: json['st'] as String?,
          ));
        } catch (_) {
          // 单行解析失败,跳过,不影响其它行。
        }
      }
      // 倒序:最新在前。
      return out.reversed.toList(growable: false);
    } catch (e) {
      debugPrint('LogCapture._readFromFile failed: $e');
      return const [];
    }
  }

  void _onLogEvent(LogEvent event) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: event.level,
      message: _stringify(event.message),
      error: event.error?.toString(),
      stackTrace: event.stackTrace?.toString(),
    );

    // 内存 ring buffer:新到旧,超出裁尾。
    final current = entries.value;
    final next = <LogEntry>[entry, ...current];
    if (next.length > maxEntries) {
      next.removeRange(maxEntries, next.length);
    }
    entries.value = List.unmodifiable(next);

    // 进入节流队列。
    _pending.add(entry);
  }

  /// 节流触发:500ms 到了 / 显式 flushNow() / 退出前,统一把 `_pending`
  /// 一次性写完,然后做 size + rotate 检查。
  void _scheduleFlush() {
    if (_pending.isEmpty) return;
    if (_flushInFlight) return;
    _flushInFlight = true;
    unawaited(_flush().whenComplete(() => _flushInFlight = false));
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final file = _cachedFile;
    if (file == null) {
      _pending.clear();
      return;
    }
    // 取出当前待写,清空队列(让后续事件继续累积)。
    final batch = List<LogEntry>.unmodifiable(_pending);
    _pending.clear();
    try {
      final buf = StringBuffer();
      for (final e in batch) {
        buf.writeln(jsonEncode({
          'ts': e.timestamp.millisecondsSinceEpoch,
          'level': _levelToString(e.level),
          'msg': e.message,
          'err': e.error,
          'st': e.stackTrace,
        }));
      }
      await file.writeAsString(
        buf.toString(),
        mode: FileMode.append,
        flush: false,
      );
      // rotate 检查:如果活跃文件 > 1MB,触发轮转。
      await _maybeRotate(file);
    } catch (e) {
      // 落盘失败静默,不打扰调用方;调试期可以打开下面这行。
      debugPrint('LogCapture._flush failed: $e');
    }
  }

  /// 活跃文件超过 [_maxFileBytes] 时,按 `N -> N+1` 顺序平移,丢弃最旧的。
  ///
  /// 冷却期(默认 30 秒)内不会再次触发,避免 IO 失败 / 边界条件下反复 rename。
  Future<void> _maybeRotate(File active) async {
    try {
      final size = await active.length();
      if (size < _maxFileBytes) return;

      // 冷却期检查
      final now = DateTime.now();
      if (_lastRotatedAt != null &&
          now.difference(_lastRotatedAt!) < _rotateCooldown) {
        return;
      }

      // 先把当前 _pending 全部落盘(避免 rotate 丢日志)。
      // 这里不再调 _flush(),因为 _pending 已经在 _flush 之前被清空。
      // 如果用户使用 flushNow() 主动调用,这一步是 no-op。

      final parent = active.parent;
      // 1) 删除最旧的 rotate 文件
      final oldest = File('${parent.path}/${_rotatedFileName(_maxRotatedFiles)}');
      if (await oldest.exists()) {
        await oldest.delete();
      }
      // 2) 依次向前平移:.(N-1) -> .N
      for (var i = _maxRotatedFiles - 1; i >= 1; i--) {
        final src = File('${parent.path}/${_rotatedFileName(i)}');
        if (await src.exists()) {
          await src.rename('${parent.path}/${_rotatedFileName(i + 1)}');
        }
      }
      // 3) 活跃文件 -> .1
      await active.rename('${parent.path}/${_rotatedFileName(1)}');
      // 4) 下一次 _flush() 会按 append mode 自动创建新的活跃文件。
      _lastRotatedAt = DateTime.now();
    } catch (e) {
      debugPrint('LogCapture._maybeRotate failed: $e');
    }
  }

  static String _stringify(Object? msg) {
    if (msg == null) return '';
    if (msg is String) return msg;
    try {
      return msg.toString();
    } catch (_) {
      return '<unprintable>';
    }
  }

  static String _levelToString(Level level) {
    if (level == Level.error) return 'error';
    if (level == Level.warning) return 'warn';
    if (level == Level.info) return 'info';
    if (level == Level.debug) return 'debug';
    if (level == Level.trace) return 'trace';
    if (level == Level.fatal) return 'fatal';
    return 'info';
  }

  static Level _parseLevel(String? s) {
    switch (s) {
      case 'error':
        return Level.error;
      case 'warn':
        return Level.warning;
      case 'debug':
        return Level.debug;
      case 'trace':
        return Level.trace;
      case 'fatal':
        return Level.fatal;
      case 'info':
      default:
        return Level.info;
    }
  }
}

/// 内存中存储的单条日志。
@immutable
class LogEntry {
  final DateTime timestamp;
  final Level level;
  final String message;
  final String? error;

  /// 完整堆栈文本(仅在调用方传入 `stackTrace` 时才会有内容)。
  final String? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  /// 是否为错误级别(warning / error / fatal),用于 UI 区分。
  bool get isAbnormal =>
      level == Level.warning || level == Level.error || level == Level.fatal;

  /// 是否携带可展开的 stack trace。
  bool get hasStackTrace => stackTrace != null && stackTrace!.trim().isNotEmpty;

  String get displayMessage => error == null ? message : '$message — $error';
}

/// App 退到后台 / 被挂起 / 即将销毁时,主动 flush 一次,避免
/// timer 还没到点时进程被回收,导致最后一批日志丢失。
///
/// 只触发 `flushNow()`(fire-and-forget),不 await —— lifecycle 事件
/// 处理函数本身是同步的,阻塞它可能影响 Flutter 框架的 lifecycle 切换。
class _LifecycleFlusher extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(LogCapture.instance.flushNow());
        break;
      case AppLifecycleState.resumed:
        // 不需要做什么,定时器一直在跑。
        break;
    }
  }
}
