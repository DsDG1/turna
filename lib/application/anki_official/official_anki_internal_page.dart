import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/engine/official_anki_in_process.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/anki_official/official_anki_source_management_page.dart';
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

  Future<void> _openFirstCard() async {
    setState(() {
      _busy = true;
      _status = 'opening_reviewer';
    });
    try {
      if (!OfficialAnkiFeatureFlags.current.allowsOfficialRenderer) {
        setState(() {
          _status = 'renderer_off';
          _detail =
              '需要 TURNA_OFFICIAL_ANKI_RENDERER=true，并保留 ENGINE/CATALOG/RUNTIME/PLATFORM';
        });
        debugPrint('[OfficialAnkiPreview] renderer_off');
        return;
      }
      var session = OfficialAnkiCompositionRoot.session;
      if (session is! OfficialAnkiSession) {
        final support = await getApplicationSupportDirectory();
        await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
        session = OfficialAnkiCompositionRoot.session;
      }
      if (session is! OfficialAnkiSession) {
        setState(() {
          _status = 'no_worker';
          _detail =
              '官方 worker 未就绪（mode=${OfficialAnkiCompositionRoot.executionMode.name}）';
        });
        debugPrint('[OfficialAnkiPreview] no_worker');
        return;
      }
      final info = await session.engineInfo();
      if (!info.has('RENDER_CARD')) {
        setState(() {
          _status = 'capability_missing';
          _detail =
              '当前 libturna_anki.so 没有 RENDER_CARD（contract ${info.contractMajor}.${info.contractMinor}）。'
              '请重编 Android arm64 .so 后完整重启，不要只 hot reload。';
        });
        debugPrint('[OfficialAnkiPreview] capability_missing $info');
        return;
      }
      debugPrint('[OfficialAnkiPreview] ensureOpen source-catalog');
      await session.ensureCollectionOpen();
      final sources = await session.listSources();
      if (sources.isEmpty) {
        setState(() {
          _status = 'no_source';
          _detail = '没有已导入的官方来源';
        });
        return;
      }
      final cards = await session.listCards(sources.first.sourceId);
      if (cards.isEmpty) {
        setState(() {
          _status = 'no_cards';
          _detail = '来源没有卡片';
        });
        return;
      }
      if (!mounted) return;
      final support = await getApplicationSupportDirectory();
      if (!mounted) return;
      final paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot: Directory('${support.path}/official_anki/default'),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfficialAnkiReviewerPage(
            sourceId: sources.first.sourceId,
            cardId: cards.first.cardId,
            paths: paths,
          ),
        ),
      );
      setState(() => _status = 'previewed');
    } catch (error, stack) {
      debugPrint('[OfficialAnkiPreview] error $error\n$stack');
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSourceManagement() async {
    setState(() {
      _busy = true;
      _status = 'opening_sources';
    });
    try {
      if (!OfficialAnkiFeatureFlags.current.allowsProjection) {
        setState(() {
          _status = 'projection_off';
          _detail =
              '需要 TURNA_OFFICIAL_ANKI_PROJECTION=true，并保留 ENGINE/IMPORT/CATALOG/RUNTIME';
        });
        return;
      }
      final support = await getApplicationSupportDirectory();
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator(
        supportDir: support,
      );
      if (OfficialAnkiCompositionRoot.session == null) {
        await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
      }
      CourseProvider? courseProvider;
      try {
        courseProvider = getIt<CourseProvider>();
      } catch (_) {
        courseProvider = null;
      }
      final page = await officialAnkiBuildSourceManagementPage(
        courseProvider: courseProvider,
        course: CourseLoader.databaseOrNull(),
      );
      if (page == null) {
        setState(() {
          _status = 'source_management_unavailable';
          _detail = 'catalog/course/engine 未就绪，无法打开课程映射';
        });
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
      setState(() => _status = 'source_management');
    } catch (error, stack) {
      debugPrint('[OfficialAnkiSources] error $error\n$stack');
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
          Text('mode=${OfficialAnkiCompositionRoot.executionMode.name}'),
          Text(
            'renderer=${OfficialAnkiFeatureFlags.current.allowsOfficialRenderer}',
          ),
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
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _openFirstCard,
            child: const Text('预览已导入官方卡片'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('official-source-management-open'),
            onPressed: _busy ? null : _openSourceManagement,
            child: const Text('课程映射 / 生成'),
          ),
        ],
      ),
    );
  }
}
