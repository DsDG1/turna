/// Pedagogy, CEFR, distractor, and language-specific guidance blocks for
/// in-app AI course generation.
///
/// Ported from `tool/gui/src/backend/ai_pedagogy.py` so the in-app generator
/// produces natural, sentence-driven drills instead of isolated word-gloss
/// quizzes or malformed distractors.
abstract final class AiPracticePedagogy {
  static String normalizeLevel(String level) {
    final upper = level.trim().toUpperCase();
    if (upper.startsWith('C2')) return 'C2';
    if (upper.startsWith('C1')) return 'C1';
    if (upper.startsWith('B2')) return 'B2';
    if (upper.startsWith('B1')) return 'B1';
    if (upper.startsWith('A2')) return 'A2';
    return 'A1';
  }

  static String levelGuideBlock(String level) {
    final normalized = normalizeLevel(level);
    return switch (normalized) {
      'A1' => 'CEFR A1 constraints:\n'
          '- New words per lesson: 4-8.\n'
          '- Sentences: 2-8 words, everyday concrete situations and short '
          'two-turn exchanges; put new words into sentences immediately.\n'
          '- Focus: interleave showWord with contextual fillBlank, '
          'reorderSentence, and short translateSentence; minimize isolated '
          'single-word gloss MCQs.',
      'A2' => 'CEFR A2 constraints:\n'
          '- New words per lesson: 6-12.\n'
          '- Sentences: 5-12 words, simple compound clauses and common tense '
          'contrasts.\n'
          '- Focus: contextual fillBlank, reorderSentence, situational '
          'translateSentence, and short dialogue/reading.',
      'B1' => 'CEFR B1 constraints:\n'
          '- New words per lesson: 8-15.\n'
          '- Sentences: medium-length with reason/condition/time clauses.\n'
          '- Focus: reading comprehension, multiSelect nuance checks, and '
          'situational translateSentence.',
      'B2' => 'CEFR B2 constraints:\n'
          '- New words per lesson: 10-18.\n'
          '- Sentences: longer connected discourse, abstract topics, register '
          'and tone contrasts.\n'
          '- Focus: inference reading, nuanced multiSelect, and precision '
          'production.',
      'C1' => 'CEFR C1 constraints:\n'
          '- New words per lesson: 10-18 idioms, collocations, or formal '
          'structures.\n'
          '- Sentences: complex subordination, nuanced register, pragmatic '
          'implicature.\n'
          '- Focus: authentic reading analysis, fine-grained synonym/register '
          'contrasts, and idiomatic translation.',
      _ => 'CEFR C2 constraints:\n'
          '- New words per lesson: 10-18 advanced idioms, stylistic variants, '
          'or rhetorical devices.\n'
          '- Sentences: near-native nuance, irony/tone, domain-specific prose.\n'
          '- Focus: deep reading inference and stylistic precision.',
    };
  }

  static String templateGradientBlock(String template) {
    return switch (template.trim()) {
      'intro' => 'Template gradient (intro): introduce words with showWord '
          'first, then immediately put each new word into contextual '
          'fillBlank / reorderSentence / short translateSentence. Never emit '
          'pseudo-blanks like "word = ____".',
      'practice' => 'Template gradient (practice): prioritize sentence-level '
          'production (contextual fillBlank, reorderSentence, '
          'translateSentence) over isolated word-meaning MCQs.',
      'review' => 'Template gradient (review): recycle and contrast target '
          'items in varied sentences; avoid repeating identical stems or '
          'pseudo-blanks.',
      'reading' => 'Template gradient (reading): write a coherent passage '
          'with 2-5 natural paragraphs, then follow with readingMcq, '
          'readingTrueFalse, and readingShortAnswer grounded directly in the '
          'passage.',
      'dialogue' => 'Template gradient (dialogue): build a realistic 2-3 '
          'character scene where partner lines alternate with learner response '
          'interactions; every learner turn must link via interactionId to an '
          'item in stages.',
      'guide' => 'Template gradient (guide): ungraded explanation pages only '
          '(no stages/items). Combine concise text blocks with terms, '
          'classification, or wordOrder blocks.',
      'mastery' => 'Template gradient (mastery): single-stage comprehensive '
          'quiz mixing recognition and production across the unit core items.',
      _ => 'Template gradient (mixed): arrange lessons inside each unit along '
          'a sensible progression such as intro -> practice -> reading/dialogue '
          '-> mastery (or guide -> practice -> mastery).',
    };
  }

  static String distractorRulesBlock() => 'Distractor & answerability rules:\n'
      '1. multipleChoice / readingMcq: provide 4 unique options with exactly '
      'ONE unambiguous correct answer; correctIndex must be 0..3.\n'
      '2. Distractors must match the correct option in part of speech, '
      'language, and approximate length — prefer plausible near-synonyms or '
      'topic-related words, never gibberish or placeholders.\n'
      '3. Substitute every option into the stem mentally: only the keyed '
      'answer may fit grammatically and contextually ("all 3 could work" is a '
      'defect).\n'
      '4. fillBlank: sentence must contain a single ____ blank; answer must '
      'fit that blank cleanly without ambiguous synonyms unless listed.\n'
      '5. reorderSentence: scrambled and correct must contain the exact same '
      'multiset of tokens, with scrambled actually shuffled.';

  static String languagePackBlock(String language) {
    final key = language.trim().toLowerCase();
    if (key == 'turkish' ||
        key == 'tr' ||
        key == 'türkçe' ||
        key == 'turkce' ||
        key.contains('土耳其')) {
      return 'Target-language pack (Turkish):\n'
          '1. Preserve accurate Turkish orthography and capitalization '
          '(ç, ğ, ı, İ, ö, ş, ü; e.g. Merhaba, Teşekkürler, İstanbul).\n'
          '2. Respect vowel harmony and consonant mutation on every suffix.\n'
          '3. Keep register consistent (sen vs siz) and indicate polite '
          'context in the prompt when siz is required.\n'
          '4. Do not invent broken vowel-harmony spellings as the sole '
          'distractor strategy.';
    }
    return 'Target-language pack ($language):\n'
        '1. Every word.term and target sentence must be natural, idiomatic '
        '$language with accurate orthography/diacritics.\n'
        '2. Translations and prompts must use the requested source language.\n'
        '3. Never leave empty translations or placeholder text.';
  }

  /// Combined pedagogy block for outline or lesson fill prompts.
  static String fullBlock({
    required String level,
    required String language,
    required String template,
  }) {
    return [
      '## Pedagogy & Quality Guidelines',
      levelGuideBlock(level),
      '',
      templateGradientBlock(template),
      '',
      distractorRulesBlock(),
      '',
      languagePackBlock(language),
    ].join('\n');
  }
}
