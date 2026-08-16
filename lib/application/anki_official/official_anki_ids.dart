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
