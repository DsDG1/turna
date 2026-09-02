import 'package:flutter/material.dart';
import 'package:turna/application/maintenance/official_anki_ghost_purge_service.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// One user-facing row on the storage category drill-down (official source
/// or a legacy media directory). [id] is the uninstall identity — never a
/// truncated prefix.
class StorageDeletableItem {
  const StorageDeletableItem({
    required this.id,
    required this.displayName,
    required this.subtitle,
    this.physicalBytes,
    this.alreadyRetiring = false,
    this.orphaned = false,
  });

  final String id;
  final String displayName;
  final String subtitle;
  final int? physicalBytes;
  final bool alreadyRetiring;
  final bool orphaned;
}

/// Local (non-AutoRoute) list: checkbox multi-select then delete via the
/// injected [uninstall] callback. Production wires [AnkiDeckManager].
class StorageCategoryItemsPage extends StatefulWidget {
  const StorageCategoryItemsPage({
    super.key,
    required this.title,
    required this.totalBytesLabel,
    required this.emptyMessage,
    required this.loadItems,
    required this.uninstall,
    this.selectionWarning,
    this.allowForcePurge = false,
    this.onForcePurge,
  });

  final String title;
  final String totalBytesLabel;
  final String emptyMessage;
  final String? selectionWarning;
  final Future<List<StorageDeletableItem>> Function() loadItems;
  final Future<bool> Function(String id) uninstall;

  /// Empty-ledger leftover bytes (collection / checkpoints / staging).
  final bool allowForcePurge;
  final Future<OfficialAnkiGhostPurgeResult> Function()? onForcePurge;

  @override
  State<StorageCategoryItemsPage> createState() =>
      _StorageCategoryItemsPageState();
}

class _StorageCategoryItemsPageState extends State<StorageCategoryItemsPage> {
  List<StorageDeletableItem>? _items;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  final Set<String> _selected = {};
  var _didChange = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.loadItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _selected.removeWhere(
          (id) => items.every((item) => item.id != id),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _forcePurge() async {
    final purge = widget.onForcePurge;
    if (purge == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.storageForcePurgeOfficialConfirmTitle),
        content: Text(AppStrings.storageForcePurgeOfficialConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TurnaTheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.storageForcePurgeOfficial),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    OfficialAnkiGhostPurgeResult result;
    try {
      result = await purge();
    } catch (_) {
      result = const OfficialAnkiGhostPurgeResult(
        ok: false,
        errorCode: 'purge_failed',
      );
    }
    if (!mounted) return;
    if (result.ok) _didChange = true;
    setState(() => _busy = false);
    final message = result.ok
        ? AppStrings.storageForcePurgeOfficialDone
        : (result.errorCode == 'sources_present' ||
                result.errorCode == 'import_in_progress')
            ? AppStrings.storageForcePurgeOfficialBlocked
            : AppStrings.storageForcePurgeOfficialFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    await _reload();
  }

  String _shortId(String id) => id.length <= 12 ? id : id.substring(0, 12);

  Future<void> _deleteSelected() async {
    final items = _items;
    if (items == null || _busy) return;
    final chosen = items.where((item) => _selected.contains(item.id)).toList();
    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.storageDeleteNothingSelected)),
      );
      return;
    }
    final retiring = chosen.where((item) => item.alreadyRetiring).toList();
    final actionable =
        chosen.where((item) => !item.alreadyRetiring).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final names = chosen
            .map((item) => '${item.displayName}\n${_shortId(item.id)}')
            .join('\n\n');
        final extra = widget.selectionWarning == null
            ? ''
            : '\n\n${widget.selectionWarning}';
        return AlertDialog(
          title: Text(AppStrings.ankiUninstallConfirmTitle),
          content: Text(
            '$names\n\n${AppStrings.ankiUninstallConfirmBody}$extra',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppStrings.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: TurnaTheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppStrings.ankiUninstallDeck),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    if (actionable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.storageRetiringSkipHint)),
      );
      return;
    }
    setState(() => _busy = true);
    var completed = 0;
    var pending = 0;
    var failed = 0;
    for (final item in actionable) {
      try {
        if (await widget.uninstall(item.id)) {
          completed++;
        } else {
          pending++;
        }
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _didChange = true;
    _selected.clear();
    setState(() => _busy = false);
    final message = failed > 0
        ? AppStrings.ankiDeckRemovalFailed
        : pending > 0 && completed == 0
            ? AppStrings.ankiDeckRemovalPending
            : AppStrings.ankiDeckRemoved;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          retiring.isEmpty ? message : '$message · ${AppStrings.storageRetiringSkipHint}',
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_didChange);
      },
      child: SettingsScaffold(
        title: widget.title,
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_error',
                style: const TextStyle(color: TurnaTheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reload,
                child: Text(AppStrings.commonRetry),
              ),
            ],
          ),
        ),
      );
    }
    final items = _items ?? const <StorageDeletableItem>[];
    final showForcePurge = widget.allowForcePurge &&
        widget.onForcePurge != null &&
        items.isEmpty;
    return Column(
      children: [
        if (_busy || _loading) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.totalBytesLabel,
              style: TextStyle(
                fontSize: 13,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
        ),
        if (widget.selectionWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              widget.selectionWarning!,
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      showForcePurge
                          ? AppStrings.storageForcePurgeOfficialHint
                          : widget.emptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = _selected.contains(item.id);
                    return CheckboxListTile(
                      key: Key('storage-item-${item.id}'),
                      value: selected,
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(item.id);
                                } else {
                                  _selected.remove(item.id);
                                }
                              });
                            },
                      title: Text(item.displayName),
                      subtitle: Text(
                        item.physicalBytes == null
                            ? item.subtitle
                            : '${item.subtitle} · ${_formatBytes(item.physicalBytes!)}',
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('storage-delete-selected'),
                    onPressed:
                        (_busy || items.isEmpty) ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: TurnaTheme.error,
                    ),
                    label: Text(AppStrings.storageDeleteSelected),
                  ),
                ),
                if (showForcePurge) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('storage-force-purge'),
                    onPressed: _busy ? null : _forcePurge,
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TurnaTheme.error,
                      side: BorderSide(
                        color: TurnaTheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    label: Text(AppStrings.storageForcePurgeOfficial),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
