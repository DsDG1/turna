// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_genre.dart';
import 'package:turna/application/ai/ai_json_text.dart';
import 'package:turna/application/ai/ai_resource_consistency.dart';

/// Pure helpers for AI JSON replies.
///
/// Phase 4.4 + 2.4: every network method on the original `AiCourseService`
/// has been migrated to live directly on the providers / engine. What
/// remains here is stateless parsing + normalization + the genre hook:
///   - [parseCompletion]        — wraps `jsonDecode`, runs code-fence stripping,
///     resource normalization, autoFix and self-consistency, then returns the
///     normalized [AiGeneratedCourse]. Used by importers and tests; the practice
///     pipeline decodes per phase (outline/lesson) instead of a whole chat body.
///   - [extractAssistantText]   — extracts the assistant's reply text from an
///     OpenAI-compatible chat completion body, guarding against malformed
///     shapes. Kept for callers that hold a full completion body rather than
///     `AiEngineResult.content`.
///   - [applyGenreToSpec]       — if genre batch is on, update the spec
///     template based on the detected genre tag.
class AiCourseService {
  const AiCourseService();

  /// Extract the assistant's reply text from an OpenAI-compatible chat
  /// completion response body. Guards against malformed shapes (missing
  /// `choices`, a null `message`, or `content` that is not a plain string
  /// — e.g. a multimodal array or a rate-limit payload) by throwing a
  /// user-facing error instead of a raw `TypeError`.
  ///
  /// Kept here so the parsing logic stays in one place — the engine mirrors
  /// it internally for streaming paths but the providers always use this.
  String extractAssistantText(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('AI response choices is empty.');
    }
    // Check `is Map` rather than `as Map?` so a malformed first element that
    // is neither null nor a Map (e.g. `{"choices":[42]}`) throws the friendly
    // error below instead of a raw `TypeError` at the cast.
    final first = choices.first;
    if (first is! Map) {
      throw Exception('AI response message is empty or malformed.');
    }
    final message = first['message'];
    if (message is! Map) {
      throw Exception('AI response message is empty or malformed.');
    }
    final content = message['content'];
    if (content is! String) {
      throw Exception('AI response content is empty or malformed.');
    }
    return content.trim();
  }

  /// Parse an OpenAI-compatible chat completion response body into the
  /// decoded course JSON dict. Runs resource normalization, auto-fix and
  /// self-consistency checks. Accepts either an already-decoded body map
  /// (the engine path) or a raw JSON string (legacy / shim callers).
  AiGeneratedCourse parseCompletion(dynamic body) {
    Map<String, dynamic> decoded;
    if (body is Map<String, dynamic>) {
      decoded = body;
    } else if (body is String) {
      try {
        decoded = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Could not parse AI response JSON: $e');
      }
    } else {
      throw Exception('Could not parse AI response: unexpected type');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('AI response choices is empty.');
    }
    final message = (choices.first as Map)['message'] as Map;
    final content = (message['content'] as String?) ?? '';
    final cleaned = _stripCodeFences(content.trim());
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw Exception(
          'Could not parse model JSON output: $e\nFirst 200 chars: ${cleaned.substring(0, cleaned.length < 200 ? cleaned.length : 200)}');
    }
    if (parsed['units'] is! List) {
      throw Exception("Model output is missing the top-level 'units' array.");
    }
    normalizeResources(parsed);
    autoFixResources(parsed);
    checkResourceSelfConsistency(parsed);
    return AiGeneratedCourse(rawJson: cleaned, parsed: parsed);
  }

  /// If a genre tag is present and batch mode is on, update the spec template.
  AiCourseSpec applyGenreToSpec(AiCourseSpec spec) {
    if (!spec.useGenreBatch) return spec;
    final tag = detectGenreFromSpec(
      topic: spec.topic,
      extraInstructions: spec.extraInstructions,
    );
    if (tag != null) {
      return spec.copyWith(template: genreToTemplate(tag));
    }
    return spec;
  }

  /// Delegates to [AiJsonText]. This used to be one of four private copies of
  /// the fence-stripping logic, each handling ```` ```json ```` slightly
  /// differently.
  String _stripCodeFences(String s) => AiJsonText.stripCodeFences(s);
}
