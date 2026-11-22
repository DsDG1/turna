import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_catalog_service.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// Interrupted staging-first import (doc 42 P3). Continue is not offered:
/// resume never received the unfinished source id, so the button was a no-op.
class OfficialPendingImportBanner extends StatefulWidget {
  const OfficialPendingImportBanner({
    super.key,
    this.onChanged,
    this.onContinue,
  });

  final VoidCallback? onChanged;
  final void Function(OfficialAnkiPendingImport item)? onContinue;

  @override
  State<OfficialPendingImportBanner> createState() =>
      _OfficialPendingImportBannerState();
}

class _OfficialPendingImportBannerState
    extends State<OfficialPendingImportBanner> {
  List<OfficialAnkiPendingImport> _pending = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _pending = const OfficialAnkiCatalogService().pendingImports();
  }

  Future<void> _discard(OfficialAnkiPendingImport item) async {
    final confirmed = await showTurnaConfirmDialog(
      context: context,
      title: AppStrings.ankiRepairDiscardConfirmTitle,
      message: AppStrings.ankiRepairDiscardConfirmBody,
      confirmLabel: AppStrings.ankiPendingDiscard,
      destructive: true,
    );
    if (confirmed != true) return;
    final discarded = await const OfficialAnkiCatalogService()
        .discardPendingImport(item.sourceId);
    if (!discarded) return;
    if (mounted) setState(_reload);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final item in _pending) ...[
          OfficialInterruptedImportCard(
            key: Key('pending-import-${item.sourceId}'),
            displayName: item.displayName,
            continueLabel: item.stagingIntact
                ? AppStrings.ankiPendingContinue
                : (item.packagePath == null
                      ? null
                      : AppStrings.ankiPendingReparse),
            onContinue: widget.onContinue == null
                ? null
                : () => widget.onContinue!(item),
            onDiscard: () => _discard(item),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// Callout for an interrupted import. Continue reopens preview when the
/// staging collection is still on disk; otherwise the card only discards.
class OfficialInterruptedImportCard extends StatelessWidget {
  const OfficialInterruptedImportCard({
    super.key,
    required this.displayName,
    required this.onDiscard,
    this.onContinue,
    this.continueLabel,
  });

  final String displayName;
  final VoidCallback? onDiscard;
  final VoidCallback? onContinue;
  final String? continueLabel;

  @override
  Widget build(BuildContext context) {
    const danger = TurnaTheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: danger.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: 0.16),
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: const TurnaIcon(
                    TurnaIconId.error,
                    color: TurnaTheme.errorDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.ankiPendingImportTitle,
                        style: AppTextStyles.cardTitle(context).copyWith(
                          fontWeight: FontWeight.w800,
                          color: TurnaTheme.errorDark,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.captionSm(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: TurnaTheme.errorDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.ankiImportSystemError,
              style: AppTextStyles.captionSm(context).copyWith(
                fontWeight: FontWeight.w800,
                color: TurnaTheme.errorDark,
              ),
            ),
            if (onContinue == null || continueLabel == null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.ankiPendingMustDiscardBeforeNew,
                style: AppTextStyles.captionSm(context).copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.errorDark,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              AppStrings.ankiPendingImportBody(displayName),
              style: AppTextStyles.captionSm(context),
            ),
            const SizedBox(height: 14),
            if (onContinue != null && continueLabel != null) ...[
              FilledButton.icon(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: TurnaTheme.brandTeal,
                  foregroundColor: TurnaTheme.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  shape: TurnaTheme.shape,
                ),
                icon: const TurnaIcon(
                  TurnaIconId.play,
                  size: 18,
                  color: TurnaTheme.textOnPrimary,
                ),
                label: Text(continueLabel!),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            FilledButton.icon(
              onPressed: onDiscard,
              style: FilledButton.styleFrom(
                backgroundColor: TurnaTheme.errorDark,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: TurnaTheme.shape,
              ),
              icon: const TurnaIcon(
                TurnaIconId.delete,
                size: 18,
                color: TurnaTheme.textOnPrimary,
              ),
              label: Text(AppStrings.ankiPendingDiscard),
            ),
          ],
        ),
      ),
    );
  }
}
