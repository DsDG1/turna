// Dart imports:
import 'dart:math';

Map<String, String> flattenLanguage(
    Map<String, Map<String, String>> nestedMap) {
  final flatMap = <String, String>{};

  nestedMap.forEach((category, items) {
    flatMap.addAll(items);
  });

  return flatMap;
}

Map<K, V> shuffleMap<K, V>(Map<K, V> inputMap) {
  final entries = inputMap.entries.toList();

  final random = Random();
  entries.shuffle(random);

  return Map.fromEntries(entries);
}

String getFormattedTime(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return "$minutes:$seconds";
}
