import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_backup_manifest.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

void main() {
  test('remount polish keeps one PlatformView and treats Congrats as success', () {
    final view = File(
      'lib/views/anki_official/official_anki_reviewer_view.dart',
    ).readAsStringSync();
    expect(view.contains('if (_hcpp == null)'), isFalse);
    expect(view.contains('_hcppCached'), isTrue);
    final stage = File(
      'lib/views/anki_official/official_anki_reviewer_stage.dart',
    ).readAsStringSync();
    expect(stage.contains('_surfaceReleased'), isTrue);
    expect(
      stage.contains('scaffoldBackgroundColor.withValues'),
      isTrue,
      reason: 'fatal overlay must stay translucent over the WebView',
    );
    expect(
      stage.contains('color: Theme.of(context).scaffoldBackgroundColor,'),
      isFalse,
      reason: 'opaque ColoredBox disposes the occluded PlatformView',
    );
    final page = File(
      'lib/views/anki_official/official_anki_review_page.dart',
    ).readAsStringSync();
    expect(page.contains('_keepReviewerSurface'), isTrue);
    final rate = File('tool/official_anki_device_rate.py').readAsStringSync();
    expect(rate.contains('queue_exhausted'), isTrue);
    expect(rate.contains('queue_exhausted and timeouts == 0'), isTrue);
    final internal = File(
      'lib/application/anki_official/official_anki_internal_page.dart',
    ).readAsStringSync();
    expect(internal.contains('_warmupWorker'), isTrue);
    expect(internal.contains("_status = 'opening'"), isTrue);
    expect(internal.contains('_canOpenOfficialSurfaces'), isTrue);
  });

  test('native poll treats only renderComplete as success', () {
    final platform = File(
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerPlatformView.kt',
    ).readAsStringSync();
    expect(platform.contains('type == "cardAccepted" || type == "frameReady"'), isTrue);
    expect(platform.contains('type == "renderComplete" || type == "renderError"'), isTrue);
    expect(
      platform.contains('val ok = type == "renderComplete"'),
      isTrue,
    );
  });

  test('renderError is not recoverable and maps to unrenderable', () {
    expect(
      OfficialAnkiReviewerUi.recoverableCodes.contains('renderError'),
      isFalse,
    );
    expect(OfficialAnkiReviewerUi.isRecoverableCode('RENDER_TIMEOUT'), isTrue);
    expect(OfficialAnkiReviewerUi.isRecoverableCode('UNRENDERABLE_CARD'), isFalse);
    final parsed = OfficialAnkiPresentResult.fromNative(<String, Object?>{
      'ok': false,
      'code': 'renderError',
    });
    expect(parsed.code, 'UNRENDERABLE_CARD');
    expect(parsed.recoverable, isFalse);
  });

  test('legacy match goldens are identity-only files', () {
    const matcher = LegacyAnkiDryRunMatcher();
    final dir = Directory('test/application/anki_official/fixtures/legacy_match');
    expect(dir.existsSync(), isTrue);
    for (final file in dir.listSync().whereType<File>()) {
      final encoded = file.readAsStringSync();
      expect(encoded.contains('questionHtml'), isFalse);
      expect(encoded.contains('你好'), file.path.contains('unicode'));
      final json = jsonDecode(encoded) as Map<String, Object?>;
      final legacy = [
        for (final row in json['legacy']! as List)
          LegacyAnkiCardIdentity(
            legacyCardId: (row as Map)['legacyCardId'] as int,
            legacyWordId: row['legacyWordId'] as String,
            templateOrd: row['templateOrd'] as int,
            noteGuid: row['noteGuid'] as String?,
          ),
      ];
      final official = [
        for (final row in json['official']! as List)
          OfficialAnkiCardIdentity(
            officialCardId: (row as Map)['officialCardId'] as int,
            templateOrd: row['templateOrd'] as int,
            noteGuid: row['noteGuid'] as String?,
          ),
      ];
      final result = matcher.match(legacy: legacy, official: official);
      final expected = json['expected']! as List;
      expect(result.rows.length, expected.length, reason: file.path);
      for (var i = 0; i < expected.length; i++) {
        final want = expected[i] as Map;
        expect(result.rows[i].legacyCardId, want['legacyCardId']);
        expect(result.rows[i].matchState.name, want['matchState']);
        if (want['officialCardId'] != null) {
          expect(result.rows[i].officialCardId, want['officialCardId']);
        }
      }
    }
  });

  test('backup persist file has counts only', () async {
    const census = LegacyAnkiCensusReport(
      generatedAtMillis: 1,
      platform: 'linux',
      imports: [
        LegacyAnkiImportCensus(
          importId: 'imp',
          sourceHash: 'h',
          noteCount: 2,
          cardCount: 3,
          mediaCount: 0,
          deckCount: 1,
          importedScheduling: false,
          status: 'ready',
          sourceFilePresent: true,
          srsRowCount: 3,
          reviewEventCount: 0,
          duplicateGuidCount: 0,
          missingGuidCount: 0,
        ),
      ],
    );
    const service = LegacyAnkiBackupService();
    final first = service.generateFromCensus(census: census, createdAtMillis: 9);
    final second = service.generateFromCensus(census: census, createdAtMillis: 9);
    expect(first.legacyRowHash, second.legacyRowHash);
    final root = Directory.systemTemp.createTempSync('turna-backup-');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = await service.persist(
      manifest: first,
      targetFile: File('${root.path}/legacy-manifest-mig.json'),
    );
    final body = file.readAsStringSync();
    expect(body.contains('你好'), isFalse);
    expect(body.contains('questionHtml'), isFalse);
    expect(body.contains('/home/'), isFalse);
    expect(
      LegacyAnkiBackupManifest.fromJson(
        jsonDecode(body) as Map<String, Object?>,
      ).legacyRowCount,
      first.legacyRowCount,
    );
  });

  test('daily limit empties queue until next day reset', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    fake.newPerDayLimit = 1;
    final session = OfficialReviewSession(engine: fake, flags: _flags);
    await session.openDeck(1);
    expect(session.current, isNotNull);
    session.showAnswer();
    await session.answer('good');
    expect(session.phase, OfficialReviewPhase.completed);
    expect(session.congrats, isNotNull);
    fake.newPerDayLimit = 3;
    fake.officialAnswers = 0;
    await session.refreshQueue();
    expect(session.current, isNotNull);
  });
}
