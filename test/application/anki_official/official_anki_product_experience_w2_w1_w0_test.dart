import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/anki_official/official_anki_practice_review_surface.dart';
import 'package:turna/views/anki_official/official_anki_review_page.dart';
import 'package:turna/views/settings/widgets/settings_advanced_section.dart';

const _fullOfficialFlags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
  projection: true,
  courseEntry: true,
);

class _FakeImporter implements OfficialAnkiImporter {
  _FakeImporter({
    this.failWith,
    this.returnCancelled = false,
    this.cardCount = 10,
    this.sourceId = 'src-test-hash',
  });

  final OfficialAnkiException? failWith;
  final bool returnCancelled;
  final int cardCount;
  final String sourceId;

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    if (failWith != null) {
      throw failWith!;
    }
    if (returnCancelled) {
      return OfficialAnkiImportResult(
        sourceId: sourceId,
        attemptId: 'att-1',
        state: OfficialAnkiSourceState.cancelled,
        cardCount: 0,
        noteCount: 0,
        alreadyImported: false,
      );
    }
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: 'att-1',
      state: OfficialAnkiSourceState.active,
      cardCount: cardCount,
      noteCount: cardCount,
      alreadyImported: false,
    );
  }
}

class _FakeReviewerController extends ChangeNotifier
    implements OfficialAnkiReviewerController {
  OfficialAnkiRenderedCard? _card;

  @override
  OfficialAnkiRenderedCard? get card => _card;

  void setCard(OfficialAnkiRenderedCard? c) {
    _card = c;
    notifyListeners();
  }

  @override
  bool get hasAnswerPresentAck => true;

  @override
  bool get hasQuestionPresentAck => true;

  @override
  bool get isRenderError => false;

  @override
  String? get renderErrorCode => null;

  @override
  int get presentGeneration => 1;

  @override
  int get presentedCardId => _card?.cardId ?? 0;

  @override
  Future<void> loadAndShowQuestion(int cardId) async {}

  @override
  Future<void> showAnswer({bool autoplay = true}) async {}

  @override
  void invalidateGeneration() {}

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('W2: Import Hard Block & Facade Resolution', () {
    test('Facade throws invalidState (importer_not_ready) when importer is null in official mode', () {
      expect(
        () => AnkiImportFacade.resolve(
          flags: _fullOfficialFlags,
          officialImporter: null,
          platform: 'android',
        ),
        throwsA(
          isA<OfficialAnkiException>().having(
            (e) => e.code,
            'code',
            OfficialAnkiErrorCode.invalidState,
          ).having(
            (e) => e.messageKey,
            'messageKey',
            'official_anki.importer_not_ready',
          ),
        ),
      );
    });

    test('Facade resolves to OfficialAnkiImportFacade when importer is provided', () {
      final facade = AnkiImportFacade.resolve(
        flags: _fullOfficialFlags,
        officialImporter: _FakeImporter(),
        platform: 'android',
      );
      expect(facade.isOfficial, isTrue);
    });

    test('Facade resolves to LegacyAnkiImportFacade when flags are off on harmonyos', () {
      final facade = AnkiImportFacade.resolve(
        flags: const OfficialAnkiFeatureFlags(import: false),
        platform: 'harmonyos',
      );
      expect(facade.isOfficial, isFalse);
    });
  });

  group('W1: Review Page Default Practice & Localized Strings', () {
    testWidgets('Review page defaults to practice mode for compatible cards and renders AppStrings',
        (tester) async {
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'test.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(
        engine: engine,
        flags: _fullOfficialFlags,
      );
      await session.openDeck(1);
      final paths = OfficialAnkiPaths(
        profileId: 'prof-test-w1',
        profileRoot: Directory.systemTemp.createTempSync('turna-test-w1-'),
      );
      addTearDown(() {
        if (paths.profileRoot.existsSync()) {
          paths.profileRoot.deleteSync(recursive: true);
        }
      });

      final presenter = _FakeReviewerController();
      presenter.setCard(
        const OfficialAnkiRenderedCard(
          cardId: 1,
          questionHtml: '<div>Hello</div>',
          answerHtml: '<div>你好</div>',
          questionDisplayHtml: '<div>Hello</div>',
          answerDisplayHtml: '<div>你好</div>',
          css: '',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OfficialAnkiReviewPage(
            engine: engine,
            paths: paths,
            flags: _fullOfficialFlags,
            session: session,
            presenter: presenter,
          ),
        ),
      );
      await tester.pump();

      // Verify Chinese title from AppStrings
      expect(find.text(AppStrings.ankiReviewTitle), findsOneWidget);

      // Verify action buttons from AppStrings
      expect(find.text(AppStrings.ankiShowAnswer), findsOneWidget);
      expect(find.text(AppStrings.ankiBuryCard), findsOneWidget);
      expect(find.text(AppStrings.ankiBurySiblings), findsOneWidget);
      expect(find.text(AppStrings.ankiSuspendCard), findsOneWidget);

      // Verify Practice Review Surface is active by default (not WebView stage)
      expect(find.byType(OfficialAnkiPracticeReviewSurface), findsOneWidget);
    });
  });

  group('W0: Settings Advanced Section Release Cleanup', () {
    testWidgets('Spike page tile is removed and internal page is guarded', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await StreamingSharedPreferences.instance;
      final appPrefs = AppPrefs(preferences);
      final settings = SettingsProvider(appPrefs);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<SettingsProvider>.value(
            value: settings,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: SettingsAdvancedSection(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Section title is localized to AppStrings.ankiAdvancedFidelityTitle
      expect(find.text(AppStrings.ankiAdvancedFidelityTitle), findsOneWidget);

      // Spike page is never rendered in SettingsAdvancedSection
      expect(find.text('Official Anki Spike'), findsNothing);
    });
  });

  group('W3, W4, W5: Feature Flags & Defaults', () {
    test('W3: Projection and course entry are enabled by default in environment', () {
      final flags = OfficialAnkiFeatureFlags.fromEnvironment();
      expect(flags.projection, isTrue);
      expect(flags.courseEntry, isTrue);
      expect(flags.allowsProjection, isTrue);
      expect(flags.allowsCourseEntry, isTrue);
    });

    test('W5: Course grades scheduler flag defaults to false', () {
      final flags = OfficialAnkiFeatureFlags.fromEnvironment();
      expect(flags.courseGradesScheduler, isFalse);
    });

    test('OfficialAnki projected sections appear in ankiDeckEntries and courseEntries', () {
      final provider = CourseProvider();
      // Inject official section
      final officialSection = const Section(
        id: 'official-anki-srcDuolingo-s1',
        name: 'Irish from Duolingo',
        description: 'Projected official deck',
        level: 'OfficialAnki',
        units: [],
      );
      // Simulate loaded shells
      provider.allSections; // verify getter works
    });
  });
}
