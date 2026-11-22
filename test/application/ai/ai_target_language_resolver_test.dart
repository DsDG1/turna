// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/ai_target_language_resolver.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/interaction.dart';

void main() {
  setUp(() {
    LanguageRegistry.instance.resetForTest();
    ImportedLanguageRegistry.instance.resetForTest();
  });

  tearDown(() {
    LanguageRegistry.instance.resetForTest();
    ImportedLanguageRegistry.instance.resetForTest();
  });

  group('AiTargetLanguageResolver.fromCourseScope', () {
    test('resolves builtin Turkish course scope to Turkish', () {
      final lang = AiTargetLanguageResolver.fromCourseScope(
        const BuiltinCourseScope('tr'),
      );
      expect(lang.isGeneric, isFalse);
      expect(lang.code, 'tr');
      expect(lang.displayName, 'Turkish');
    });

    test('resolves imported language pack display name from overlay registry',
        () {
      ImportedLanguageRegistry.instance.remember('ja', {
        'displayName': 'Japanese',
        'nativeLabel': '日本語',
      });
      final lang = AiTargetLanguageResolver.fromCourseScope(
        const BuiltinCourseScope('ja'),
      );
      expect(lang.isGeneric, isFalse);
      expect(lang.code, 'ja');
      expect(lang.displayName, 'Japanese');
    });

    test('resolves OfficialAnkiCourseScope to generic mode (never Turkish)',
        () {
      final lang = AiTargetLanguageResolver.fromCourseScope(
        const OfficialAnkiCourseScope(profileId: 'p1', sourceId: 'deck-42'),
      );
      expect(lang.isGeneric, isTrue);
      expect(lang.code, isNull);
      expect(lang.displayName, isNull);
    });
  });

  group('AiTargetLanguageResolver.forLessonInteraction', () {
    test('returns generic mode for AnkiCard even inside builtin scope', () {
      final lang = AiTargetLanguageResolver.forLessonInteraction(
        scope: const BuiltinCourseScope('tr'),
        interaction: const Interaction.ankiCard(
          id: 'c1',
          front: '食べる',
          back: 'eat',
        ),
      );
      expect(lang.isGeneric, isTrue);
    });

    test('returns generic mode for AnkiHtmlCard', () {
      final lang = AiTargetLanguageResolver.forLessonInteraction(
        scope: const BuiltinCourseScope('tr'),
        interaction: const Interaction.ankiHtmlCard(
          id: 'c2',
          frontHtml: '<div>Bonjour</div>',
          backHtml: '<div>Hello</div>',
        ),
      );
      expect(lang.isGeneric, isTrue);
    });

    test('returns generic mode when isAnkiOwned is true on any interaction',
        () {
      final lang = AiTargetLanguageResolver.forLessonInteraction(
        scope: const BuiltinCourseScope('tr'),
        interaction: const Interaction.multipleChoice(
          id: 'q1',
          prompt: 'Pick one',
          options: ['a', 'b'],
          correctIndex: 0,
        ),
        isAnkiOwned: true,
      );
      expect(lang.isGeneric, isTrue);
    });

    test('returns builtin course language for normal lesson interactions', () {
      final lang = AiTargetLanguageResolver.forLessonInteraction(
        scope: const BuiltinCourseScope('tr'),
        interaction: const Interaction.multipleChoice(
          id: 'q1',
          prompt: 'Merhaba',
          options: ['你好', '再见'],
          correctIndex: 0,
        ),
      );
      expect(lang.isGeneric, isFalse);
      expect(lang.displayName, 'Turkish');
    });
  });

  group('AiTargetLanguageResolver.fromLanguageCode', () {
    test('empty, null, or generic sentinel resolves to generic mode', () {
      expect(AiTargetLanguageResolver.fromLanguageCode(null).isGeneric, isTrue);
      expect(AiTargetLanguageResolver.fromLanguageCode('  ').isGeneric, isTrue);
      expect(
        AiTargetLanguageResolver.fromLanguageCode(
          AiTargetLanguageResolver.genericCode,
        ).isGeneric,
        isTrue,
      );
    });

    test('unknown custom language code preserves display label', () {
      final lang = AiTargetLanguageResolver.fromLanguageCode(
        'Japanese',
        fallbackDisplayName: 'Japanese',
      );
      expect(lang.isGeneric, isFalse);
      expect(lang.displayName, 'Japanese');
    });
  });
}
