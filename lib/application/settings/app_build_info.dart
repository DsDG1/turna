// Package imports:
import 'package:package_info_plus/package_info_plus.dart';

/// Installed-build facts (Plan 2 §7.2). The UI version comes exclusively
/// from `PackageInfo` (via [load]); tests inject values directly. There is
/// deliberately **no hardcoded fallback version** — when package info is
/// unavailable the UI shows [unknownVersion] instead of a made-up number.
class AppBuildInfo {
  const AppBuildInfo({
    required this.versionName,
    required this.buildNumber,
    this.channel,
    this.commit,
  });

  static const String unknownVersion = '未知版本';

  final String versionName;
  final String buildNumber;
  final String? channel;
  final String? commit;

  /// True when [versionName] came from the platform (not the unknown state).
  bool get isKnown => versionName != unknownVersion;

  /// "1.2.3 (+45)" style display, tolerating empty build numbers.
  String get displayVersion {
    if (!isKnown) return unknownVersion;
    if (buildNumber.isEmpty) return versionName;
    return '$versionName (+$buildNumber)';
  }

  static Future<AppBuildInfo> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return AppBuildInfo(
        versionName: info.version,
        buildNumber: info.buildNumber,
      );
    } catch (_) {
      // package_info unavailable (exotic platform / harness): unknown, not
      // a guessed number.
      return const AppBuildInfo(
        versionName: unknownVersion,
        buildNumber: '',
      );
    }
  }

  /// Pre-resolved instance for widget tests and previews.
  static const AppBuildInfo testInstance = AppBuildInfo(
    versionName: '0.0.0-test',
    buildNumber: '1',
  );
}
