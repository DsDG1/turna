import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';

/// Thin continue/discard row for unfinished staging-first imports (doc 42 P3).
///
/// crash-hunt PR1: the pending list is a handful of synchronous sqlite reads
/// and used to run inside build() on every parent rebuild. It is loaded once
/// per state (and after this banner's own actions) until PR2 makes the
/// catalog async.
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

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    return Column(
      children: [
        for (final item in _pending)
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
                    if (paths == null || catalog == null) return;
                    await OfficialAnkiImportSaga(
                      sources: OfficialAnkiSourceDao(catalog),
                      attempts: OfficialAnkiImportAttemptDao(catalog),
                      paths: paths,
                    ).cancelSource(item.sourceId);
                    if (mounted) setState(_reload);
                    widget.onChanged?.call();
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
