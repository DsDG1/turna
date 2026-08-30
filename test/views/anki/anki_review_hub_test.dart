import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_review_screen.dart';

import '../../helpers/in_memory_course_db.dart';

class _HubStubCourseProvider extends CourseProvider {
  _HubStubCourseProvider({
    required List<Section> sections,
    List<CourseCatalogEntry> catalog = const [],
  })  : _sectionsOverride = sections,
        _catalogOverride = catalog;

  final List<Section> _sectionsOverride;
  final List<CourseCatalogEntry> _catalogOverride;

  @override
  List<Section> get allSections => _sectionsOverride;

  @override
  List<CourseCatalogEntry> get catalogEntries => _catalogOverride;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensurePathProviderMockForTest();

  setUp(OfficialFormalDueRepository.instance.resetForTest);
  tearDown(OfficialFormalDueRepository.instance.resetForTest);

  Widget wrap(CourseProvider course) {
    return ChangeNotifierProvider<CourseProvider>.value(
      value: course,
      child: const MaterialApp(home: AnkiReviewPage()),
    );
  }

  testWidgets('empty hub shows import empty state', (tester) async {
    await tester.pumpWidget(wrap(_HubStubCourseProvider(sections: const [])));
    await tester.pump();

    expect(find.text(AppStrings.ankiNoDecksTitle), findsOneWidget);
    expect(find.text(AppStrings.ankiImportDeck), findsOneWidget);
    expect(find.byKey(const Key('anki-review-hub-hero')), findsNothing);
  });

  testWidgets('deck list uses caught-up hero and visible browse/stats',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        _HubStubCourseProvider(
          sections: const [
            Section(
              id: 'official-anki-deck1-s1',
              name: '核心词汇',
              description: '日常用语',
              level: 'OfficialAnki',
              units: [],
            ),
          ],
          catalog: [
            CourseCatalogEntry(
              scope: const OfficialAnkiCourseScope(
                profileId: 'profile-default-01',
                sourceId: 'deck1',
              ),
              displayName: '核心词汇',
              isBuiltin: false,
              officialSourceId: 'deck1',
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.ankiHubCaughtUpTitle), findsOneWidget);
    expect(find.text(AppStrings.ankiHubDecksTitle), findsOneWidget);
    expect(find.text('核心词汇'), findsOneWidget);
    expect(find.text('日常用语'), findsOneWidget);
    expect(find.text(AppStrings.ankiBrowseCards), findsOneWidget);
    expect(find.text(AppStrings.ankiDeckStats), findsOneWidget);
    expect(find.byTooltip(AppStrings.ankiImportNewDeck), findsOneWidget);
  });
}
