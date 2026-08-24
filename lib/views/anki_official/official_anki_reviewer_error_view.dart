import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/l10n/app_strings.dart';

class OfficialAnkiReviewerErrorView extends StatelessWidget {
  const OfficialAnkiReviewerErrorView({
    super.key,
    required this.messageKey,
    this.debugDetails,
    this.code,
    this.onRetry,
    this.onBack,
  });

  factory OfficialAnkiReviewerErrorView.fromException(
    OfficialAnkiException error, {
    String? code,
    VoidCallback? onRetry,
    VoidCallback? onBack,
  }) {
    return OfficialAnkiReviewerErrorView(
      messageKey: error.messageKey,
      debugDetails: (kDebugMode || kShowOfficialDebug)
          ? '${error.messageKey}\n${error.debugDetails ?? error}'
          : null,
      code: code ?? error.debugDetails,
      onRetry: onRetry,
      onBack: onBack,
    );
  }

  static const kShowOfficialDebug = bool.fromEnvironment(
    'TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS',
  );

  final String messageKey;
  final String? debugDetails;
  final String? code;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(localize(messageKey), textAlign: TextAlign.center),
            if (code != null) ...[
              const SizedBox(height: 8),
              Text(code!, textAlign: TextAlign.center),
            ],
            if (debugDetails != null) ...[
              const SizedBox(height: 8),
              Text(
                debugDetails!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null || onBack != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onRetry != null)
                    FilledButton(
                      onPressed: onRetry,
                      child: Text(AppStrings.officialAnkiRetryCurrentSide),
                    ),
                  if (onRetry != null && onBack != null) const SizedBox(width: 12),
                  if (onBack != null)
                    OutlinedButton(
                      onPressed: onBack,
                      child: Text(AppStrings.commonBack),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Single localization entry for `official_anki.*` message keys, shared
  /// with the reviewer stage. Translations live in [AppStrings]; unknown
  /// keys surface the raw key only in debug builds so users never see
  /// diagnostic identifiers.
  static String localize(String key) {
    final text = AppStrings.officialAnkiError(key);
    if (text == AppStrings.officialAnkiErrorFallback &&
        (kDebugMode || kShowOfficialDebug)) {
      return '官方卡片无法显示（$key）。';
    }
    return text;
  }

  static OfficialAnkiReviewerErrorView fromUi({
    required OfficialAnkiReviewerUi ui,
    OfficialAnkiException? error,
    VoidCallback? onRetry,
    VoidCallback? onBack,
  }) {
    return OfficialAnkiReviewerErrorView(
      messageKey: error?.messageKey ?? 'official_anki.render_failed',
      code: ui.code,
      debugDetails: kDebugMode ? error?.debugDetails : null,
      onRetry: ui.offersRetryCurrentSide ? onRetry : null,
      onBack: ui.offersBack ? onBack : null,
    );
  }
}
