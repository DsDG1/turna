// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guide_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GuidePage _$GuidePageFromJson(Map<String, dynamic> json) => _GuidePage(
      id: json['id'] as String,
      title: json['title'] as String,
      kicker: json['kicker'] as String? ?? '',
      intro: json['intro'] as String? ?? '',
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((e) => GuideBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GuideBlock>[],
      nextLabel: json['nextLabel'] as String?,
      nextLessonId: json['nextLessonId'] as String?,
      nextSubLessonId: json['nextSubLessonId'] as String?,
    );

Map<String, dynamic> _$GuidePageToJson(_GuidePage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'kicker': instance.kicker,
      'intro': instance.intro,
      'blocks': instance.blocks,
      'nextLabel': instance.nextLabel,
      'nextLessonId': instance.nextLessonId,
      'nextSubLessonId': instance.nextSubLessonId,
    };

_GuideTerm _$GuideTermFromJson(Map<String, dynamic> json) => _GuideTerm(
      text: json['text'] as String,
      translation: json['translation'] as String? ?? '',
      note: json['note'] as String? ?? '',
      speechText: json['speechText'] as String?,
      wordId: json['wordId'] as String?,
    );

Map<String, dynamic> _$GuideTermToJson(_GuideTerm instance) =>
    <String, dynamic>{
      'text': instance.text,
      'translation': instance.translation,
      'note': instance.note,
      'speechText': instance.speechText,
      'wordId': instance.wordId,
    };

_GuideClassificationCategory _$GuideClassificationCategoryFromJson(
        Map<String, dynamic> json) =>
    _GuideClassificationCategory(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String? ?? '',
    );

Map<String, dynamic> _$GuideClassificationCategoryToJson(
        _GuideClassificationCategory instance) =>
    <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'description': instance.description,
    };

_GuideClassificationCard _$GuideClassificationCardFromJson(
        Map<String, dynamic> json) =>
    _GuideClassificationCard(
      id: json['id'] as String,
      text: json['text'] as String,
      categoryId: json['categoryId'] as String,
      hint: json['hint'] as String? ?? '',
      highlight: json['highlight'] as String? ?? '',
    );

Map<String, dynamic> _$GuideClassificationCardToJson(
        _GuideClassificationCard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'categoryId': instance.categoryId,
      'hint': instance.hint,
      'highlight': instance.highlight,
    };

_GuideSuffixStep _$GuideSuffixStepFromJson(Map<String, dynamic> json) =>
    _GuideSuffixStep(
      suffix: json['suffix'] as String,
      result: json['result'] as String,
      meaning: json['meaning'] as String,
    );

Map<String, dynamic> _$GuideSuffixStepToJson(_GuideSuffixStep instance) =>
    <String, dynamic>{
      'suffix': instance.suffix,
      'result': instance.result,
      'meaning': instance.meaning,
    };

_GuideSuffixExample _$GuideSuffixExampleFromJson(Map<String, dynamic> json) =>
    _GuideSuffixExample(
      id: json['id'] as String,
      root: json['root'] as String,
      rootMeaning: json['rootMeaning'] as String,
      label: json['label'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>?)
              ?.map((e) => GuideSuffixStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GuideSuffixStep>[],
    );

Map<String, dynamic> _$GuideSuffixExampleToJson(_GuideSuffixExample instance) =>
    <String, dynamic>{
      'id': instance.id,
      'root': instance.root,
      'rootMeaning': instance.rootMeaning,
      'label': instance.label,
      'steps': instance.steps,
    };

_GuideSentenceToken _$GuideSentenceTokenFromJson(Map<String, dynamic> json) =>
    _GuideSentenceToken(
      id: json['id'] as String,
      text: json['text'] as String,
      role: json['role'] as String,
      meaning: json['meaning'] as String,
      optional: json['optional'] as bool? ?? false,
    );

Map<String, dynamic> _$GuideSentenceTokenToJson(_GuideSentenceToken instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'role': instance.role,
      'meaning': instance.meaning,
      'optional': instance.optional,
    };

GuideTextBlock _$GuideTextBlockFromJson(Map<String, dynamic> json) =>
    GuideTextBlock(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      body: json['body'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$GuideTextBlockToJson(GuideTextBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'body': instance.body,
      'runtimeType': instance.$type,
    };

GuideTermsBlock _$GuideTermsBlockFromJson(Map<String, dynamic> json) =>
    GuideTermsBlock(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      compact: json['compact'] as bool? ?? false,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => GuideTerm.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GuideTerm>[],
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$GuideTermsBlockToJson(GuideTermsBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'compact': instance.compact,
      'items': instance.items,
      'runtimeType': instance.$type,
    };

GuideClassificationBlock _$GuideClassificationBlockFromJson(
        Map<String, dynamic> json) =>
    GuideClassificationBlock(
      id: json['id'] as String? ?? '',
      title: json['title'] as String,
      instruction: json['instruction'] as String? ?? '',
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => GuideClassificationCategory.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          const <GuideClassificationCategory>[],
      cards: (json['cards'] as List<dynamic>?)
              ?.map((e) =>
                  GuideClassificationCard.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GuideClassificationCard>[],
      completionNote: json['completionNote'] as String? ?? '',
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$GuideClassificationBlockToJson(
        GuideClassificationBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'instruction': instance.instruction,
      'categories': instance.categories,
      'cards': instance.cards,
      'completionNote': instance.completionNote,
      'runtimeType': instance.$type,
    };

GuideSuffixBuilderBlock _$GuideSuffixBuilderBlockFromJson(
        Map<String, dynamic> json) =>
    GuideSuffixBuilderBlock(
      id: json['id'] as String? ?? '',
      title: json['title'] as String,
      instruction: json['instruction'] as String? ?? '',
      examples: (json['examples'] as List<dynamic>?)
              ?.map(
                  (e) => GuideSuffixExample.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GuideSuffixExample>[],
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$GuideSuffixBuilderBlockToJson(
        GuideSuffixBuilderBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'instruction': instance.instruction,
      'examples': instance.examples,
      'runtimeType': instance.$type,
    };

GuideWordOrderBlock _$GuideWordOrderBlockFromJson(Map<String, dynamic> json) =>
    GuideWordOrderBlock(
      id: json['id'] as String? ?? '',
      title: json['title'] as String,
      translation: json['translation'] as String? ?? '',
      tokens: (json['tokens'] as List<dynamic>?)
              ?.map(
                  (e) => GuideSentenceToken.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GuideSentenceToken>[],
      optionalToggleLabel: json['optionalToggleLabel'] as String? ?? '',
      note: json['note'] as String? ?? '',
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$GuideWordOrderBlockToJson(
        GuideWordOrderBlock instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'translation': instance.translation,
      'tokens': instance.tokens,
      'optionalToggleLabel': instance.optionalToggleLabel,
      'note': instance.note,
      'runtimeType': instance.$type,
    };
