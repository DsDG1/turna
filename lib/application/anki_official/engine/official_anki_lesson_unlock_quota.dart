import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';

/// Option A (ADR 0037): on first-pass lesson complete, raise today's
/// remaining Official new-card quota so it covers this lesson's cards.
/// Uses `extend_new` (never a permanent `new_per_day` change). Fail-closed.
class OfficialAnkiLessonUnlockQuota {
  const OfficialAnkiLessonUnlockQuota({this.engine});

  final OfficialAnkiEngine? engine;

  static OfficialAnkiLessonUnlockQuota? debugOverride;

  static OfficialAnkiLessonUnlockQuota resolve() =>
      debugOverride ?? const OfficialAnkiLessonUnlockQuota();

  static const _descriptorBatch = 200;

  Future<int> ensureForCardIds(Iterable<int> cardIds) async {
    final unique = {for (final id in cardIds) if (id > 0) id};
    if (unique.isEmpty) return 0;
    try {
      final resolved = engine ?? OfficialAnkiCompositionRoot.engine;
      if (resolved == null) return 0;
      final byDeck = <int, int>{};
      final list = unique.toList();
      for (var i = 0; i < list.length; i += _descriptorBatch) {
        final end = i + _descriptorBatch < list.length
            ? i + _descriptorBatch
            : list.length;
        for (final descriptor
            in await resolved.getCardDescriptorsBatch(list.sublist(i, end))) {
          if (descriptor.deckId <= 0) continue;
          byDeck[descriptor.deckId] = (byDeck[descriptor.deckId] ?? 0) + 1;
        }
      }
      var extra = 0;
      for (final entry in byDeck.entries) {
        extra += await resolved.ensureTodayNewQuota(
          deckId: entry.key,
          neededNew: entry.value,
        );
      }
      return extra;
    } catch (error) {
      debugPrint('[OfficialAnkiLessonUnlockQuota] fail-closed: $error');
      return 0;
    }
  }
}
