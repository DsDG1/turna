// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
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
  });

  final OfficialAnkiSpikeEngine? engine;

  @override
  State<OfficialAnkiSpikePage> createState() => _OfficialAnkiSpikePageState();
}

class _OfficialAnkiSpikePageState extends State<OfficialAnkiSpikePage> {
  late final OfficialAnkiSpikeEngine _engine;
  OfficialAnkiSpikeSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? FfiOfficialAnkiSpikeEngine();
    _snapshot = _engine.probe();
  }

  void _probe() {
    setState(() {
      _snapshot = _engine.probe();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
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
