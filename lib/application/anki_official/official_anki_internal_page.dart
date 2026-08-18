import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki_official/engine/official_anki_in_process.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_session_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_fixture_pilot_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/views/anki_official/official_anki_review_page.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/anki_official/official_anki_source_management_page.dart';
import 'package:turna/views/anki_official/official_anki_migration_preview_page.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_preview_loader.dart';
import 'package:turna/data/course_database.dart';
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
  final _ops = OfficialAnkiOperationCoordinator();

  OfficialAnkiRuntimeProbe get _probe => OfficialAnkiCompositionRoot.probe();

  Future<File?> _locateP5cFixture() async {
    final support = await getApplicationSupportDirectory();
    for (final path in <String>[
      '${support.path}/p5c-classic-basic.apkg',
      '${support.path}/p5c-basic-cloze.apkg',
      '/sdcard/Download/p5c-classic-basic.apkg',
      '/sdcard/Download/p5c-basic-cloze.apkg',
      '/storage/emulated/0/Download/p5c-classic-basic.apkg',
      '/storage/emulated/0/Download/p5c-basic-cloze.apkg',
    ]) {
      final file = File(path);
      if (file.existsSync()) return file;
    }
    return null;
  }

  bool get _canOpenOfficialSurfaces {
    if (_busy) return false;
    if (!OfficialAnkiFeatureFlags.current.allowsOfficialImport) {
      return true;
    }
    return OfficialAnkiCompositionRoot.session != null &&
        OfficialAnkiCompositionRoot.executionMode !=
            OfficialAnkiExecutionMode.none;
  }

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
    _warmupWorker();
  }

  Future<void> _warmupWorker() async {
    if (!OfficialAnkiFeatureFlags.current.allowsOfficialImport) {
      return;
    }
    setState(() {
      _busy = true;
      _status = 'opening';
    });
    try {
      final support = await getApplicationSupportDirectory();
      if (!mounted) return;
      await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
      if (!mounted) return;
      var status = OfficialAnkiCompositionRoot.session != null
          ? 'ready'
          : 'no_worker';
      var detail = '';
      if (status == 'ready' &&
          OfficialAnkiFeatureFlags.current.migrationPilot &&
          OfficialAnkiFeatureFlags.current.allowsProjection) {
        final projected = await _projectObservingFixture();
        if (projected != null) {
          status = projected.$1;
          detail = projected.$2;
        }
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _detail = detail;
      });
    } catch (error) {
      debugPrint('[OfficialAnkiImport] warmup error $error');
      if (!mounted) return;
      setState(() {
        _status = 'no_worker';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _importDeviceFixture() async {
    setState(() {
      _busy = true;
      _status = 'importing_fixture';
    });
    try {
      if (!OfficialAnkiFeatureFlags.current.allowsOfficialImport) {
        setState(() {
          _status = 'flags_off';
          _detail = '需要导入相关 dart-define=true';
        });
        return;
      }
      const candidates = <String>[
        '/data/local/tmp/turna-08-scheduling.apkg',
        '/sdcard/Download/turna-08-scheduling.apkg',
      ];
      final path = candidates.firstWhere(
        (item) => File(item).existsSync(),
        orElse: () => '',
      );
      if (path.isEmpty) {
        setState(() {
          _status = 'fixture_missing';
          _detail = candidates.join('\n');
        });
        return;
      }
      final support = await getApplicationSupportDirectory();
      final importer = await OfficialAnkiCompositionRoot.requireImporter(
        supportDir: support,
      );
      final result = await importer.importFile(
        packagePath: path,
        displayName: '08-scheduling',
      );
      setState(() {
        _status = result.state.wire;
        _detail =
            'fixture=$path source=${result.sourceId} cards=${result.cardCount}';
      });
    } catch (error) {
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(String, String)?> _projectObservingFixture() async {
    final support = await getApplicationSupportDirectory();
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory('${support.path}/official_anki/default'),
    );
    final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
    try {
      final row = OfficialAnkiMigrationDao(catalog).findObservingFixture(
        profileId: paths.profileId,
      );
      final sourceId = row?.officialSourceId;
      if (sourceId == null || sourceId.isEmpty) return null;
      CourseDatabase? course;
      try {
        course = CourseLoader.databaseOrNull() ??
            (getIt.isRegistered<CourseDatabase>()
                ? getIt<CourseDatabase>()
                : null);
      } catch (_) {
        course = null;
      }
      if (course == null) {
        return ('ready', 'projection skipped: no course db');
      }
      final session = OfficialAnkiCompositionRoot.session;
      if (session is! OfficialAnkiSession) return null;
      await session.ensureCollectionOpen();
      final result = await OfficialAnkiCourseProjectionService(
        engine: OfficialAnkiSessionEngine(session),
        catalog: catalog,
        course: course,
        sourceId: sourceId,
        profileId: paths.profileId,
        flags: OfficialAnkiFeatureFlags.current,
      ).projectSourceForFixturePilot();
      if (result.failed || result.needsMapping || result.itemCount == 0) {
        return (
          'projection_failed',
          result.errorCode ??
              (result.needsMapping ? 'projection_needs_mapping' : 'projection_empty'),
        );
      }
      return (
        'ready',
        'projection items=${result.itemCount} source=$sourceId',
      );
    } catch (error) {
      debugPrint('[OfficialAnkiPilot] observing projection error $error');
      return ('projection_failed', error.toString());
    } finally {
      catalog.close();
    }
  }

  Future<void> _openFormalReview() async {
    setState(() {
      _busy = true;
      _status = 'opening_formal_review';
    });
    try {
      if (!OfficialAnkiFeatureFlags.current.allowsOfficialScheduler) {
        setState(() {
          _status = 'scheduler_off';
          _detail =
              '需要 TURNA_OFFICIAL_ANKI_SCHEDULER=true，并保留 ENGINE/IMPORT/CATALOG/RUNTIME/PLATFORM/RENDERER';
        });
        return;
      }
      final support = await getApplicationSupportDirectory();
      await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
      final session = OfficialAnkiCompositionRoot.session;
      if (session is! OfficialAnkiSession) {
        setState(() {
          _status = 'no_worker';
          _detail = '官方 worker 未就绪';
        });
        return;
      }
      await session.ensureCollectionOpen();
      if (!mounted) return;
      final paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot: Directory('${support.path}/official_anki/default'),
      );
      int? fixtureDeckId;
      Set<int>? fixtureCardIds;
      if (OfficialAnkiFeatureFlags.current.migrationPilot) {
        final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
        try {
          final target = officialAnkiObservingFixtureReviewTarget(
            dao: OfficialAnkiMigrationDao(catalog),
            sources: OfficialAnkiSourceDao(catalog),
            profileId: paths.profileId,
          );
          fixtureDeckId = target?.deckId;
          fixtureCardIds = target?.cardIds;
        } finally {
          catalog.close();
        }
        if (fixtureDeckId == null ||
            fixtureCardIds == null ||
            fixtureCardIds.isEmpty) {
          setState(() {
            _status = 'no_fixture_observing';
            _detail = 'MIGRATION_PILOT 下正式复习只打开 observing fixture 牌组';
          });
          return;
        }
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfficialAnkiReviewPage(
            engine: OfficialAnkiSessionEngine(session),
            paths: paths,
            deckId: fixtureDeckId,
            allowedCardIds: fixtureCardIds,
          ),
        ),
      );
      setState(() => _status = 'formal_reviewed');
    } catch (error, stack) {
      debugPrint('[OfficialAnkiReview] error $error\n$stack');
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMigrationPreview() async {
    setState(() {
      _busy = true;
      _status = 'collecting_census';
    });
    try {
      CourseDatabase? courseDb;
      try {
        courseDb = CourseLoader.databaseOrNull() ??
            (getIt.isRegistered<CourseDatabase>() ? getIt<CourseDatabase>() : null);
      } catch (_) {
        courseDb = null;
      }

      DatabaseLegacyAnkiCensusReader? reader;
      LegacyAnkiCensusReport census;
      if (courseDb != null) {
        reader = DatabaseLegacyAnkiCensusReader(courseDb);
        census = await LegacyAnkiCensusService(reader).collect(
          platform: Platform.operatingSystem,
        );
      } else {
        census = LegacyAnkiCensusReport(
          generatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          platform: Platform.operatingSystem,
          imports: const [],
        );
      }

      final support = await getApplicationSupportDirectory();
      final paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot: Directory('${support.path}/official_anki/default'),
      );
      final preview = await const OfficialAnkiMigrationPreviewLoader().load(
        paths: paths,
        census: census,
        identityReader: reader,
      );

      if (!mounted) return;
      final selected = preview.selectedImport;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfficialAnkiMigrationPreviewPage(
            census: preview.census,
            dryRun: preview.dryRun,
            diskFreeBytes: preview.diskFreeBytes,
            displayName: preview.displayName,
            importId: selected?.importId,
            sourceHash: selected?.sourceHash,
            flags: OfficialAnkiFeatureFlags.current,
            coordinator: _ops,
            onFixturePilot: selected == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    unawaited(_runFixturePilot(
                      preview: preview,
                      paths: paths,
                      reader: reader,
                    ));
                  },
          ),
        ),
      );
      setState(() => _status = 'previewed_migration');
    } catch (error, stack) {
      debugPrint('[OfficialAnkiPreview] migration preview error $error\n$stack');
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _seedP5cFixtureLegacy() async {
    setState(() {
      _busy = true;
      _status = 'seeding_fixture';
    });
    try {
      if (!OfficialAnkiFeatureFlags.current.migrationPilot) {
        setState(() {
          _status = 'pilot_off';
          _detail = '需要 TURNA_OFFICIAL_ANKI_MIGRATION_PILOT=true';
        });
        return;
      }
      final fixture = await _locateP5cFixture();
      if (fixture == null) {
        setState(() {
          _status = 'fixture_missing';
          _detail = '把 p5c-basic-cloze.apkg 放到应用 files/ 后再试';
        });
        return;
      }
      final collection = await AnkiImporter().parse(fixture.path);
      const importId = 'p5c-fixture-device';
      final sourceHashReal = sha256.convert(await fixture.readAsBytes()).toString();

      CourseDatabase? courseDb;
      try {
        courseDb = CourseLoader.databaseOrNull() ??
            (getIt.isRegistered<CourseDatabase>()
                ? getIt<CourseDatabase>()
                : null);
      } catch (_) {
        courseDb = null;
      }
      if (courseDb == null) {
        setState(() {
          _status = 'no_course_db';
          _detail = 'CourseDatabase 未就绪';
        });
        return;
      }
      final importDao = AnkiImportDao(courseDb);
      final noteDao = AnkiNoteDao(courseDb);
      // Re-seed must replace leftover cards from a previous fixture package.
      await noteDao.deleteByImport(importId);
      await importDao.upsert(
        AnkiImportRecord(
          importId: importId,
          sourcePath: fixture.path,
          sourceHash: sourceHashReal,
          importedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          deckCount: collection.decks.length,
          noteCount: collection.notes.length,
          cardCount: collection.cards.length,
          status: 'complete',
          sourceCardCount: collection.cards.length,
          storedCardCount: collection.cards.length,
          indexedCardCount: collection.cards.length,
        ),
      );
      for (final note in collection.notes) {
        await noteDao.upsertNote(
          AnkiNoteRecord(
            importId: importId,
            noteId: note.id,
            mid: note.mid,
            tags: note.tags,
            fields: note.fields,
            sfld: note.sortField,
            guid: note.guid,
            mod: note.mod,
          ),
        );
      }
      for (final card in collection.cards) {
        await noteDao.upsertCardMeta(
          AnkiCardMetaRecord(
            importId: importId,
            cardId: card.id,
            noteId: card.nid,
            ord: card.ord,
            did: card.did,
            wordId: 'anki-$importId-c${card.id}',
          ),
        );
      }
      setState(() {
        _status = 'fixture_seeded';
        _detail =
            'importId=$importId cards=${collection.cards.length} hash=$sourceHashReal';
      });
    } catch (error, stack) {
      debugPrint('[OfficialAnkiPilot] seed error $error\n$stack');
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runFixturePilot({
    required OfficialAnkiMigrationPreviewModel preview,
    required OfficialAnkiPaths paths,
    DatabaseLegacyAnkiCensusReader? reader,
  }) async {
    setState(() {
      _busy = true;
      _status = 'fixture_pilot';
    });
    OfficialAnkiDatabase? catalog;
    OfficialAnkiFixturePilotSaga? saga;
    try {
      final flags = OfficialAnkiFeatureFlags.current;
      if (!flags.migrationPilot) {
        setState(() {
          _status = 'pilot_off';
          _detail = '需要 TURNA_OFFICIAL_ANKI_MIGRATION_PILOT=true';
        });
        return;
      }
      final first = preview.selectedImport;
      if (first == null) {
        setState(() {
          _status = 'not_allowlist';
          _detail = '该来源不在 P5-C fixture allowlist';
        });
        return;
      }
      final known = await _locateP5cFixture();
      var packagePath = known?.path;
      if (packagePath == null) {
        final picked = await OhosFilePicker.pickFiles(
          allowedExtensions: const ['apkg'],
          dialogTitle: '重选原 fixture .apkg',
        );
        packagePath = picked?.files.single.path;
      }
      if (packagePath == null) {
        setState(() {
          _status = 'cancelled';
          _detail = '未选择原包';
        });
        return;
      }
      catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      final dao = OfficialAnkiMigrationDao(catalog);
      saga = OfficialAnkiFixturePilotSaga(dao: dao, coordinator: _ops);
      final existing = dao.findByLegacyImport(
        profileId: paths.profileId,
        legacyImportId: first.importId,
      );
      final migrationId = existing?.migrationId ?? 'mig-${first.importId}';
      saga.start(
        migrationId: migrationId,
        profileId: paths.profileId,
        legacyImportId: first.importId,
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        sourceHash: first.sourceHash,
        legacyCardCount: first.cardCount,
      );
      final identities = reader == null
          ? const <LegacyAnkiCardIdentity>[]
          : await reader.loadCardIdentities(first.importId);
      final okHash = await saga.pickAndValidatePackage(
        migrationId: migrationId,
        pickedFile: File(packagePath),
        expectedSourceHash: first.sourceHash,
        paths: paths,
        legacyCards: identities,
        census: preview.census,
      );
      if (!okHash) {
        setState(() {
          _status = 'package_mismatch';
          _detail = '重选的 .apkg hash 与 census.sourceHash 不一致';
        });
        return;
      }
      final support = await getApplicationSupportDirectory();
      final importer = await OfficialAnkiCompositionRoot.requireImporter(
        supportDir: support,
      );
      final sourceId = await saga.importOfficial(
        migrationId: migrationId,
        packagePath: packagePath,
        importer: importer,
        displayName: 'p5c-fixture-${first.importId}',
      );
      // Worker wrote catalog on another connection. Re-open before listing cards.
      catalog.close();
      catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      saga = OfficialAnkiFixturePilotSaga(
        dao: OfficialAnkiMigrationDao(catalog),
        coordinator: _ops,
      );
      final officialRows = OfficialAnkiSourceDao(catalog).listCardsForImport(
        sourceId: sourceId,
        profileId: paths.profileId,
        sourceHash: first.sourceHash,
      );
      final official = [
        for (final card in officialRows)
          OfficialAnkiCardIdentity(
            officialCardId: card.cardId,
            templateOrd: card.templateOrd,
            officialNoteId: card.noteId,
            noteGuid: card.noteGuid,
          ),
      ];
      final matched = await saga.indexAndMatchCards(
        migrationId: migrationId,
        legacyCards: identities,
        officialCards: official,
        sameTrustedPackage: true,
      );
      if (!matched) {
        setState(() {
          _status = 'mapping_unresolved';
          _detail =
              'dry-run 未 100% 唯一匹配 legacy=${identities.length} official=${official.length} source=$sourceId';
        });
        return;
      }
      var projectionItems = 0;
      final projected = await saga.projectCourse(
        migrationId: migrationId,
        projectionAction: () async {
          if (!flags.allowsProjection) {
            throw StateError('projection flag off');
          }
          final session = OfficialAnkiCompositionRoot.session;
          final course = CourseLoader.databaseOrNull();
          if (session is! OfficialAnkiSession || course == null) {
            throw StateError('projection engine/course unavailable');
          }
          await session.ensureCollectionOpen();
          final result = await OfficialAnkiCourseProjectionService(
            engine: OfficialAnkiSessionEngine(session),
            catalog: catalog!,
            course: course,
            sourceId: sourceId,
            profileId: paths.profileId,
            flags: flags,
          ).projectSourceForFixturePilot();
          if (result.failed || result.needsMapping || result.itemCount == 0) {
            throw StateError(
              result.errorCode ??
                  (result.needsMapping
                      ? 'projection_needs_mapping'
                      : 'projection_empty'),
            );
          }
          projectionItems = result.itemCount;
        },
      );
      if (!projected) {
        setState(() {
          _status = 'projection_failed';
          _detail = '课程投影失败';
        });
        return;
      }
      final cutover = await saga.verifyAndCutover(
        migrationId: migrationId,
        legacyCardCount: identities.length,
        officialCardCount: official.length,
        legacyNoteCount: first.noteCount,
        officialNoteCount: official.map((c) => c.officialNoteId).toSet().length,
        legacyDeckCount: first.deckCount,
        officialDeckCount: first.deckCount,
        legacyMediaCount: first.mediaCount,
        officialMediaCount: first.mediaCount,
        projectionItemCount: projectionItems,
        matchedCount: identities.length,
      );
      setState(() {
        _status = cutover ? 'observing' : 'verify_mismatch';
        _detail = cutover
            ? 'fixture pilot observing source=$sourceId'
            : 'verifying 计数不一致';
      });
    } catch (error, stack) {
      debugPrint('[OfficialAnkiPilot] error $error\n$stack');
      setState(() {
        _status = 'error';
        _detail = error.toString();
      });
    } finally {
      saga?.releaseLease();
      catalog?.close();
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
          Text(
            'scheduler=${OfficialAnkiFeatureFlags.current.allowsOfficialScheduler} '
            'migrationPilot=${OfficialAnkiFeatureFlags.current.migrationPilot}',
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
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('official-import-device-fixture'),
              onPressed: _busy ? null : _importDeviceFixture,
              child: const Text('导入设备测试牌组'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _canOpenOfficialSurfaces ? _openFirstCard : null,
            child: const Text('预览已导入官方卡片'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('official-formal-review-open'),
            onPressed: _canOpenOfficialSurfaces ? _openFormalReview : null,
            child: const Text('正式复习'),
          ),
          if (OfficialAnkiFeatureFlags.current.migrationPilot) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('official-p5c-seed-fixture'),
              onPressed: _busy ? null : _seedP5cFixtureLegacy,
              child: const Text('导入 P5C fixture（Legacy）'),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('official-source-management-open'),
            onPressed: _busy ? null : _openSourceManagement,
            child: const Text('课程映射 / 生成'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('official-migration-preview-open'),
            onPressed: _busy ? null : _openMigrationPreview,
            child: const Text('Legacy 迁移预览'),
          ),
        ],
      ),
    );
  }
}
