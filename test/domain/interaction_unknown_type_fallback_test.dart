// Regression: [Interaction.fromJson] previously delegated directly to the
// generated `_$InteractionFromJson`, which throws `CheckedFromJsonException`
// for any unrecognized `runtimeType`. At the runtime read path that throw is
// swallowed by `CourseRepository._toLesson`, silently emptying the whole
// lesson. The factory now degrades to a benign `ShowWord` carrying the
// offending type so the lesson still loads.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';

void main() {
  group('Interaction.fromJson unknown-type fallback', () {
    test('degrades unknown runtimeType to ShowWord with diagnostic wordId',
        () {
      final interaction = Interaction.fromJson(const {
        'runtimeType': 'futureUnknownType',
        'prompt': 'ignored',
      });
      expect(interaction, isA<ShowWord>());
      final wordId = (interaction as ShowWord).wordId;
      // The prefix is the shared [unknownInteractionWordIdPrefix] constant —
      // consumers (_registerSrsWords, ShowWordRenderer) match on it, so pin it
      // here so a rename breaks this test rather than silently desyncing them.
      expect(wordId.startsWith(unknownInteractionWordIdPrefix), isTrue);
      expect(wordId, '$unknownInteractionWordIdPrefix${'futureUnknownType'}');
    });

    test('degrades missing runtimeType to ShowWord', () {
      final interaction = Interaction.fromJson(const <String, dynamic>{
        'prompt': 'no type here',
      });
      expect(interaction, isA<ShowWord>());
      expect(
        (interaction as ShowWord).wordId,
        '$unknownInteractionWordIdPrefix${'unknown'}',
      );
    });

    test('known types still parse unchanged', () {
      final interaction = Interaction.fromJson(const {
        'runtimeType': 'multipleChoice',
        'prompt': 'Pick one',
        'options': <String>['a', 'b'],
        'correctIndex': 0,
      });
      expect(interaction, isA<MultipleChoice>());
      final mc = interaction as MultipleChoice;
      expect(mc.prompt, 'Pick one');
      expect(mc.options, ['a', 'b']);
      expect(mc.correctIndex, 0);
    });
  });
}