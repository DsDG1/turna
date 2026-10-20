// Dart imports:
import 'dart:convert';

/// Shared helpers for reading a model reply that is supposed to be JSON.
///
/// Every AI surface used to carry its own copy of the fence-stripping logic
/// (`hint_genres`, `ai_course_service`, `ai_practice_pipeline`,
/// `textbook_import_provider`), and the copies disagreed: one handled a
/// ```` ```json ```` info string via a regex, the others only stripped the
/// first line via `indexOf`. This file is the single implementation; the four
/// call sites now delegate here so a model that adds an info string is handled
/// the same way everywhere.
abstract final class AiJsonText {
  /// Strip a leading ```` ``` ```` / ```` ```json ```` fence and a trailing
  /// ```` ``` ```` so a model that ignored the "no fences" rule still decodes.
  ///
  /// Only a fence that wraps the *whole* reply is removed; a fence appearing
  /// mid-text is left alone (that would be prose, not an envelope).
  static String stripCodeFences(String input) {
    var text = input.trim();
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    if (firstNewline < 0) {
      // A single line like "```json" carries no content — nothing to unwrap.
      return text;
    }
    text = text.substring(firstNewline + 1).trimRight();
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }

  /// Decode a model reply into a JSON object, stripping fences first.
  ///
  /// Throws [FormatException] when the reply is not a JSON object.
  static Map<String, dynamic> decodeObject(String reply) {
    final decoded = jsonDecode(stripCodeFences(reply));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model output is not a JSON object.');
    }
    return decoded;
  }
}

/// Backwards-compatible top-level aliases for the historical helpers.
String stripCodeFences(String s) => AiJsonText.stripCodeFences(s);

/// Backwards-compatible alias of [AiJsonText.decodeObject].
Map<String, dynamic> decodeJsonObject(String reply) =>
    AiJsonText.decodeObject(reply);
