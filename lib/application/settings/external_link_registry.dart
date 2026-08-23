// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';

/// Stable identities for every external link the app can open (Plan 2 §4.7).
enum ExternalLinkId {
  projectHome,
  issueTracker,
  releaseNotes,
  privacyPolicy,
  guiPlatform,
  cliDocs,
}

/// A link's launchable state. `uri == null` means the URL is not configured
/// in this build — the entry must render disabled with [unavailableReason],
/// never as a fake clickable link.
class ExternalLinkDescriptor {
  const ExternalLinkDescriptor({
    required this.id,
    required this.label,
    this.uri,
  });

  final ExternalLinkId id;
  final String label;
  final Uri? uri;

  bool get enabled => uri != null;

  String get unavailableReason => AppStrings.externalLinkNotConfigured;
}

/// Single source of truth for production URLs (Plan 2 §4.7 / §0.1).
///
/// The project's official home / issue tracker / release page / privacy
/// policy / GUI platform addresses have **not been confirmed yet**. Until a
/// confirmed URL is entered here, every entry stays `null` and the UI must
/// show an explicit "未配置" state instead of opening a guessed legacy
/// GitHub path. Fill in one place; about page, GUI-migration tombstone and
/// diagnostics all read from here.
const Map<ExternalLinkId, String?> kExternalLinkUrls =
    <ExternalLinkId, String?>{
  ExternalLinkId.projectHome: null, // e.g. 'https://example.org/turna'
  ExternalLinkId.issueTracker: null, // e.g. 'https://example.org/turna/issues'
  ExternalLinkId.releaseNotes:
      null, // e.g. 'https://example.org/turna/releases'
  ExternalLinkId.privacyPolicy:
      null, // e.g. 'https://example.org/turna/privacy'
  ExternalLinkId.guiPlatform: null, // e.g. 'https://gui.example.org'
  ExternalLinkId.cliDocs: null, // e.g. 'https://example.org/turna/docs/cli'
};

/// Registry + launch state machine (Plan 2 §7.3):
///
/// ```text
/// 未配置 -> 禁用 + 原因
/// 已配置 -> 校验 scheme -> 不合法：禁用 + 诊断记录
///                    -> 合法：launch -> 成功
///                              -> false/异常：提示失败 + 复制链接
/// ```
class ExternalLinkRegistry {
  const ExternalLinkRegistry({this.urls = kExternalLinkUrls});

  /// Injectable for tests; production reads [kExternalLinkUrls].
  final Map<ExternalLinkId, String?> urls;

  ExternalLinkDescriptor describe(ExternalLinkId id) {
    final raw = urls[id];
    if (raw == null || raw.trim().isEmpty) {
      return ExternalLinkDescriptor(id: id, label: _labelFor(id));
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !isAllowedScheme(uri)) {
      return ExternalLinkDescriptor(id: id, label: _labelFor(id));
    }
    return ExternalLinkDescriptor(id: id, label: _labelFor(id), uri: uri);
  }

  /// Only https (plus http for local loopback in debug builds) is allowed —
  /// no intent/JavaScript/file schemes.
  @visibleForTesting
  static bool isAllowedScheme(Uri uri) {
    if (uri.scheme == 'https') return true;
    if (uri.scheme == 'http') {
      final loopback = uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host == '[::1]';
      return loopback && kDebugMode;
    }
    return false;
  }

  String _labelFor(ExternalLinkId id) {
    switch (id) {
      case ExternalLinkId.projectHome:
        return '项目主页';
      case ExternalLinkId.issueTracker:
        return '问题反馈';
      case ExternalLinkId.releaseNotes:
        return '发布页';
      case ExternalLinkId.privacyPolicy:
        return '隐私政策';
      case ExternalLinkId.guiPlatform:
        return 'GUI 平台';
      case ExternalLinkId.cliDocs:
        return 'CLI 文档';
    }
  }
}

enum ExternalLinkLaunchOutcome {
  launched,
  notConfigured,
  invalidScheme,
  failed
}

/// Open a link and surface the outcome to the user: success is silent, every
/// failure shows a reason plus a "copy address" action so the user can retry
/// externally (never a silent dead tap).
Future<ExternalLinkLaunchOutcome> openExternalLink(
  BuildContext context,
  ExternalLinkId id, {
  ExternalLinkRegistry registry = const ExternalLinkRegistry(),
}) async {
  final descriptor = registry.describe(id);
  final uri = descriptor.uri;
  if (uri == null) {
    _notify(context, descriptor.unavailableReason);
    return ExternalLinkLaunchOutcome.notConfigured;
  }
  if (!ExternalLinkRegistry.isAllowedScheme(uri)) {
    _notify(context, AppStrings.externalLinkInvalidScheme);
    return ExternalLinkLaunchOutcome.invalidScheme;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await _notifyWithCopy(context, uri.toString());
      return ExternalLinkLaunchOutcome.failed;
    }
    return ExternalLinkLaunchOutcome.launched;
  } catch (_) {
    await _notifyWithCopy(context, uri.toString());
    return ExternalLinkLaunchOutcome.failed;
  }
}

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

Future<void> _notifyWithCopy(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(AppStrings.externalLinkOpenFailed),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: AppStrings.externalLinkCopyAddress,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: url));
        },
      ),
    ),
  );
}
