import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 来源级的「显示方式」入口（ADR 0057 §6 / plan §12.4）。
///
/// 方案生效之后，用户必须能独立恢复原卡，且恢复只切决策、不动排期。这个
/// sheet 只读 manifest 并逐组 `deactivate`，不碰卡片内容、不碰调度。
Future<void> showAdaptationRestoreSheet(
  BuildContext context, {
  required String sourceId,
}) async {
  final engine = OfficialAnkiCompositionRoot.engine;
  if (engine == null) {
    TurnaSnackBar.show(context, AppStrings.ankiAdaptationRestoreUnavailable);
    return;
  }
  final store = OfficialAnkiAdaptationStore(engine);
  var changed = false;
  await showTurnaSheet<void>(
    context: context,
    title: AppStrings.ankiAdaptationRestoreTitle,
    subtitle: AppStrings.ankiAdaptationRestoreHint,
    body: AdaptationRestoreSheet(
      showHeader: false,
      loadManifest: () => store.readManifest(sourceId),
      restoreScope: (scopeKey) async {
        final ok = await store.deactivate(
          sourceId: sourceId,
          scopeKey: scopeKey,
        );
        changed = changed || ok;
        return ok;
      },
      restoreAll: () async {
        final ok = await store.replaceManifest(
          sourceId,
          AdaptationManifest.empty,
        );
        changed = changed || ok;
        return ok;
      },
    ),
  );
  if (changed && context.mounted) {
    TurnaSnackBar.show(context, AppStrings.ankiAdaptationRestored);
  }
}

/// Injectable sheet: it never touches the engine itself, so the list/restore
/// behaviour is testable without one.
class AdaptationRestoreSheet extends StatefulWidget {
  const AdaptationRestoreSheet({
    super.key,
    required this.loadManifest,
    required this.restoreScope,
    required this.restoreAll,
    this.showHeader = true,
  });

  final Future<AdaptationManifest> Function() loadManifest;
  final Future<bool> Function(String scopeKey) restoreScope;
  final Future<bool> Function() restoreAll;
  final bool showHeader;

  @override
  State<AdaptationRestoreSheet> createState() => _AdaptationRestoreSheetState();
}

class _AdaptationRestoreSheetState extends State<AdaptationRestoreSheet> {
  AdaptationManifest? _manifest;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manifest = await widget.loadManifest();
    if (!mounted) return;
    setState(() => _manifest = manifest);
  }

  Future<void> _restoreScope(String scopeKey) async {
    if (_busy.contains(scopeKey)) return;
    setState(() => _busy.add(scopeKey));
    final ok = await widget.restoreScope(scopeKey);
    if (!mounted) return;
    setState(() {
      _busy.remove(scopeKey);
      if (ok) {
        final entries = Map<String, AdaptationManifestEntry>.from(
          _manifest?.entries ?? const <String, AdaptationManifestEntry>{},
        )..remove(scopeKey);
        _manifest = AdaptationManifest(
          schemaVersion: _manifest?.schemaVersion ?? 1,
          entries: entries,
        );
      }
    });
  }

  Future<void> _restoreAll() async {
    final ok = await widget.restoreAll();
    if (!mounted) return;
    if (ok) {
      setState(() => _manifest = AdaptationManifest.empty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _manifest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.xs,
        AppSpacing.pageMargin,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeader) ...[
            Text(
              AppStrings.ankiAdaptationRestoreTitle,
              style: AppTextStyles.sectionTitle(context),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppStrings.ankiAdaptationRestoreHint,
              style: AppTextStyles.captionSm(context),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (manifest == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: TurnaLoader.inline()),
            )
          else if (manifest.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                AppStrings.ankiAdaptationRestoreEmpty,
                key: const ValueKey('adaptation-restore-empty'),
                style: AppTextStyles.captionSm(context),
              ),
            )
          else ...[
            for (final entry in manifest.entries.keys)
              Row(
                key: ValueKey('adaptation-scope-$entry'),
                children: [
                  Expanded(
                    child: Text(
                      adaptationScopeLabel(
                        entry,
                        (id, template) =>
                            AppStrings.ankiAdaptationScopeLabel(id, template),
                      ),
                      style: AppTextStyles.captionSm(
                        context,
                      ).copyWith(color: TurnaTheme.textPrimaryColor(context)),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy.contains(entry)
                        ? null
                        : () => _restoreScope(entry),
                    child: Text(AppStrings.ankiAdaptationRestoreOne),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('adaptation-restore-all'),
                onPressed: _restoreAll,
                child: Text(AppStrings.ankiAdaptationRestoreAll),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `notetype:template[:cloze]` → 人类可读标签。解析失败时原样返回，避免
/// 损坏的 manifest 让整个面板显示空白。
String adaptationScopeLabel(
  String scopeKey,
  String Function(int notetypeId, int templateOrdinal) format,
) {
  final scope = parseAdaptationScopeKey(scopeKey);
  if (scope == null) return scopeKey;
  return format(scope.notetypeId, scope.templateOrdinal);
}
