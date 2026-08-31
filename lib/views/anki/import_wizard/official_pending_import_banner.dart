import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';

/// Thin continue/discard row for unfinished staging-first imports (doc 42 P3).
class OfficialPendingImportBanner extends StatelessWidget {
  const OfficialPendingImportBanner({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog == null) return const SizedBox.shrink();
    final pending = const OfficialAnkiPendingImportStore().list(catalog);
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final item in pending)
          ListTile(
            key: Key('pending-import-${item.sourceId}'),
            contentPadding: EdgeInsets.zero,
            title: Text(AppStrings.ankiPendingImportTitle),
            subtitle: Text(AppStrings.ankiPendingImportBody(item.displayName)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () =>
                      context.router.push(const AnkiImportRoute()),
                  child: Text(AppStrings.ankiPendingContinue),
                ),
                TextButton(
                  onPressed: () async {
                    final paths = OfficialAnkiCompositionRoot.locatorPaths;
                    if (paths == null) return;
                    await OfficialAnkiImportSaga(
                      sources: OfficialAnkiSourceDao(catalog),
                      attempts: OfficialAnkiImportAttemptDao(catalog),
                      paths: paths,
                    ).cancelSource(item.sourceId);
                    onChanged?.call();
                  },
                  child: Text(AppStrings.ankiPendingDiscard),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
