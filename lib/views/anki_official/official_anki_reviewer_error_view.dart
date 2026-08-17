import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';

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
                      child: const Text('重试当前面'),
                    ),
                  if (onRetry != null && onBack != null) const SizedBox(width: 12),
                  if (onBack != null)
                    OutlinedButton(
                      onPressed: onBack,
                      child: const Text('返回'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String localize(String key) {
    switch (key) {
      case 'official_anki.card_not_found':
        return '这张官方卡片不存在。';
      case 'official_anki.render_failed':
        return '官方模板渲染失败。';
      case 'official_anki.renderer_flag_fail_closed':
        return '官方原卡渲染未启用。';
      case 'official_anki.worker_required':
        return '官方渲染需要独立 worker，当前不可用。';
      case 'official_anki.in_process_forbidden':
        return '生产路径禁止使用进程内回退。';
      case 'official_anki.flag_fail_closed':
        return '官方 Anki 功能未打开。';
      case 'official_anki.capability_missing':
        return '当前 native 没有 RENDER_CARD，需要重编 libturna_anki.so。';
      case 'official_anki.collection_already_open':
        return '官方 Collection 已打开，请重试预览。';
      case 'official_anki.typed_field_unknown':
      case 'official_anki.typed_field_not_found':
        return '这张卡片没有可输入的字段。';
      case 'official_anki.typed_cloze_empty':
        return '这个填空没有可输入的内容。';
      case 'official_anki.typed_compare_failed':
        return '答案比对失败，可以重试或跳过。';
      default:
        return '官方卡片无法显示（$key）。';
    }
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
