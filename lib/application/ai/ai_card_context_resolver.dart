// Project imports:
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_source.dart';

/// Media reference that may travel into an AI prompt: kind + readable label
/// only — never raw bytes, absolute paths or URLs (Plan 3 §20.1 rule 4).
class AiMediaDescriptor {
  const AiMediaDescriptor({required this.kind, this.label});

  /// 'image' | 'audio'.
  final String kind;
  final String? label;
}

/// Unified, reveal-constrained context for AI card features (Plan 3 §20.1).
///
/// Built by [AiCardContextResolver.resolve] from a [ReviewItem]:
///   * question/answer are *plain text* — HTML, script/style blocks, tags and
///     file paths never enter the model request;
///   * [answerPlainText] is null unless the card was already revealed
///     (§20.3): the assistant must not leak the answer pre-reveal;
///   * when plaintext cannot be produced reliably, [supported] is false and
///     the UI must show "此卡片暂不支持 AI 解释" instead of sending raw ids.
class AiCardContext {
  const AiCardContext({
    required this.schemaVersion,
    required this.source,
    required this.cardId,
    required this.presentationKind,
    required this.questionPlainText,
    this.answerPlainText,
    this.noteTypeSignature,
    this.recognitionConfidence,
    this.tags = const [],
    this.language,
    required this.answerRevealed,
    this.media = const [],
    this.warnings = const [],
    this.supported = true,
  });

  static const int kSchemaVersion = 1;

  final int schemaVersion;
  final LearningSourceRef source;
  final String cardId;
  final String presentationKind;

  final String questionPlainText;
  final String? answerPlainText;

  final String? noteTypeSignature;
  final double? recognitionConfidence;
  final List<String> tags;
  final String? language;

  final bool answerRevealed;
  final List<AiMediaDescriptor> media;
  final List<String> warnings;
  final bool supported;

  /// Prompt-facing digest: includes everything EXCEPT the answer when it is
  /// not revealed. Never includes raw HTML, ids-only fallbacks or paths.
  String toPromptBlock() {
    if (!supported) return '(card content unavailable for AI)';
    final buf = StringBuffer()
      ..writeln('Card (kind: $presentationKind):')
      ..writeln(questionPlainText);
    final answer = answerPlainText;
    if (answer != null && answer.isNotEmpty) {
      buf.writeln('Answer (revealed by the learner): $answer');
    }
    for (final w in warnings) {
      buf.writeln('Warning: $w');
    }
    return buf.toString();
  }
}

/// Maps [ReviewSource] onto the stable [LearningSourceKind] identity.
LearningSourceRef _sourceRef(ReviewItem item) {
  final source = item.source;
  if (source is TurnaCourseSource) {
    return LearningSourceRef(
      kind: LearningSourceKind.course,
      sourceId: source.lessonId ?? source.sectionId ?? 'course',
      displayName: '课程',
    );
  }
  if (source is LegacyAnkiSource) {
    return LearningSourceRef(
      kind: LearningSourceKind.ankiLegacy,
      sourceId: source.importId,
      displayName: 'Anki',
    );
  }
  if (source is OfficialAnkiSource) {
    return LearningSourceRef(
      kind: LearningSourceKind.ankiOfficial,
      sourceId: source.sourceId,
      displayName: 'Anki (Official)',
    );
  }
  // Grammar reviews ride the course SRS queue today; keep a distinct label.
  return const LearningSourceRef(
    kind: LearningSourceKind.grammar,
    sourceId: 'grammar',
    displayName: '语法',
  );
}

/// Produces the [AiCardContext] for the currently reviewed card.
///
/// Safety rules (Plan 3 §20.1):
///  1. Context is built here at the review-assembly layer — the AI layer
///     never grabs DOM/WebView content.
///  2. Official template cards are reduced to sanitized plaintext from their
///     HTML fields; a raw scheduling id is NEVER used as the "term".
///  3. Raw HTML/JS/CSS, absolute media paths and DB ids stay out.
///  5. [answerPlainText] is null until [answerRevealed] is true.
///  8. When reliable plaintext can't be produced, [AiCardContext.supported]
///     is false and callers must not send anything.
class AiCardContextResolver {
  const AiCardContextResolver();

