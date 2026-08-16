import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/engine/official_anki_in_process.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/utils/ohos_file_picker.dart';

/// Internal-only official import surface. Review is not opened here.
class OfficialAnkiInternalPage extends StatefulWidget {
  const OfficialAnkiInternalPage({super.key});

  @override
  State<OfficialAnkiInternalPage> createState() =>
      _OfficialAnkiInternalPageState();
}

class _OfficialAnkiInternalPageState extends State<OfficialAnkiInternalPage> {
  String _status = 'idle';
  String _detail = '';
  var _busy = false;

  OfficialAnkiRuntimeProbe get _probe => OfficialAnkiCompositionRoot.probe();

  @override
  void initState() {
    super.initState();
    final probe = _probe;
    debugPrint(
      '[OfficialAnkiImport] flags.import='
      '${OfficialAnkiFeatureFlags.current.import} '
      'allows=${OfficialAnkiFeatureFlags.current.allowsOfficialImport} '
      'probe=${probe.reason} abi=${probe.abiVersion} '
      'backend=${probe.backendCommit ?? "-"}',
    );
  }

  Future<void> _importPicked() async {
    setState(() {
      _busy = true;
      _status = 'picking';
    });
    try {
      final flags = OfficialAnkiFeatureFlags.current;
      if (!flags.allowsOfficialImport) {
        setState(() {
          _status = 'flags_off';
          _detail =
              '需要 5 个 TURNA_OFFICIAL_ANKI_* dart-define=true 后重新 flutter run';
        });
        debugPrint('[OfficialAnkiImport] flags_off');
        return;
      }
      final picked = await OhosFilePicker.pickFiles(
        allowedExtensions: const ['apkg'],
        dialogTitle: '选择官方导入用 .apkg',
      );
      final path = picked?.files.single.path;
      if (path == null) {
        setState(() {
          _status = 'cancelled';
          _detail = '未选择文件';
        });
        return;
      }
      setState(() => _status = 'importing');
      debugPrint('[OfficialAnkiImport] start path=$path');
      final support = await getApplicationSupportDirectory();
      final importer = await OfficialAnkiCompositionRoot.requireImporter(
        supportDir: support,
      );
      final result = await importer.importFile(
        packagePath: path,
        displayName: path.split(RegExp(r'[/\\]')).last,
      );
      debugPrint(
        '[OfficialAnkiImport] done state=${result.state.wire} '
        'source=${result.sourceId} cards=${result.cardCount} '
        'notes=${result.noteCount} already=${result.alreadyImported}',
      );
      setState(() {
        _status = result.state.wire;
        _detail =
            'source=${result.sourceId} cards=${result.cardCount}\n已导入官方 Collection，复习入口尚未开放';
      });
    } catch (error) {
      debugPrint('[OfficialAnkiImport] error $error');
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final session = OfficialAnkiCompositionRoot.session;
    if (session is OfficialAnkiSession) {
      await session.cancel();
    } else if (session is OfficialAnkiInProcessHost) {
      await session.engine.cancel();
    } else {
      return;
    }
    debugPrint('[OfficialAnkiImport] cancel_requested');
    setState(() => _status = 'cancel_requested');
  }

  @override
  Widget build(BuildContext context) {
    final probe = _probe;
    return Scaffold(
      appBar: AppBar(title: const Text('Official Anki 内部导入')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('flags.import=${OfficialAnkiFeatureFlags.current.import}'),
          Text(
            'allows=${OfficialAnkiFeatureFlags.current.allowsOfficialImport}',
          ),
          Text('probe=${probe.reason} abi=${probe.abiVersion}'),
          Text('backend=${probe.backendCommit ?? "-"}'),
          const SizedBox(height: 12),
          Text('status=$_status'),
          Text(_detail),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _importPicked,
            child: const Text('选择并导入 apkg'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? _cancel : null,
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
