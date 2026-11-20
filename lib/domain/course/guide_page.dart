// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'guide_page.freezed.dart';
part 'guide_page.g.dart';

@freezed
abstract class GuidePage with _$GuidePage {
  const factory GuidePage({
    required String id,
    required String title,
    @Default('') String kicker,
    @Default('') String intro,
    @Default(<GuideBlock>[]) List<GuideBlock> blocks,
    String? nextLabel,
    String? nextLessonId,
    String? nextSubLessonId,
  }) = _GuidePage;

  factory GuidePage.fromJson(Map<String, dynamic> json) =>
      _$GuidePageFromJson(json);
}

@freezed
abstract class GuideTerm with _$GuideTerm {
  const factory GuideTerm({
    required String text,
    @Default('') String translation,
    @Default('') String note,
    String? speechText,
    String? wordId,
  }) = _GuideTerm;

  factory GuideTerm.fromJson(Map<String, dynamic> json) =>
      _$GuideTermFromJson(json);
}

@freezed
abstract class GuideClassificationCategory with _$GuideClassificationCategory {
  const factory GuideClassificationCategory({
    required String id,
    required String label,
    @Default('') String description,
  }) = _GuideClassificationCategory;

  factory GuideClassificationCategory.fromJson(Map<String, dynamic> json) =>
      _$GuideClassificationCategoryFromJson(json);
}

@freezed
abstract class GuideClassificationCard with _$GuideClassificationCard {
  const factory GuideClassificationCard({
    required String id,
    required String text,
    required String categoryId,
    @Default('') String hint,
    @Default('') String highlight,
  }) = _GuideClassificationCard;

  factory GuideClassificationCard.fromJson(Map<String, dynamic> json) =>
      _$GuideClassificationCardFromJson(json);
}

@freezed
abstract class GuideSuffixStep with _$GuideSuffixStep {
  const factory GuideSuffixStep({
    required String suffix,
    required String result,
    required String meaning,
  }) = _GuideSuffixStep;

  factory GuideSuffixStep.fromJson(Map<String, dynamic> json) =>
      _$GuideSuffixStepFromJson(json);
}

@freezed
abstract class GuideSuffixExample with _$GuideSuffixExample {
  const factory GuideSuffixExample({
    required String id,
    required String root,
    required String rootMeaning,
    @Default('') String label,
    @Default(<GuideSuffixStep>[]) List<GuideSuffixStep> steps,
  }) = _GuideSuffixExample;

  factory GuideSuffixExample.fromJson(Map<String, dynamic> json) =>
      _$GuideSuffixExampleFromJson(json);
}

@freezed
abstract class GuideSentenceToken with _$GuideSentenceToken {
  const factory GuideSentenceToken({
    required String id,
    required String text,
    required String role,
    required String meaning,
    @Default(false) bool optional,
  }) = _GuideSentenceToken;

  factory GuideSentenceToken.fromJson(Map<String, dynamic> json) =>
      _$GuideSentenceTokenFromJson(json);
}

@Freezed(fromJson: true, toJson: true)
sealed class GuideBlock with _$GuideBlock {
  const factory GuideBlock.text({
    @Default('') String id,
    String? title,
    required String body,
  }) = GuideTextBlock;

  const factory GuideBlock.terms({
    @Default('') String id,
    String? title,
    @Default(false) bool compact,
    @Default(<GuideTerm>[]) List<GuideTerm> items,
  }) = GuideTermsBlock;

  const factory GuideBlock.classification({
    @Default('') String id,
    required String title,
    @Default('') String instruction,
    @Default(<GuideClassificationCategory>[])
    List<GuideClassificationCategory> categories,
    @Default(<GuideClassificationCard>[]) List<GuideClassificationCard> cards,
    @Default('') String completionNote,
  }) = GuideClassificationBlock;

  const factory GuideBlock.suffixBuilder({
    @Default('') String id,
    required String title,
    @Default('') String instruction,
    @Default(<GuideSuffixExample>[]) List<GuideSuffixExample> examples,
  }) = GuideSuffixBuilderBlock;

  const factory GuideBlock.wordOrder({
    @Default('') String id,
    required String title,
    @Default('') String translation,
    @Default(<GuideSentenceToken>[]) List<GuideSentenceToken> tokens,
    @Default('') String optionalToggleLabel,
    @Default('') String note,
  }) = GuideWordOrderBlock;

  factory GuideBlock.fromJson(Map<String, dynamic> json) =>
      _$GuideBlockFromJson(json);
}
