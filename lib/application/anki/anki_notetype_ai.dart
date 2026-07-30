// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:varnamala/application/ai/engine/ai_engine.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/di/injection.dart';

/// Uses LLM to intelligently identify how an Anki notetype should map
/// to Varnamala card types. Falls back to heuristic on failure.
///
/// Routes through [AiEngine.chat] with a system/user message pair (same
/// pattern as KnowledgePrompt.buildExtractionMessages).
class AnkiNotetypeAI {
  final AiEngine _engine;

  AnkiNotetypeAI({AiEngine? engine}) : _engine = engine ?? getIt<AiEngine>();

  static const _systemPrompt = '''
You are an Anki deck analysis assistant. Given an Anki notetype's field definitions (field name list), determine which Varnamala card type it best maps to:

1. `ankiCard` — Generic flip card (for non-language content, or when fields are ambiguous)
2. `wordEntry` — Vocabulary card (front is a word/term, back is definition/translation, can generate multiple-choice questions)
3. `expression` — Sentence/expression card (can generate fill-in-the-blank exercises)
4. `cloze` — Cloze deletion card (Anki Cloze format with {{c1::}} markers)

Respond with ONLY a JSON object (no markdown fences):
{"mapping": "<type>", "frontField": "<field name for front>", "backField": "<field name for back>", "reason": "<brief explanation>"}

Rules:
- If field names contain "Cloze" or the notetype is marked as Cloze type, use "cloze"
- If fields look like Term/Word/Front + Translation/Meaning/Back, use "wordEntry"
- If fields look like Sentence/Expression/Example + Meaning/Translation, use "expression"
- Otherwise default to "ankiCard"
- frontField and backField must be exact field names from the provided list
''';

  /// Identify the best mapping for a notetype using LLM.
  ///
  /// Returns the AI-identified mapping, or falls back to heuristic
  /// if the LLM call fails.
  Future<NotetypeMapping> identify({
    required AiEngineConfig config,
    required AnkiNotetype notetype,
  }) async {
    if (!config.isComplete) {
      // No AI configured — use heuristic
      return AnkiCardAdapter.inferMapping(notetype);
    }

    try {
      final userMessage = _buildUserMessage(notetype);
      final result = await _engine.chat(
        config: config,
        messages: [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        temperature: 0.2,
        timeout: const Duration(seconds: 30),
      );

      return _parseReply(result.content, notetype);
    } catch (e) {
      logger.w('AnkiNotetypeAI LLM failed, falling back to heuristic: $e');
      return AnkiCardAdapter.inferMapping(notetype);
    }
  }

  /// Batch-identify all notetypes in a collection.
  Future<Map<int, NotetypeMapping>> identifyAll({
    required AiEngineConfig config,
    required Map<int, AnkiNotetype> notetypes,
  }) async {
    final result = <int, NotetypeMapping>{};
    for (final entry in notetypes.entries) {
      result[entry.key] = await identify(
        config: config,
        notetype: entry.value,
      );
    }
    return result;
  }

  String _buildUserMessage(AnkiNotetype notetype) {
    final buffer = StringBuffer();
    buffer.writeln('Notetype name: ${notetype.name}');
    buffer.writeln('Is Cloze type: ${notetype.isCloze}');
    buffer.writeln('Fields: ${notetype.fieldNames.join(', ')}');
    if (notetype.templateNames.isNotEmpty) {
      buffer.writeln('Templates: ${notetype.templateNames.join(', ')}');
    }
    return buffer.toString();
  }

  NotetypeMapping _parseReply(String reply, AnkiNotetype notetype) {
    try {
      // Strip potential markdown fences
      var cleaned = reply.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceAll(RegExp(r'^```\w*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '')
            .trim();
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      final mappingStr = json['mapping']?.toString() ?? 'ankiCard';
      final frontField = json['frontField']?.toString() ?? '';
      final backField = json['backField']?.toString() ?? '';
      final reason = json['reason']?.toString() ?? '';

      final type = _parseMappingType(mappingStr);

      // Resolve field indices from names
      final frontIdx = notetype.fieldNames.indexOf(frontField);
      final backIdx = notetype.fieldNames.indexOf(backField);

      return NotetypeMapping(
        type: type,
        frontFieldIndex: frontIdx >= 0 ? frontIdx : 0,
        backFieldIndex: backIdx >= 0
            ? backIdx
            : (frontIdx == 0 && notetype.fieldNames.length > 1 ? 1 : 0),
        reason: reason,
      );
    } catch (e) {
      logger.w('AnkiNotetypeAI parse failed: $e, using heuristic');
      return AnkiCardAdapter.inferMapping(notetype);
    }
  }

  NotetypeMappingType _parseMappingType(String raw) {
    switch (raw.toLowerCase()) {
      case 'wordentry':
      case 'word_entry':
      case 'word':
        return NotetypeMappingType.wordEntry;
      case 'expression':
      case 'sentence':
        return NotetypeMappingType.expression;
      case 'cloze':
        return NotetypeMappingType.cloze;
      default:
        return NotetypeMappingType.ankiCard;
    }
  }
}
