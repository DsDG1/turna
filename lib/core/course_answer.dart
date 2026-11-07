import 'package:turna/core/turkish_text.dart';

const String _ignoredPunctuation = '.,!?;:\\"\'’‘“”«»()[]{}…—–-';

String normalizeCourseAnswer(String value) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in foldTurkish(value.trim()).runes) {
    final char = String.fromCharCode(rune);
    if (_ignoredPunctuation.contains(char)) continue;
    if (RegExp(r'\s').hasMatch(char)) {
      pendingSpace = buffer.isNotEmpty;
      continue;
    }
    if (pendingSpace) buffer.write(' ');
    buffer.write(char);
    pendingSpace = false;
  }
  return buffer.toString();
}

bool matchesCourseAnswer(
  String input,
  String canonical,
  Iterable<String> acceptedAnswers,
) {
  final normalized = normalizeCourseAnswer(input);
  if (normalized.isEmpty) return false;
  return normalizeCourseAnswer(canonical) == normalized ||
      acceptedAnswers.any(
        (answer) => normalizeCourseAnswer(answer) == normalized,
      );
}
