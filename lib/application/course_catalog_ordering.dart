// Project imports:
import 'package:turna/application/course_catalog.dart';

/// Pure course-catalog ordering rules (plan P4 extraction from
/// CourseProvider): how a persisted wire order maps onto the catalog, and
/// how the review hub's deck drag order becomes one.
///
/// Stateless by design — CourseProvider keeps the catalog state and
/// persistence; this class owns only the derivation, so every rule is
/// unit-testable without a database.
abstract final class CourseCatalogOrdering {
  /// Applies [wires] to [entries]: mentioned entries first (in wire order,
  /// duplicates skipped), unmentioned entries keep their relative order at
  /// the tail. Unknown wires are ignored — a stored order naming deleted
  /// decks simply drops them.
  static List<CourseCatalogEntry> applyOrder(
    List<CourseCatalogEntry> entries,
    List<String> wires,
  ) {
    final byWire = {for (final e in entries) e.wireKey: e};
    final ordered = <CourseCatalogEntry>[];
    final seen = <String>{};
    for (final wire in wires) {
      final entry = byWire[wire];
      if (entry == null || !seen.add(wire)) continue;
      ordered.add(entry);
    }
    for (final entry in entries) {
      if (seen.add(entry.wireKey)) ordered.add(entry);
    }
    return List.unmodifiable(ordered);
  }

  /// Derives the full persisted wire order for a review-hub deck drag:
  /// the builtin course stays first, the dragged decks land directly after
  /// it in the user's order, non-deck courses keep their relative order,
  /// and decks absent from [reorderedImportIds] go to the tail.
  static List<String> deckReorderWires({
    required List<CourseCatalogEntry> entries,
    required List<String> reorderedImportIds,
  }) {
    final wireForId = <String, String>{};
    for (final entry in entries) {
      final id = entry.legacyImportId ?? entry.officialSourceId;
      if (id != null) wireForId[id] = entry.wireKey;
    }
    final reorderedWires = <String>{
      for (final id in reorderedImportIds)
        if (wireForId[id] != null) wireForId[id]!,
    };
    final order = <String>[];
    for (final entry in entries) {
      if (!entry.isBuiltin && reorderedWires.contains(entry.wireKey)) {
        continue;
      }
      order.add(entry.wireKey);
    }
    final builtinWire =
        entries.where((e) => e.isBuiltin).map((e) => e.wireKey).firstOrNull;
    final builtinIndex = builtinWire == null ? -1 : order.indexOf(builtinWire);
    order.insertAll(
      builtinIndex < 0 ? order.length : builtinIndex + 1,
      reorderedWires.toList(),
    );
    return order;
  }
}
