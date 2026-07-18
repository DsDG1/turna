/// Builds the per-chapter extraction prompt. Mirrors
/// `tool/gui/src/backend/knowledge_prompt.py`.
class KnowledgePrompt {
  const KnowledgePrompt._();

  static List<Map<String, String>> buildExtractionMessages({
    required String language,
    required String sourceLanguage,
    required String chapterTitle,
    required String chapterMarkdown,
    int maxChars = 8000,
  }) {
    final truncated = _truncateAtParagraph(chapterMarkdown, maxChars);
    return [
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences.',
      },
      {
        'role': 'user',
        'content': _buildPrompt(
          language: language,
          sourceLanguage: sourceLanguage,
          chapterTitle: chapterTitle,
          chapterMarkdown: truncated,
        ),
      },
    ];
  }

  static String _buildPrompt({
    required String language,
    required String sourceLanguage,
    required String chapterTitle,
    required String chapterMarkdown,
  }) {
    return '''Extract teachable knowledge points from the following $language textbook chapter.

The chapter title is: "$chapterTitle".

Return STRICT JSON with this top-level shape:
{
  "words": [
    {
      "id": "w-chapter-slug-term",
      "term": "target-language word",
      "translation": "$sourceLanguage translation",
      "pronunciation": null,
      "audioAsset": null,
      "tags": ["tag"]
    }
  ],
  "expressions": [
    {
      "id": "e-chapter-slug-expression",
      "term": "target-language expression",
      "translation": "$sourceLanguage translation",
      "pronunciation": null,
      "audioAsset": null,
      "tags": []
    }
  ],
  "grammarPoints": [
    {
      "id": "g-chapter-slug-rule",
      "title": "Rule name",
      "explanation": "Explanation in $sourceLanguage",
      "exampleExpressionIds": [],
      "exampleSentenceIds": [],
      "practiceItems": []
    }
  ]
}

Rules:
1. Only include items that are actually taught or illustrated in the chapter.
2. term/title must be in $language; translation/explanation must be in $sourceLanguage.
3. ids are globally unique, lower kebab-case. Use a short slug derived from the chapter title as a prefix.
4. Output JSON only — no markdown fences, no prose.

Chapter content:
$chapterMarkdown
''';
  }

  static String _truncateAtParagraph(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    var cut = text.lastIndexOf('\n\n', maxChars);
    if (cut < 0) cut = text.lastIndexOf('\n', maxChars);
    if (cut < 0) cut = maxChars;
    return text.substring(0, cut).trim();
  }
}
