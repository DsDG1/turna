import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/views/anki/import_wizard/deck_directory_tree_view.dart';

void main() {
  test('deck tree caches counts and hides collapsed descendants', () {
    final roots = buildDeckTree(
      const [
        OfficialAnkiDeckNode(
          deckId: 1,
          name: 'Biology::Genetics::Mendel',
          level: 2,
        ),
        OfficialAnkiDeckNode(
          deckId: 2,
          name: 'Biology::Genetics::Darwin',
          level: 2,
        ),
      ],
      const {1: 42, 2: 8},
    );

    expect(roots.single.isExpanded, isTrue);
    expect(roots.single.subtreeTotal, 50);
    final genetics = roots.single.children.single;
    expect(genetics.name, 'Genetics');
    expect(genetics.isExpanded, isFalse);
    expect(genetics.subtreeTotal, 50);

    final collapsed = visibleDeckNodes(roots).map((entry) => entry.node.name);
    expect(collapsed, ['Biology', 'Genetics']);

    genetics.isExpanded = true;
    final expanded = visibleDeckNodes(roots).map((entry) => entry.node.name);
    expect(expanded, ['Biology', 'Genetics', 'Mendel', 'Darwin']);
  });
}
