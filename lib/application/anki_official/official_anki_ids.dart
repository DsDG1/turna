import 'dart:math';

final Random _secure = Random.secure();

/// 128-bit UUID v4. Do not use millisecond + hash prefixes as IDs.
String newOfficialAnkiId(String prefix) {
  final bytes = List<int>.generate(16, (_) => _secure.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-$hex';
}

/// Legacy Anki identifier helpers for parsing importId and prefixes without depending on Legacy assembler.
abstract class LegacyAnkiIdentifiers {
  static const String ankiPrefix = 'anki-';

  static String importIdFromWordId(String wordId) {
    final cIdx = wordId.lastIndexOf('-c');
    if (cIdx > 5) {
      return wordId.substring(5, cIdx);
    }
    return '';
  }

  static String importIdFromSectionId(String sectionId) {
    if (sectionId.startsWith('official-anki-')) {
      final sIdx = sectionId.lastIndexOf('-s');
      if (sIdx > 14) {
        return sectionId.substring(14, sIdx);
      }
      return sectionId.substring(14);
    }
    final sIdx = sectionId.lastIndexOf('-s');
    if (sIdx > 5) {
      return sectionId.substring(5, sIdx);
    }
    return '';
  }
}

