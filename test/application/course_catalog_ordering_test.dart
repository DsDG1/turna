// Plan P4 extraction tests: the catalog-ordering rules moved out of
// CourseProvider into CourseCatalogOrdering — pure, database-free.
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_catalog_ordering.dart';
import 'package:turna/domain/course/course_scope.dart';

CourseCatalogEntry _builtin(String code) => CourseCatalogEntry(
      scope: BuiltinCourseScope(code),
      displayName: 'Builtin $code',
      isBuiltin: true,
    );

CourseCatalogEntry _deck(String id) => CourseCatalogEntry(
      scope: OfficialAnkiCourseScope(profileId: 'default', sourceId: id),
      displayName: 'Deck $id',
      isBuiltin: false,
      officialSourceId: id,
    );

void main() {
  final entries = [_builtin('tr'), _deck('a'), _deck('b'), _deck('c')];
  final wires = entries.map((e) => e.wireKey).toList();

  group('CourseCatalogOrdering.applyOrder', () {
    test('reorders mentioned entries and keeps the rest at the tail', () {
      final ordered = CourseCatalogOrdering.applyOrder(
        entries,
        [wires[2], wires[0]], // deck b first, then builtin
      );
      expect(ordered.map((e) => e.displayName),
          ['Deck b', 'Builtin tr', 'Deck a', 'Deck c']);
    });

    test('drops unknown wires (deleted decks) and duplicates', () {
      final ordered = CourseCatalogOrdering.applyOrder(
        entries,
        ['course-scope:v1:official:default:gone', wires[1], wires[1]],
      );
      expect(ordered.map((e) => e.displayName),
          ['Deck a', 'Builtin tr', 'Deck b', 'Deck c']);
    });

    test('an empty wire list preserves the current order', () {
      final ordered = CourseCatalogOrdering.applyOrder(entries, []);
      expect(ordered.map((e) => e.wireKey), wires);
    });
  });

  group('CourseCatalogOrdering.deckReorderWires', () {
    test('dragged decks land right after the builtin course', () {
      final order = CourseCatalogOrdering.deckReorderWires(
        entries: entries,
        reorderedImportIds: ['c', 'a'],
      );
      expect(order, [wires[0], wires[3], wires[1], wires[2]]);
    });

    test('undragged decks go to the tail, undragged non-decks stay put', () {
      final order = CourseCatalogOrdering.deckReorderWires(
        entries: entries,
        reorderedImportIds: ['b'],
      );
      expect(order, [wires[0], wires[2], wires[1], wires[3]]);
    });

    test('unknown import ids are ignored', () {
      final order = CourseCatalogOrdering.deckReorderWires(
        entries: entries,
        reorderedImportIds: ['nope'],
      );
      expect(order, wires);
    });
  });
}
