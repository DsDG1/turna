import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_ffi.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';

bool get _requireNative =>
    Platform.environment['TURNA_ANKI_REQUIRE_NATIVE'] == '1';

void main() {
  final libraryPath = resolveOfficialAnkiLibraryPath();

  test('production transport loads Host .so and reports runtime metadata', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    expect(transport.abiVersion(), 1);
    final engine = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(engine.dispose);
    final info = await engine.engineInfo();
    expect(info.abiVersion, 1);
    expect(info.contractMajor, 1);
    expect(info.backendCommit, isNotEmpty);
    expect(info.backendCommit, isNot('unknown'));
    expect(info.has(OfficialAnkiOperation.importPackage), isTrue);
    expect(info.has(OfficialAnkiOperation.renderCard), isTrue);
    expect(info.has(OfficialAnkiOperation.compareTypedAnswer), isTrue);
    expect(info.contractMinor, anyOf(2, 3, 4));
  });

  test('Host FFI openProfile is idempotent when Collection is already open', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final root = Directory.systemTemp.createTempSync('turna-reopen-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-reopen01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final engine = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(engine.dispose);
    await engine.openProfile(paths);
    await engine.openProfile(paths);
    await engine.checkCollection();
  });

  test('second engine reclaims an idle collection holder', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final root = Directory.systemTemp.createTempSync('turna-reclaim-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-reclaim01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final leaked = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(leaked.dispose);
    final next = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(next.dispose);
    await leaked.openProfile(paths);
    await next.openProfile(paths);
    await next.checkCollection();
    await expectLater(
      leaked.closeCollection(),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.invalidState,
        ),
      ),
    );
  });

  test('Dart allocator → C ABI → rslib → catalog for unicode fixture', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final root = Directory.systemTemp.createTempSync('turna-host-ffi-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-host-ffi01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final engine = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(engine.dispose);
    final db = OfficialAnkiDatabase.file('${root.path}/catalog.sqlite');
    addTearDown(db.close);
    final pkg = File(
      p.absolute('test/fixtures/anki_official/packages/01-basic-unicode.apkg'),
    );
    final imported = await OfficialAnkiImportOrchestrator(
      engine: engine,
      sources: OfficialAnkiSourceDao(db),
      attempts: OfficialAnkiImportAttemptDao(db),
      paths: paths,
    ).importFile(packagePath: pkg.path, displayName: 'unicode');
    expect(imported.state, OfficialAnkiSourceState.active);
    expect(imported.cardCount, greaterThan(0));
    expect(imported.noteCount, greaterThan(0));
    await engine.closeCollection();
    await engine.openProfile(paths);
    await engine.checkCollection();
    final listed = OfficialAnkiSourceDao(db).findById(imported.sourceId);
    expect(listed?.state, 'active');
  });

  test('worker isolate heartbeat continues during fake import', () async {
    final root = Directory.systemTemp.createTempSync('turna-isolate-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-isolate01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final session = await OfficialAnkiSession.spawn(
      paths: paths,
      catalogPath: '${root.path}/catalog.sqlite',
      useFake: true,
    );
    addTearDown(session.dispose);
    var ticks = 0;
    final ticker = Stream<int>.periodic(const Duration(milliseconds: 20), (i) => i)
        .listen((_) => ticks++);
    addTearDown(ticker.cancel);
    final pkg = File(
      p.join('test/fixtures/anki_official/packages/01-basic-unicode.apkg'),
    );
    final imported = await session.importFile(
      packagePath: pkg.path,
      displayName: 'isolate-unicode',
    );
    expect(imported.state, OfficialAnkiSourceState.active);
    expect(ticks, greaterThan(0));
  });

  test('Host FFI renders nine official fixtures and compares typed answer', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final expectedDir = Directory('test/fixtures/anki_official/expected');
    final packages = [
      '01-basic-unicode',
      '02-basic-reversed',
      '03-optional-reversed',
      '04-cloze-multi-ord',
      '05-frontside-css',
      '06-media-paths',
      '07-typed-answer',
      '08-scheduling',
      '09-legacy-package',
    ];
    for (final name in packages) {
      final root = Directory.systemTemp.createTempSync('turna-render-$name-');
      addTearDown(() => root.deleteSync(recursive: true));
      final paths = OfficialAnkiPaths(
        profileId: 'profile-r${name.substring(0, 2)}01',
        profileRoot: Directory('${root.path}/profile'),
      );
      final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
      final engine = FfiOfficialAnkiEngine.connect(transport);
      addTearDown(engine.dispose);
      final db = OfficialAnkiDatabase.file('${root.path}/catalog.sqlite');
      addTearDown(db.close);
      final pkg = File('test/fixtures/anki_official/packages/$name.apkg');
      final imported = await OfficialAnkiImportOrchestrator(
        engine: engine,
        sources: OfficialAnkiSourceDao(db),
        attempts: OfficialAnkiImportAttemptDao(db),
        paths: paths,
      ).importFile(packagePath: pkg.absolute.path, displayName: name);
      expect(imported.state, OfficialAnkiSourceState.active);
      final page = await engine.searchCardsPage();
      expect(page.cardIds, isNotEmpty);
      final expected = jsonDecode(
        File('${expectedDir.path}/$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final expectedCards = expected['cards'] as List;
      final rendered = <OfficialAnkiRenderedCard>[];
      for (final cardId in page.cardIds) {
        rendered.add(await engine.renderCard(cardId: cardId));
      }
      expect(rendered.length, expectedCards.length, reason: name);
      for (final exp in expectedCards) {
        final expMap = Map<String, Object?>.from(exp as Map);
        expect(
          rendered.any(
            (got) =>
                got.questionHtml == expMap['questionHtml'] &&
                got.answerHtml == expMap['answerHtml'],
          ),
          isTrue,
          reason: '$name missing ${expMap['questionHtml']}',
        );
      }
      if (name == '07-typed-answer') {
        final card = rendered.single;
        expect(card.typedAnswer?.marker, '[[type:Back]]');
        final compared = await engine.compareTypedAnswer(
          cardId: card.cardId,
          marker: '[[type:Back]]',
          provided: 'typed-back',
        );
        expect(compared.hasExpected, isTrue);
        expect(compared.comparisonHtml, contains('typeans'));
      }
      if (name == '02-basic-reversed') {
        expect(rendered.length, 2);
        expect(rendered.any((card) => card.templateOrdinal == 1), isTrue);
        expect(rendered.any((card) => card.bodyClass.contains('card2')), isTrue);
        for (final card in rendered) {
          expect(card.bodyClass, contains('card${card.templateOrdinal + 1}'));
        }
      }
      if (name == '06-media-paths') {
        expect(
          rendered.first.answerAvTags.any((tag) => tag.filename == 'paren (1).mp3'),
          isTrue,
        );
        expect(rendered.first.answerDisplayHtml.contains('[sound:'), isFalse);
      }
    }
  });

  test('Host FFI set-deck queue answer good then stale token', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final root = Directory.systemTemp.createTempSync('turna-host-sched-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-host-sched01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final engine = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(engine.dispose);
    final db = OfficialAnkiDatabase.file('${root.path}/catalog.sqlite');
    addTearDown(db.close);
    final pkg = File(
      p.absolute('test/fixtures/anki_official/packages/08-scheduling.apkg'),
    );
    final imported = await OfficialAnkiImportOrchestrator(
      engine: engine,
      sources: OfficialAnkiSourceDao(db),
      attempts: OfficialAnkiImportAttemptDao(db),
      paths: paths,
    ).importFile(packagePath: pkg.path, displayName: 'scheduling');
    expect(imported.state, OfficialAnkiSourceState.active);
    await engine.setCurrentDeck(1);
    final queue = await engine.getReviewQueue(fetchLimit: 1);
    expect(queue.cards, isNotEmpty);
    expect(queue.cards.single.answerToken, isNotEmpty);
    final first = await engine.answerCard(
      sessionId: queue.sessionId,
      queueEpoch: queue.queueEpoch,
      answerToken: queue.cards.single.answerToken,
      cardId: queue.cards.single.cardId,
      rating: 'good',
      millisecondsTaken: 3210,
    );
    expect(first.millisecondsTaken, 3210);
    expect(first.committed, isTrue);
    expect(first.revlogCount, greaterThan(0));
    await expectLater(
      engine.answerCard(
        sessionId: queue.sessionId,
        queueEpoch: queue.queueEpoch,
        answerToken: queue.cards.single.answerToken,
        cardId: queue.cards.single.cardId,
        rating: 'good',
        millisecondsTaken: 10,
      ),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.schedulingContextStale,
        ),
      ),
    );
  });
}
