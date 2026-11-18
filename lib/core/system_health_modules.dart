/// Shared diagnostic module identifiers used by [SystemHealthMonitor] when
/// classifying log entries and [SystemHealthPage] when matching advice.
abstract final class SystemHealthModules {
  static const String database = '数据库';
  static const String webView = 'WebView';
  static const String cardRender = '记忆卡渲染';
  static const String ttsAudio = 'TTS / 音频';
  static const String aiNetwork = 'AI 网络';
  static const String courseLoad = '课程加载';
  static const String other = '其他';
}