  static const int _maxPlainTextLength = 4000;

  AiCardContext resolve(
    ReviewItem item, {
    required bool answerRevealed,
    String? language,
  }) {
    final source = _sourceRef(item);
    final content = item.content;

    String question;
    String? answer;
    String presentationKind;
    List<AiMediaDescriptor> media = const [];
    final warnings = <String>[];

    if (content is StandardCourseCardContent) {
      presentationKind = 'standard';
      question = content.frontText;
      answer = content.backText;
      // Legacy Anki cards surface as StandardCourseCardContent with an
      // AnkiCard/AnkiHtmlCard interaction: prefer the adapted plain fields
      // (never the scheduling id).
      final interaction = content.interaction;
      if (interaction is AnkiCard) {
        presentationKind = 'ankiLegacy';
        if (interaction.front.trim().isNotEmpty) {
          question = _plainText(interaction.front);
          answer = _plainText(interaction.back);
        }
        media = [
          if (interaction.audioAssets.isNotEmpty)
            const AiMediaDescriptor(kind: 'audio'),
          if (interaction.imageAssets.isNotEmpty)
            const AiMediaDescriptor(kind: 'image'),
        ];
      } else if (interaction is AnkiHtmlCard) {
        presentationKind = 'ankiLegacyHtml';
        question = _plainText(interaction.frontHtml);
        answer = _plainText(interaction.backHtml);
      }
    } else if (content is OfficialTemplateContent) {
      presentationKind = 'officialTemplate';
      question = _plainText(content.frontHtml);
      answer = _plainText(content.backHtml);
      if (content.mediaBasePath != null) {
        // Path itself never travels; note that media exists.
        warnings.add('card contains media; only labels are shared');
      }
      if (question.trim().isEmpty) {
        warnings.add('front plaintext extraction was empty');
      }
    } else {
      return AiCardContext(
        schemaVersion: AiCardContext.kSchemaVersion,
        source: source,
        cardId: item.schedulingKey.rawId,
        presentationKind: 'unsupported',
        questionPlainText: '',
        answerRevealed: answerRevealed,
        language: language,
        supported: false,
        warnings: const ['card content type is not AI-explainable'],
      );
    }

    final sanitizedQuestion = _clamp(question);
    if (sanitizedQuestion.trim().isEmpty) {
      return AiCardContext(
        schemaVersion: AiCardContext.kSchemaVersion,
        source: source,
        cardId: item.schedulingKey.rawId,
        presentationKind: presentationKind,
        questionPlainText: '',
        answerRevealed: answerRevealed,
        language: language,
        supported: false,
        warnings: warnings,
      );
    }

    return AiCardContext(
      schemaVersion: AiCardContext.kSchemaVersion,
      source: source,
      cardId: item.schedulingKey.rawId,
      presentationKind: presentationKind,
      questionPlainText: sanitizedQuestion,
      // §20.3: the answer enters the prompt only after reveal.
      answerPlainText: answerRevealed ? _clamp(answer) : null,
      language: language,
      answerRevealed: answerRevealed,
      media: media,
      warnings: warnings,
    );
  }

  /// HTML → safe plaintext: drop script/style blocks entirely, strip all
  /// tags, drop `{{…}}` template directives, decode common entities and trim.
  static String _plainText(String raw) {
    var text = raw;
    // Remove script/style blocks with their content.
    text = text.replaceAll(
      RegExp(r'<(script|style)\b[^>]*>.*?</\1>',
          caseSensitive: false, dotAll: true),
      '',
    );
    // Drop template directives (cloze markers render their answer inline
    // only when that field is the intended question).
    text = text.replaceAll(RegExp(r'\{\{[^}]*\}\}'), '');
    // Strip all remaining tags (with attributes — paths/URLs live there).
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    // Decode the small set of entities we can encounter in card fields.
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    // Collapse whitespace runs introduced by tag removal.
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  static String _clamp(String? text) {
    if (text == null) return '';
    if (text.length <= _maxPlainTextLength) return text;
    return '${text.substring(0, _maxPlainTextLength)}…';
  }
}
