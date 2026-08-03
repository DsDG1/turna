// Gold-standard regression test for the interactionItemId refactor.
//
// The pre-refactor implementation was `'$stageId#$index'`, which meant
// inserting a new interaction anywhere in a stage shifted every
// subsequent interaction's synthetic id — wiping out any per-item
// state the viewmodel had cached. The new implementation uses the
// interaction's own `id` field, so item identities must remain stable
// when other items are inserted or removed before them.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

void main() {
  group('interactionItemId stability', () {
    test('uses real id when present', () {
      const item = Interaction.multipleChoice(
        id: 'mc-yes',
        prompt: 'p',
        options: ['a', 'b'],
        correctIndex: 0,
      );
      expect(
          interactionItemId('stage-vocab', item.id, 0), 'stage-vocab#mc-yes');
    });

    test('falls back to legacy-N when id is empty', () {
      const item = Interaction.showWord(id: '', wordId: 'w-x');
      expect(
          interactionItemId('stage-vocab', item.id, 2), 'stage-vocab#legacy-2');
    });

    test('inserting an item before does not shift sibling ids', () {
      // Original stage: items at indices 0, 1, 2 with ids a, b, c.
      const a = Interaction.showWord(id: 'a', wordId: 'w-a');
      const b = Interaction.showWord(id: 'b', wordId: 'w-b');
      const c = Interaction.showWord(id: 'c', wordId: 'w-c');
      const stageId = 'stage-vocab';

      final before = [
        interactionItemId(stageId, a.id, 0),
        interactionItemId(stageId, b.id, 1),
        interactionItemId(stageId, c.id, 2),
      ];

      // Now insert a new item BEFORE `b`. The pre-refactor index-based
      // scheme would have produced: b' = stageId#2, c' = stageId#3 —
      // different from the original. The new scheme keeps them stable.
      const inserted = Interaction.showWord(id: 'x', wordId: 'w-x');
      final after = [
        interactionItemId(stageId, a.id, 0),
        interactionItemId(stageId, inserted.id, 1),
        interactionItemId(stageId, b.id, 2),
        interactionItemId(stageId, c.id, 3),
      ];

      expect(after[0], before[0]); // a unchanged
      expect(after[2], before[1]); // b unchanged
      expect(after[3], before[2]); // c unchanged
    });

    test('removing an item does not shift sibling ids', () {
      const a = Interaction.showWord(id: 'a', wordId: 'w-a');
      const b = Interaction.showWord(id: 'b', wordId: 'w-b');
      const c = Interaction.showWord(id: 'c', wordId: 'w-c');
      const stageId = 'stage-vocab';

      final before = [
        interactionItemId(stageId, a.id, 0),
        interactionItemId(stageId, b.id, 1),
        interactionItemId(stageId, c.id, 2),
      ];

      // Remove `b`. The new scheme must keep `c`'s id stable.
      final after = [
        interactionItemId(stageId, a.id, 0),
        interactionItemId(stageId, c.id, 1),
      ];

      expect(after[0], before[0]);
      expect(after[1], before[2]);
    });

    test('works for reading-question ids too', () {
      const q = Interaction.readingMcq(
        id: 'rm-happy',
        prompt: 'p',
        options: ['a', 'b'],
        correctIndex: 0,
      );
      expect(interactionItemId('stage-comp', q.id, 0), 'stage-comp#rm-happy');
    });
  });
}
