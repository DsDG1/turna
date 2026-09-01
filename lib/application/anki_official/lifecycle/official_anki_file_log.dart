import 'package:flutter/foundation.dart' show debugPrint;
import 'package:turna/core/logger.dart';

/// D8 文件日志通道（step4.md C1，Step 1 发现 #4 的答复）。
///
/// `LogCapture` 已把全局 [logger] 的事件滚动落盘到
/// `transparency_log.jsonl`（1MB 轮转 ×3，修复中心可带出）——但 Anki
/// 路径此前全走 `debugPrint`，厂商 logcat 静默时完全不可观测。本助手
/// 把关键路径（启动恢复、commit 窗口、维护任务、视图重建、retiring
/// 序列）同时送到控制台与文件；调用处保留原 `debugPrint` 语义，只增
/// 不减，不改变任何行为。
///
/// 纯本地：不联网、不上传；文件位于应用沙箱。
void officialAnkiFileLog(
  String channel,
  Object? message, {
  bool warning = false,
  Object? error,
}) {
  final line = '[$channel] $message';
  if (warning) {
    logger.w(line, error: error);
  } else {
    logger.i(line);
  }
  debugPrint(line);
}

/// 启动恢复日志（doc 41 §7 / step4.md C1 覆盖清单第一项）。
void officialAnkiStartupLog(Object? message, {bool warning = false}) =>
    officialAnkiFileLog('OfficialAnkiStartup', message, warning: warning);

/// 维护任务日志（GC / VACUUM / v2 job）。
void officialAnkiMaintenanceLog(Object? message, {bool warning = false}) =>
    officialAnkiFileLog('OfficialAnkiMaintenance', message,
        warning: warning);

/// v2 链路日志（导入 commit / 视图重建 / retiring）。
void officialAnkiV2Log(Object? message, {bool warning = false}) =>
    officialAnkiFileLog('OfficialAnkiV2', message, warning: warning);
