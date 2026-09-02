import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Interrupted staging-first import (doc 42 P3). Continue is not offered:
/// resume never received the unfinished source id, so the button was a no-op.
class OfficialPendingImportBanner extends StatefulWidget {
  const OfficialPendingImportBanner({super.key, this.onChanged});

  final VoidCallback? onChanged;

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
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    _pending = catalog == null
        ? const <OfficialAnkiPendingImport>[]
        : const OfficialAnkiPendingImportStore().list(catalog);
  }

  Future<void> _discard(OfficialAnkiPendingImport item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.ankiRepairDiscardConfirmTitle),
        content: Text(AppStrings.ankiRepairDiscardConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TurnaTheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.ankiPendingDiscard),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    if (paths == null || catalog == null) return;
    await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(catalog),
      attempts: OfficialAnkiImportAttemptDao(catalog),
      paths: paths,
    ).cancelSource(item.sourceId);
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
            onDiscard: () => _discard(item),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Callout for an interrupted import: discard-only, no continue.
class OfficialInterruptedImportCard extends StatelessWidget {
  const OfficialInterruptedImportCard({
    super.key,
    required this.displayName,
    required this.onDiscard,
  });

  final String displayName;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    const danger = TurnaTheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: danger.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    color: TurnaTheme.errorDark,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.ankiPendingImportTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: TurnaTheme.errorDark,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: TurnaTheme.errorDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.ankiPendingMustDiscardBeforeNew,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.errorDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppStrings.ankiPendingImportBody(displayName),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onDiscard,
              style: FilledButton.styleFrom(
                backgroundColor: TurnaTheme.errorDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: Text(AppStrings.ankiPendingDiscard),
            ),
          ],
        ),
      ),
    );
  }
}
