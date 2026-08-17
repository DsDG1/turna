import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String officialAnkiProfileKey(String profileId) {
  return sha256.convert(utf8.encode(profileId)).toString().substring(0, 12);
}

/// Stable stand-in for a top-deck id when the deck tree did not supply one.
int officialAnkiStableTopDeckId(String topDeckName) {
  final bytes = sha256.convert(utf8.encode(topDeckName)).bytes;
  return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0);
}

String officialAnkiSectionId({
  required String sourceId,
  required int topDeckId,
}) {
  return 'official-anki-$sourceId-s$topDeckId';
}

String officialAnkiSectionIdForTopDeck({
  required String sourceId,
  required String topDeckName,
  Map<String, int> topDeckIds = const <String, int>{},
}) {
  if (topDeckName.isEmpty || topDeckName == 'Recovered') {
    return officialAnkiSectionId(sourceId: sourceId, topDeckId: 0);
  }
  final id = topDeckIds[topDeckName] ?? officialAnkiStableTopDeckId(topDeckName);
  return officialAnkiSectionId(sourceId: sourceId, topDeckId: id);
}

String officialAnkiUnitId({
  required String sourceId,
  required List<String> deckPath,
}) {
  final hash = sha256.convert(utf8.encode(deckPath.join('\u001f'))).toString();
  return 'official-anki-$sourceId-u${hash.substring(0, 12)}';
}

String officialAnkiLessonId({
  required String sourceId,
  required String groupKey,
  required int part,
}) {
  final hash = sha256.convert(utf8.encode(groupKey)).toString();
  return 'official-anki-$sourceId-l${hash.substring(0, 12)}-p$part';
}

String officialAnkiWordId({
  required String profileId,
  required int cardId,
}) {
  return 'official-anki-${officialAnkiProfileKey(profileId)}-c$cardId';
}

String officialAnkiItemId({
  required String wordId,
  required String projectionKind,
  required int ordinal,
}) {
  return '$wordId-p$projectionKind-$ordinal';
}

bool officialAnkiIsOwnedTreeId({
  required String sourceId,
  required String id,
}) {
  return id.startsWith('official-anki-$sourceId-');
}

String officialAnkiCanonicalWordId({
  required String sourceId,
  required int cardId,
}) {
  return 'official-anki-link-$sourceId-c$cardId';
}
