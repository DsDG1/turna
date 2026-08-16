// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_license_notices.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_engine.dart';
import 'package:turna/application/anki_official/spike/official_anki_spike_models.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Debug-only diagnostics for the official Anki native spike.
/// Not registered in AutoRoute; opened only from a [kDebugMode] settings tile.
class OfficialAnkiSpikePage extends StatefulWidget {
  const OfficialAnkiSpikePage({
    super.key,
    this.engine,
    this.resolveOpenRequest,
  });

  final OfficialAnkiSpikeEngine? engine;

  /// Tests inject a resolver so widget tests never call [path_provider].
  final Future<OfficialAnkiOpenRequest> Function()? resolveOpenRequest;

  @override
  State<OfficialAnkiSpikePage> createState() => _OfficialAnkiSpikePageState();
}

class _OfficialAnkiSpikePageState extends State<OfficialAnkiSpikePage> {
  late final OfficialAnkiSpikeEngine _engine;
  OfficialAnkiSpikeSnapshot? _snapshot;
  OfficialAnkiSpikeSnapshot? _collectionSnapshot;
  String? _collectionRoot;
  bool _probingCollection = false;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? FfiOfficialAnkiSpikeEngine();
    registerOfficialAnkiLicenses();
    _snapshot = _engine.probe();
    _logSnapshot('auto-probe', _snapshot);
  }

  void _logSnapshot(String phase, OfficialAnkiSpikeSnapshot? snap) {
    if (snap == null) {
      debugPrint('[OfficialAnkiSpike] $phase: no snapshot');
      return;
    }
    debugPrint(
      '[OfficialAnkiSpike] $phase library=${snap.libraryLoaded} '
      'abi=${snap.abiVersion} backend=${snap.backendCommit} '
      'op=${snap.lastOperation} state=${snap.collectionState.name} '
      'error=${snap.lastError?.code.name ?? "none"} '
      '${snap.lastError?.message ?? ""}',
    );
  }

  void _probe() {
    setState(() {
      _snapshot = _engine.probe();
    });
    _logSnapshot('refresh', _snapshot);
  }

  Future<void> _probeCollection() async {
    if (_probingCollection) {
      return;
    }
    setState(() => _probingCollection = true);
    try {
      final request = widget.resolveOpenRequest != null
          ? await widget.resolveOpenRequest!()
          : OfficialAnkiOpenRequest.isolated(
              supportDirectory: (await getApplicationSupportDirectory()).path,
              runId: DateTime.now().millisecondsSinceEpoch.toString(),
            );
      final snapshot = await _engine.probeCollection(request);
      if (!mounted) {
        return;
      }
      setState(() {
        _collectionSnapshot = snapshot;
        _collectionRoot = request.displayRoot;
        _probingCollection = false;
      });
      _logSnapshot('probe-collection', snapshot);
    } on OfficialAnkiSpikeError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _collectionSnapshot = OfficialAnkiSpikeSnapshot(
          libraryLoaded: false,
          backendCommit: kOfficialAnkiBackendCommit,
          contractVersion: kOfficialAnkiSpikeContractVersion,
          collectionState: OfficialAnkiSpikeCollectionState.uninitialized,
          lastOperation: 'resolve_paths',
          lastError: error,
        );
        _probingCollection = false;
      });
      _logSnapshot('probe-collection-error', _collectionSnapshot);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _collectionSnapshot = OfficialAnkiSpikeSnapshot(
          libraryLoaded: false,
          backendCommit: kOfficialAnkiBackendCommit,
          contractVersion: kOfficialAnkiSpikeContractVersion,
          collectionState: OfficialAnkiSpikeCollectionState.unknown,
          lastOperation: 'resolve_paths',
          lastError: OfficialAnkiSpikeError(
            code: OfficialAnkiSpikeErrorCode.unknown,
            message: error.toString(),
          ),
        );
        _probingCollection = false;
      });
      _logSnapshot('probe-collection-error', _collectionSnapshot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final collection = _collectionSnapshot;
    return SettingsScaffold(
      title: 'Official Anki Spike',
      actions: [
        IconButton(
          tooltip: '重新探测',
          onPressed: _probe,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const _DevOnlyBanner(),
          const SizedBox(height: 16),
          if (snap == null)
            const Text('尚未探测')
          else ...[
            _row('library loaded', snap.libraryLoaded ? 'yes' : 'no'),
            _row('ABI version', snap.abiVersion?.toString() ?? '—'),
            _row('backend commit', snap.backendCommit),
            _row('contract version', '${snap.contractVersion}'),
            _row('collection state', snap.collectionState.name),
            _row('last operation', snap.lastOperation),
            _row(
              'last error',
              snap.lastError == null
                  ? 'none'
                  : '${snap.lastError!.code.name}: ${snap.lastError!.message}',
            ),
            if (snap.handle != null) _row('last handle', '${snap.handle}'),
          ],
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('official-anki-spike-probe-collection'),
            onPressed: _probingCollection ? null : _probeCollection,
            child: Text(_probingCollection ? '正在探测 Collection…' : '探测 Collection'),
          ),
          if (_collectionRoot != null) ...[
            const SizedBox(height: 16),
            _row('spike root', _collectionRoot!),
          ],
          if (collection != null) ...[
            const SizedBox(height: 8),
            _row('collection probe state', collection.collectionState.name),
            _row('collection last operation', collection.lastOperation),
            _row(
              'collection last error',
              collection.lastError == null
                  ? 'none'
                  : '${collection.lastError!.code.name}: ${collection.lastError!.message}',
            ),
          ],
          const SizedBox(height: 16),
          const _LicenseNotice(),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DevOnlyBanner extends StatelessWidget {
  const _DevOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      ),
      child: const Text(
        '开发诊断页。不进入普通用户导航，也不改生产 Anki 导入路径。',
      ),
    );
  }
}

class _LicenseNotice extends StatelessWidget {
  const _LicenseNotice();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'license',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
              ),
        ),
        const SizedBox(height: 4),
        const SelectableText(
          'Anki rslib: AGPL-3.0-or-later. Turna GPLv3 does not finish that duty. '
          '$kOfficialAnkiSourceOfferSummary',
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            registerOfficialAnkiLicenses();
            showLicensePage(
              context: context,
              applicationName: 'Turna',
            );
          },
          child: const Text('查看开源许可证'),
        ),
      ],
    );
  }
}
