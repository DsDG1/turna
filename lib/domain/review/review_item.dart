import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_capabilities.dart';
import 'package:turna/domain/review/review_source.dart';

/// Key used by the ledger to locate and update scheduling state.
class ReviewSchedulingKey {
  final String rawId;
  final ReviewSource source;

  const ReviewSchedulingKey({
    required this.rawId,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewSchedulingKey &&
          runtimeType == other.runtimeType &&
          rawId == other.rawId &&
          source == other.source;

  @override
  int get hashCode => rawId.hashCode ^ source.hashCode;

  @override
  String toString() => 'ReviewSchedulingKey($rawId, source: $source)';
}

/// Content payload rendered inside the card body.
sealed class ReviewContentBodyData {
  const ReviewContentBodyData();
}

/// Standard Flutter-rendered course card content.
class StandardCourseCardContent extends ReviewContentBodyData {
  final String frontText;
  final String? frontPronunciation;
  final String? audioPath;
  final String backText;
  final String? backNote;
  final String? explanation;
  final String? lessonName;
  final Interaction? interaction;

  const StandardCourseCardContent({
    required this.frontText,
    this.frontPronunciation,
    this.audioPath,
    required this.backText,
    this.backNote,
    this.explanation,
    this.lessonName,
    this.interaction,
  });
}

/// Original template Anki card content rendered via WebView.
class OfficialTemplateContent extends ReviewContentBodyData {
  final String frontHtml;
  final String backHtml;
  final String? css;
  final String? mediaBasePath;
  final String? answerToken;

  const OfficialTemplateContent({
    required this.frontHtml,
    required this.backHtml,
    this.css,
    this.mediaBasePath,
    this.answerToken,
  });
}

/// Unified review item presented in a review session.
class ReviewItem {
  final String sessionItemId;
  final ReviewSource source;
  final ReviewContentBodyData content;
  final ReviewCapabilities capabilities;
  final ReviewSchedulingKey schedulingKey;

  const ReviewItem({
    required this.sessionItemId,
    required this.source,
    required this.content,
    required this.capabilities,
    required this.schedulingKey,
  });
}
