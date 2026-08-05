// Package imports:
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// App-wide logger.
///
/// 在 logger 2.7 中,事件流程是:
///   1. 构造 LogEvent
///   2. 派发给所有 addLogListener 注册的回调 ← `LogCapture` 在这里挂载
///   3. _filter.shouldLog() 决定是否走 printer/output(控制台)
///
/// 因此 [LogCapture] 在 debug / release 两种 build 下都能拿到全量事件,
/// 与本 filter 无关;本 filter 只控制控制台是否打印。
///
/// 行为:
///   - debug / profile:全等级打印到控制台
///   - release:只允许 warn / error 走到控制台,避免淹没生产日志
///
/// 这是个离线 app —— 日志只走控制台与平台 log,从不发到远程后端。
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 80,
    noBoxingByDefault: true,
  ),
  filter: _ReleaseAwareFilter(),
);

/// 只对**控制台输出**生效:release 模式下低于 warn 的不打印。
///
/// 不影响 [LogCapture] —— 它通过 `Logger.addLogListener` 拿事件,绕开本 filter。
class _ReleaseAwareFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kReleaseMode) {
      return event.level.index >= Level.warning.index;
    }
    return true;
  }
}
