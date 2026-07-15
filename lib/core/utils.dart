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

/// Resolve an enum value from its [Enum.name] string without throwing.
///
/// Returns the matching value, or [fallback] when [name] is unknown (a
/// forward-incompatible content version, a manual DB edit, …). Centralizes
/// the safe `byName`-with-fallback pattern so the JSON load path and the
/// SQLite read path share one source of truth for the default rather than
/// hand-rolled loops per enum. Callers pass the expected fallback explicitly
/// (e.g. `LessonType.normal`) so the default is visible at the call site.
T enumByName<T extends Enum>(List<T> values, String name, {required T fallback}) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
