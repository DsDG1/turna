// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Interaction _$InteractionFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'showWord':
      return ShowWord.fromJson(json);
    case 'multipleChoice':
      return MultipleChoice.fromJson(json);
    case 'multiSelect':
      return MultiSelect.fromJson(json);
    case 'fillBlank':
      return FillBlank.fromJson(json);
    case 'translateSentence':
      return TranslateSentence.fromJson(json);
    case 'listenAndPick':
      return ListenAndPick.fromJson(json);
    case 'typeTheWord':
      return TypeTheWord.fromJson(json);
    case 'listenOnly':
      return ListenOnly.fromJson(json);
    case 'reorderSentence':
      return ReorderSentence.fromJson(json);
    case 'readingMcq':
      return ReadingMcq.fromJson(json);
    case 'readingTrueFalse':
      return ReadingTrueFalse.fromJson(json);
    case 'readingShortAnswer':
      return ReadingShortAnswer.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'Interaction',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$Interaction {
  String get id => throw _privateConstructorUsedError;
  String? get grammarPointId => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $InteractionCopyWith<Interaction> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InteractionCopyWith<$Res> {
  factory $InteractionCopyWith(
          Interaction value, $Res Function(Interaction) then) =
      _$InteractionCopyWithImpl<$Res, Interaction>;
  @useResult
  $Res call({String id, String? grammarPointId});
}

/// @nodoc
class _$InteractionCopyWithImpl<$Res, $Val extends Interaction>
    implements $InteractionCopyWith<$Res> {
  _$InteractionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ShowWordImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ShowWordImplCopyWith(
          _$ShowWordImpl value, $Res Function(_$ShowWordImpl) then) =
      __$$ShowWordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String wordId,
      String? context,
      String? grammarPointId,
      String? expressionId});
}

/// @nodoc
class __$$ShowWordImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ShowWordImpl>
    implements _$$ShowWordImplCopyWith<$Res> {
  __$$ShowWordImplCopyWithImpl(
      _$ShowWordImpl _value, $Res Function(_$ShowWordImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? wordId = null,
    Object? context = freezed,
    Object? grammarPointId = freezed,
    Object? expressionId = freezed,
  }) {
    return _then(_$ShowWordImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      wordId: null == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      context: freezed == context
          ? _value.context
          : context // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
      expressionId: freezed == expressionId
          ? _value.expressionId
          : expressionId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ShowWordImpl implements ShowWord {
  const _$ShowWordImpl(
      {this.id = '',
      required this.wordId,
      this.context,
      this.grammarPointId,
      this.expressionId,
      final String? $type})
      : $type = $type ?? 'showWord';

  factory _$ShowWordImpl.fromJson(Map<String, dynamic> json) =>
      _$$ShowWordImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String wordId;
  @override
  final String? context;
  @override
  final String? grammarPointId;
  @override
  final String? expressionId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.showWord(id: $id, wordId: $wordId, context: $context, grammarPointId: $grammarPointId, expressionId: $expressionId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ShowWordImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.context, context) || other.context == context) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId) &&
            (identical(other.expressionId, expressionId) ||
                other.expressionId == expressionId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, wordId, context, grammarPointId, expressionId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ShowWordImplCopyWith<_$ShowWordImpl> get copyWith =>
      __$$ShowWordImplCopyWithImpl<_$ShowWordImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return showWord(id, wordId, context, grammarPointId, expressionId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return showWord?.call(id, wordId, context, grammarPointId, expressionId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (showWord != null) {
      return showWord(id, wordId, context, grammarPointId, expressionId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return showWord(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return showWord?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (showWord != null) {
      return showWord(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ShowWordImplToJson(
      this,
    );
  }
}

abstract class ShowWord implements Interaction {
  const factory ShowWord(
      {final String id,
      required final String wordId,
      final String? context,
      final String? grammarPointId,
      final String? expressionId}) = _$ShowWordImpl;

  factory ShowWord.fromJson(Map<String, dynamic> json) =
      _$ShowWordImpl.fromJson;

  @override
  String get id;
  String get wordId;
  String? get context;
  @override
  String? get grammarPointId;
  String? get expressionId;
  @override
  @JsonKey(ignore: true)
  _$$ShowWordImplCopyWith<_$ShowWordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MultipleChoiceImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$MultipleChoiceImplCopyWith(_$MultipleChoiceImpl value,
          $Res Function(_$MultipleChoiceImpl) then) =
      __$$MultipleChoiceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String prompt,
      List<String> options,
      int correctIndex,
      String? imageAsset,
      String? grammarPointId});
}

/// @nodoc
class __$$MultipleChoiceImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$MultipleChoiceImpl>
    implements _$$MultipleChoiceImplCopyWith<$Res> {
  __$$MultipleChoiceImplCopyWithImpl(
      _$MultipleChoiceImpl _value, $Res Function(_$MultipleChoiceImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndex = null,
    Object? imageAsset = freezed,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$MultipleChoiceImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndex: null == correctIndex
          ? _value.correctIndex
          : correctIndex // ignore: cast_nullable_to_non_nullable
              as int,
      imageAsset: freezed == imageAsset
          ? _value.imageAsset
          : imageAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MultipleChoiceImpl implements MultipleChoice {
  const _$MultipleChoiceImpl(
      {this.id = '',
      required this.prompt,
      required final List<String> options,
      required this.correctIndex,
      this.imageAsset,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        $type = $type ?? 'multipleChoice';

  factory _$MultipleChoiceImpl.fromJson(Map<String, dynamic> json) =>
      _$$MultipleChoiceImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String prompt;
  final List<String> _options;
  @override
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  @override
  final int correctIndex;
  @override
  final String? imageAsset;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.multipleChoice(id: $id, prompt: $prompt, options: $options, correctIndex: $correctIndex, imageAsset: $imageAsset, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MultipleChoiceImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            (identical(other.correctIndex, correctIndex) ||
                other.correctIndex == correctIndex) &&
            (identical(other.imageAsset, imageAsset) ||
                other.imageAsset == imageAsset) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      prompt,
      const DeepCollectionEquality().hash(_options),
      correctIndex,
      imageAsset,
      grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MultipleChoiceImplCopyWith<_$MultipleChoiceImpl> get copyWith =>
      __$$MultipleChoiceImplCopyWithImpl<_$MultipleChoiceImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return multipleChoice(
        id, prompt, options, correctIndex, imageAsset, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return multipleChoice?.call(
        id, prompt, options, correctIndex, imageAsset, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (multipleChoice != null) {
      return multipleChoice(
          id, prompt, options, correctIndex, imageAsset, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return multipleChoice(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return multipleChoice?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (multipleChoice != null) {
      return multipleChoice(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MultipleChoiceImplToJson(
      this,
    );
  }
}

abstract class MultipleChoice implements Interaction {
  const factory MultipleChoice(
      {final String id,
      required final String prompt,
      required final List<String> options,
      required final int correctIndex,
      final String? imageAsset,
      final String? grammarPointId}) = _$MultipleChoiceImpl;

  factory MultipleChoice.fromJson(Map<String, dynamic> json) =
      _$MultipleChoiceImpl.fromJson;

  @override
  String get id;
  String get prompt;
  List<String> get options;
  int get correctIndex;
  String? get imageAsset;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$MultipleChoiceImplCopyWith<_$MultipleChoiceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MultiSelectImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$MultiSelectImplCopyWith(
          _$MultiSelectImpl value, $Res Function(_$MultiSelectImpl) then) =
      __$$MultiSelectImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String prompt,
      List<String> options,
      List<int> correctIndices,
      int minSelections,
      int maxSelections,
      String? imageAsset,
      String? grammarPointId});
}

/// @nodoc
class __$$MultiSelectImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$MultiSelectImpl>
    implements _$$MultiSelectImplCopyWith<$Res> {
  __$$MultiSelectImplCopyWithImpl(
      _$MultiSelectImpl _value, $Res Function(_$MultiSelectImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndices = null,
    Object? minSelections = null,
    Object? maxSelections = null,
    Object? imageAsset = freezed,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$MultiSelectImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndices: null == correctIndices
          ? _value._correctIndices
          : correctIndices // ignore: cast_nullable_to_non_nullable
              as List<int>,
      minSelections: null == minSelections
          ? _value.minSelections
          : minSelections // ignore: cast_nullable_to_non_nullable
              as int,
      maxSelections: null == maxSelections
          ? _value.maxSelections
          : maxSelections // ignore: cast_nullable_to_non_nullable
              as int,
      imageAsset: freezed == imageAsset
          ? _value.imageAsset
          : imageAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MultiSelectImpl implements MultiSelect {
  const _$MultiSelectImpl(
      {this.id = '',
      required this.prompt,
      required final List<String> options,
      required final List<int> correctIndices,
      this.minSelections = 1,
      this.maxSelections = 2147483647,
      this.imageAsset,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        _correctIndices = correctIndices,
        $type = $type ?? 'multiSelect';

  factory _$MultiSelectImpl.fromJson(Map<String, dynamic> json) =>
      _$$MultiSelectImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String prompt;
  final List<String> _options;
  @override
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  final List<int> _correctIndices;
  @override
  List<int> get correctIndices {
    if (_correctIndices is EqualUnmodifiableListView) return _correctIndices;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_correctIndices);
  }

  @override
  @JsonKey()
  final int minSelections;
  @override
  @JsonKey()
  final int maxSelections;
  @override
  final String? imageAsset;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.multiSelect(id: $id, prompt: $prompt, options: $options, correctIndices: $correctIndices, minSelections: $minSelections, maxSelections: $maxSelections, imageAsset: $imageAsset, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MultiSelectImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            const DeepCollectionEquality()
                .equals(other._correctIndices, _correctIndices) &&
            (identical(other.minSelections, minSelections) ||
                other.minSelections == minSelections) &&
            (identical(other.maxSelections, maxSelections) ||
                other.maxSelections == maxSelections) &&
            (identical(other.imageAsset, imageAsset) ||
                other.imageAsset == imageAsset) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      prompt,
      const DeepCollectionEquality().hash(_options),
      const DeepCollectionEquality().hash(_correctIndices),
      minSelections,
      maxSelections,
      imageAsset,
      grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MultiSelectImplCopyWith<_$MultiSelectImpl> get copyWith =>
      __$$MultiSelectImplCopyWithImpl<_$MultiSelectImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return multiSelect(id, prompt, options, correctIndices, minSelections,
        maxSelections, imageAsset, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return multiSelect?.call(id, prompt, options, correctIndices, minSelections,
        maxSelections, imageAsset, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (multiSelect != null) {
      return multiSelect(id, prompt, options, correctIndices, minSelections,
          maxSelections, imageAsset, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return multiSelect(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return multiSelect?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (multiSelect != null) {
      return multiSelect(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MultiSelectImplToJson(
      this,
    );
  }
}

abstract class MultiSelect implements Interaction {
  const factory MultiSelect(
      {final String id,
      required final String prompt,
      required final List<String> options,
      required final List<int> correctIndices,
      final int minSelections,
      final int maxSelections,
      final String? imageAsset,
      final String? grammarPointId}) = _$MultiSelectImpl;

  factory MultiSelect.fromJson(Map<String, dynamic> json) =
      _$MultiSelectImpl.fromJson;

  @override
  String get id;
  String get prompt;
  List<String> get options;
  List<int> get correctIndices;
  int get minSelections;
  int get maxSelections;
  String? get imageAsset;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$MultiSelectImplCopyWith<_$MultiSelectImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$FillBlankImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$FillBlankImplCopyWith(
          _$FillBlankImpl value, $Res Function(_$FillBlankImpl) then) =
      __$$FillBlankImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String sentence,
      String answer,
      String? hint,
      String? grammarPointId});
}

/// @nodoc
class __$$FillBlankImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$FillBlankImpl>
    implements _$$FillBlankImplCopyWith<$Res> {
  __$$FillBlankImplCopyWithImpl(
      _$FillBlankImpl _value, $Res Function(_$FillBlankImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sentence = null,
    Object? answer = null,
    Object? hint = freezed,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$FillBlankImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sentence: null == sentence
          ? _value.sentence
          : sentence // ignore: cast_nullable_to_non_nullable
              as String,
      answer: null == answer
          ? _value.answer
          : answer // ignore: cast_nullable_to_non_nullable
              as String,
      hint: freezed == hint
          ? _value.hint
          : hint // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FillBlankImpl implements FillBlank {
  const _$FillBlankImpl(
      {this.id = '',
      required this.sentence,
      required this.answer,
      this.hint,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'fillBlank';

  factory _$FillBlankImpl.fromJson(Map<String, dynamic> json) =>
      _$$FillBlankImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String sentence;
  @override
  final String answer;
  @override
  final String? hint;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.fillBlank(id: $id, sentence: $sentence, answer: $answer, hint: $hint, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FillBlankImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sentence, sentence) ||
                other.sentence == sentence) &&
            (identical(other.answer, answer) || other.answer == answer) &&
            (identical(other.hint, hint) || other.hint == hint) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, sentence, answer, hint, grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FillBlankImplCopyWith<_$FillBlankImpl> get copyWith =>
      __$$FillBlankImplCopyWithImpl<_$FillBlankImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return fillBlank(id, sentence, answer, hint, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return fillBlank?.call(id, sentence, answer, hint, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (fillBlank != null) {
      return fillBlank(id, sentence, answer, hint, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return fillBlank(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return fillBlank?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (fillBlank != null) {
      return fillBlank(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$FillBlankImplToJson(
      this,
    );
  }
}

abstract class FillBlank implements Interaction {
  const factory FillBlank(
      {final String id,
      required final String sentence,
      required final String answer,
      final String? hint,
      final String? grammarPointId}) = _$FillBlankImpl;

  factory FillBlank.fromJson(Map<String, dynamic> json) =
      _$FillBlankImpl.fromJson;

  @override
  String get id;
  String get sentence;
  String get answer;
  String? get hint;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$FillBlankImplCopyWith<_$FillBlankImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TranslateSentenceImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$TranslateSentenceImplCopyWith(_$TranslateSentenceImpl value,
          $Res Function(_$TranslateSentenceImpl) then) =
      __$$TranslateSentenceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String source,
      String expected,
      List<String> hints,
      String? grammarPointId});
}

/// @nodoc
class __$$TranslateSentenceImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$TranslateSentenceImpl>
    implements _$$TranslateSentenceImplCopyWith<$Res> {
  __$$TranslateSentenceImplCopyWithImpl(_$TranslateSentenceImpl _value,
      $Res Function(_$TranslateSentenceImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? source = null,
    Object? expected = null,
    Object? hints = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$TranslateSentenceImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      expected: null == expected
          ? _value.expected
          : expected // ignore: cast_nullable_to_non_nullable
              as String,
      hints: null == hints
          ? _value._hints
          : hints // ignore: cast_nullable_to_non_nullable
              as List<String>,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TranslateSentenceImpl implements TranslateSentence {
  const _$TranslateSentenceImpl(
      {this.id = '',
      required this.source,
      required this.expected,
      final List<String> hints = const <String>[],
      this.grammarPointId,
      final String? $type})
      : _hints = hints,
        $type = $type ?? 'translateSentence';

  factory _$TranslateSentenceImpl.fromJson(Map<String, dynamic> json) =>
      _$$TranslateSentenceImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String source;
  @override
  final String expected;
  final List<String> _hints;
  @override
  @JsonKey()
  List<String> get hints {
    if (_hints is EqualUnmodifiableListView) return _hints;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_hints);
  }

  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.translateSentence(id: $id, source: $source, expected: $expected, hints: $hints, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TranslateSentenceImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.expected, expected) ||
                other.expected == expected) &&
            const DeepCollectionEquality().equals(other._hints, _hints) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, source, expected,
      const DeepCollectionEquality().hash(_hints), grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TranslateSentenceImplCopyWith<_$TranslateSentenceImpl> get copyWith =>
      __$$TranslateSentenceImplCopyWithImpl<_$TranslateSentenceImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return translateSentence(id, source, expected, hints, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return translateSentence?.call(id, source, expected, hints, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (translateSentence != null) {
      return translateSentence(id, source, expected, hints, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return translateSentence(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return translateSentence?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (translateSentence != null) {
      return translateSentence(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$TranslateSentenceImplToJson(
      this,
    );
  }
}

abstract class TranslateSentence implements Interaction {
  const factory TranslateSentence(
      {final String id,
      required final String source,
      required final String expected,
      final List<String> hints,
      final String? grammarPointId}) = _$TranslateSentenceImpl;

  factory TranslateSentence.fromJson(Map<String, dynamic> json) =
      _$TranslateSentenceImpl.fromJson;

  @override
  String get id;
  String get source;
  String get expected;
  List<String> get hints;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$TranslateSentenceImplCopyWith<_$TranslateSentenceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ListenAndPickImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ListenAndPickImplCopyWith(
          _$ListenAndPickImpl value, $Res Function(_$ListenAndPickImpl) then) =
      __$$ListenAndPickImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String audioAsset,
      String prompt,
      List<String> options,
      int correctIndex,
      String? grammarPointId});
}

/// @nodoc
class __$$ListenAndPickImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ListenAndPickImpl>
    implements _$$ListenAndPickImplCopyWith<$Res> {
  __$$ListenAndPickImplCopyWithImpl(
      _$ListenAndPickImpl _value, $Res Function(_$ListenAndPickImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? audioAsset = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndex = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$ListenAndPickImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: null == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndex: null == correctIndex
          ? _value.correctIndex
          : correctIndex // ignore: cast_nullable_to_non_nullable
              as int,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ListenAndPickImpl implements ListenAndPick {
  const _$ListenAndPickImpl(
      {this.id = '',
      required this.audioAsset,
      required this.prompt,
      required final List<String> options,
      required this.correctIndex,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        $type = $type ?? 'listenAndPick';

  factory _$ListenAndPickImpl.fromJson(Map<String, dynamic> json) =>
      _$$ListenAndPickImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String audioAsset;
  @override
  final String prompt;
  final List<String> _options;
  @override
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  @override
  final int correctIndex;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.listenAndPick(id: $id, audioAsset: $audioAsset, prompt: $prompt, options: $options, correctIndex: $correctIndex, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ListenAndPickImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            (identical(other.correctIndex, correctIndex) ||
                other.correctIndex == correctIndex) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      audioAsset,
      prompt,
      const DeepCollectionEquality().hash(_options),
      correctIndex,
      grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ListenAndPickImplCopyWith<_$ListenAndPickImpl> get copyWith =>
      __$$ListenAndPickImplCopyWithImpl<_$ListenAndPickImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return listenAndPick(
        id, audioAsset, prompt, options, correctIndex, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return listenAndPick?.call(
        id, audioAsset, prompt, options, correctIndex, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (listenAndPick != null) {
      return listenAndPick(
          id, audioAsset, prompt, options, correctIndex, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return listenAndPick(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return listenAndPick?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (listenAndPick != null) {
      return listenAndPick(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ListenAndPickImplToJson(
      this,
    );
  }
}

abstract class ListenAndPick implements Interaction {
  const factory ListenAndPick(
      {final String id,
      required final String audioAsset,
      required final String prompt,
      required final List<String> options,
      required final int correctIndex,
      final String? grammarPointId}) = _$ListenAndPickImpl;

  factory ListenAndPick.fromJson(Map<String, dynamic> json) =
      _$ListenAndPickImpl.fromJson;

  @override
  String get id;
  String get audioAsset;
  String get prompt;
  List<String> get options;
  int get correctIndex;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$ListenAndPickImplCopyWith<_$ListenAndPickImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TypeTheWordImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$TypeTheWordImplCopyWith(
          _$TypeTheWordImpl value, $Res Function(_$TypeTheWordImpl) then) =
      __$$TypeTheWordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String audioAsset,
      String prompt,
      String expected,
      String? grammarPointId});
}

/// @nodoc
class __$$TypeTheWordImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$TypeTheWordImpl>
    implements _$$TypeTheWordImplCopyWith<$Res> {
  __$$TypeTheWordImplCopyWithImpl(
      _$TypeTheWordImpl _value, $Res Function(_$TypeTheWordImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? audioAsset = null,
    Object? prompt = null,
    Object? expected = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$TypeTheWordImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: null == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      expected: null == expected
          ? _value.expected
          : expected // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TypeTheWordImpl implements TypeTheWord {
  const _$TypeTheWordImpl(
      {this.id = '',
      required this.audioAsset,
      required this.prompt,
      required this.expected,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'typeTheWord';

  factory _$TypeTheWordImpl.fromJson(Map<String, dynamic> json) =>
      _$$TypeTheWordImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String audioAsset;
  @override
  final String prompt;
  @override
  final String expected;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.typeTheWord(id: $id, audioAsset: $audioAsset, prompt: $prompt, expected: $expected, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TypeTheWordImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.expected, expected) ||
                other.expected == expected) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, audioAsset, prompt, expected, grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TypeTheWordImplCopyWith<_$TypeTheWordImpl> get copyWith =>
      __$$TypeTheWordImplCopyWithImpl<_$TypeTheWordImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return typeTheWord(id, audioAsset, prompt, expected, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return typeTheWord?.call(id, audioAsset, prompt, expected, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (typeTheWord != null) {
      return typeTheWord(id, audioAsset, prompt, expected, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return typeTheWord(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return typeTheWord?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (typeTheWord != null) {
      return typeTheWord(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$TypeTheWordImplToJson(
      this,
    );
  }
}

abstract class TypeTheWord implements Interaction {
  const factory TypeTheWord(
      {final String id,
      required final String audioAsset,
      required final String prompt,
      required final String expected,
      final String? grammarPointId}) = _$TypeTheWordImpl;

  factory TypeTheWord.fromJson(Map<String, dynamic> json) =
      _$TypeTheWordImpl.fromJson;

  @override
  String get id;
  String get audioAsset;
  String get prompt;
  String get expected;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$TypeTheWordImplCopyWith<_$TypeTheWordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ListenOnlyImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ListenOnlyImplCopyWith(
          _$ListenOnlyImpl value, $Res Function(_$ListenOnlyImpl) then) =
      __$$ListenOnlyImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String? audioAsset,
      String transcript,
      String prompt,
      String? grammarPointId});
}

/// @nodoc
class __$$ListenOnlyImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ListenOnlyImpl>
    implements _$$ListenOnlyImplCopyWith<$Res> {
  __$$ListenOnlyImplCopyWithImpl(
      _$ListenOnlyImpl _value, $Res Function(_$ListenOnlyImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? audioAsset = freezed,
    Object? transcript = null,
    Object? prompt = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$ListenOnlyImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: null == transcript
          ? _value.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ListenOnlyImpl implements ListenOnly {
  const _$ListenOnlyImpl(
      {this.id = '',
      this.audioAsset,
      this.transcript = '',
      this.prompt = 'Listen to the summary',
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'listenOnly';

  factory _$ListenOnlyImpl.fromJson(Map<String, dynamic> json) =>
      _$$ListenOnlyImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String? audioAsset;
  @override
  @JsonKey()
  final String transcript;
  @override
  @JsonKey()
  final String prompt;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.listenOnly(id: $id, audioAsset: $audioAsset, transcript: $transcript, prompt: $prompt, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ListenOnlyImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.transcript, transcript) ||
                other.transcript == transcript) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, audioAsset, transcript, prompt, grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ListenOnlyImplCopyWith<_$ListenOnlyImpl> get copyWith =>
      __$$ListenOnlyImplCopyWithImpl<_$ListenOnlyImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return listenOnly(id, audioAsset, transcript, prompt, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return listenOnly?.call(id, audioAsset, transcript, prompt, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (listenOnly != null) {
      return listenOnly(id, audioAsset, transcript, prompt, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return listenOnly(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return listenOnly?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (listenOnly != null) {
      return listenOnly(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ListenOnlyImplToJson(
      this,
    );
  }
}

abstract class ListenOnly implements Interaction {
  const factory ListenOnly(
      {final String id,
      final String? audioAsset,
      final String transcript,
      final String prompt,
      final String? grammarPointId}) = _$ListenOnlyImpl;

  factory ListenOnly.fromJson(Map<String, dynamic> json) =
      _$ListenOnlyImpl.fromJson;

  @override
  String get id;
  String? get audioAsset;
  String get transcript;
  String get prompt;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$ListenOnlyImplCopyWith<_$ListenOnlyImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ReorderSentenceImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ReorderSentenceImplCopyWith(_$ReorderSentenceImpl value,
          $Res Function(_$ReorderSentenceImpl) then) =
      __$$ReorderSentenceImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      List<String> scrambled,
      List<String> correct,
      String? grammarPointId});
}

/// @nodoc
class __$$ReorderSentenceImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ReorderSentenceImpl>
    implements _$$ReorderSentenceImplCopyWith<$Res> {
  __$$ReorderSentenceImplCopyWithImpl(
      _$ReorderSentenceImpl _value, $Res Function(_$ReorderSentenceImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? scrambled = null,
    Object? correct = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$ReorderSentenceImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      scrambled: null == scrambled
          ? _value._scrambled
          : scrambled // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correct: null == correct
          ? _value._correct
          : correct // ignore: cast_nullable_to_non_nullable
              as List<String>,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReorderSentenceImpl implements ReorderSentence {
  const _$ReorderSentenceImpl(
      {this.id = '',
      required final List<String> scrambled,
      required final List<String> correct,
      this.grammarPointId,
      final String? $type})
      : _scrambled = scrambled,
        _correct = correct,
        $type = $type ?? 'reorderSentence';

  factory _$ReorderSentenceImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReorderSentenceImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  final List<String> _scrambled;
  @override
  List<String> get scrambled {
    if (_scrambled is EqualUnmodifiableListView) return _scrambled;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_scrambled);
  }

  final List<String> _correct;
  @override
  List<String> get correct {
    if (_correct is EqualUnmodifiableListView) return _correct;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_correct);
  }

  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.reorderSentence(id: $id, scrambled: $scrambled, correct: $correct, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReorderSentenceImpl &&
            (identical(other.id, id) || other.id == id) &&
            const DeepCollectionEquality()
                .equals(other._scrambled, _scrambled) &&
            const DeepCollectionEquality().equals(other._correct, _correct) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      const DeepCollectionEquality().hash(_scrambled),
      const DeepCollectionEquality().hash(_correct),
      grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReorderSentenceImplCopyWith<_$ReorderSentenceImpl> get copyWith =>
      __$$ReorderSentenceImplCopyWithImpl<_$ReorderSentenceImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return reorderSentence(id, scrambled, correct, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return reorderSentence?.call(id, scrambled, correct, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (reorderSentence != null) {
      return reorderSentence(id, scrambled, correct, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return reorderSentence(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return reorderSentence?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (reorderSentence != null) {
      return reorderSentence(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ReorderSentenceImplToJson(
      this,
    );
  }
}

abstract class ReorderSentence implements Interaction {
  const factory ReorderSentence(
      {final String id,
      required final List<String> scrambled,
      required final List<String> correct,
      final String? grammarPointId}) = _$ReorderSentenceImpl;

  factory ReorderSentence.fromJson(Map<String, dynamic> json) =
      _$ReorderSentenceImpl.fromJson;

  @override
  String get id;
  List<String> get scrambled;
  List<String> get correct;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$ReorderSentenceImplCopyWith<_$ReorderSentenceImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ReadingMcqImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ReadingMcqImplCopyWith(
          _$ReadingMcqImpl value, $Res Function(_$ReadingMcqImpl) then) =
      __$$ReadingMcqImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String prompt,
      List<String> options,
      int correctIndex,
      String? grammarPointId});
}

/// @nodoc
class __$$ReadingMcqImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ReadingMcqImpl>
    implements _$$ReadingMcqImplCopyWith<$Res> {
  __$$ReadingMcqImplCopyWithImpl(
      _$ReadingMcqImpl _value, $Res Function(_$ReadingMcqImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndex = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$ReadingMcqImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndex: null == correctIndex
          ? _value.correctIndex
          : correctIndex // ignore: cast_nullable_to_non_nullable
              as int,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReadingMcqImpl implements ReadingMcq {
  const _$ReadingMcqImpl(
      {this.id = '',
      required this.prompt,
      required final List<String> options,
      required this.correctIndex,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        $type = $type ?? 'readingMcq';

  factory _$ReadingMcqImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReadingMcqImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String prompt;
  final List<String> _options;
  @override
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  @override
  final int correctIndex;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.readingMcq(id: $id, prompt: $prompt, options: $options, correctIndex: $correctIndex, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReadingMcqImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            (identical(other.correctIndex, correctIndex) ||
                other.correctIndex == correctIndex) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      prompt,
      const DeepCollectionEquality().hash(_options),
      correctIndex,
      grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReadingMcqImplCopyWith<_$ReadingMcqImpl> get copyWith =>
      __$$ReadingMcqImplCopyWithImpl<_$ReadingMcqImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return readingMcq(id, prompt, options, correctIndex, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return readingMcq?.call(id, prompt, options, correctIndex, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (readingMcq != null) {
      return readingMcq(id, prompt, options, correctIndex, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return readingMcq(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return readingMcq?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (readingMcq != null) {
      return readingMcq(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ReadingMcqImplToJson(
      this,
    );
  }
}

abstract class ReadingMcq implements Interaction {
  const factory ReadingMcq(
      {final String id,
      required final String prompt,
      required final List<String> options,
      required final int correctIndex,
      final String? grammarPointId}) = _$ReadingMcqImpl;

  factory ReadingMcq.fromJson(Map<String, dynamic> json) =
      _$ReadingMcqImpl.fromJson;

  @override
  String get id;
  String get prompt;
  List<String> get options;
  int get correctIndex;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$ReadingMcqImplCopyWith<_$ReadingMcqImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ReadingTrueFalseImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ReadingTrueFalseImplCopyWith(_$ReadingTrueFalseImpl value,
          $Res Function(_$ReadingTrueFalseImpl) then) =
      __$$ReadingTrueFalseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String statement, bool answer, String? grammarPointId});
}

/// @nodoc
class __$$ReadingTrueFalseImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ReadingTrueFalseImpl>
    implements _$$ReadingTrueFalseImplCopyWith<$Res> {
  __$$ReadingTrueFalseImplCopyWithImpl(_$ReadingTrueFalseImpl _value,
      $Res Function(_$ReadingTrueFalseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? statement = null,
    Object? answer = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$ReadingTrueFalseImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      statement: null == statement
          ? _value.statement
          : statement // ignore: cast_nullable_to_non_nullable
              as String,
      answer: null == answer
          ? _value.answer
          : answer // ignore: cast_nullable_to_non_nullable
              as bool,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReadingTrueFalseImpl implements ReadingTrueFalse {
  const _$ReadingTrueFalseImpl(
      {this.id = '',
      required this.statement,
      required this.answer,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'readingTrueFalse';

  factory _$ReadingTrueFalseImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReadingTrueFalseImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String statement;
  @override
  final bool answer;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.readingTrueFalse(id: $id, statement: $statement, answer: $answer, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReadingTrueFalseImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.statement, statement) ||
                other.statement == statement) &&
            (identical(other.answer, answer) || other.answer == answer) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, statement, answer, grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReadingTrueFalseImplCopyWith<_$ReadingTrueFalseImpl> get copyWith =>
      __$$ReadingTrueFalseImplCopyWithImpl<_$ReadingTrueFalseImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return readingTrueFalse(id, statement, answer, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return readingTrueFalse?.call(id, statement, answer, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (readingTrueFalse != null) {
      return readingTrueFalse(id, statement, answer, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return readingTrueFalse(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return readingTrueFalse?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (readingTrueFalse != null) {
      return readingTrueFalse(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ReadingTrueFalseImplToJson(
      this,
    );
  }
}

abstract class ReadingTrueFalse implements Interaction {
  const factory ReadingTrueFalse(
      {final String id,
      required final String statement,
      required final bool answer,
      final String? grammarPointId}) = _$ReadingTrueFalseImpl;

  factory ReadingTrueFalse.fromJson(Map<String, dynamic> json) =
      _$ReadingTrueFalseImpl.fromJson;

  @override
  String get id;
  String get statement;
  bool get answer;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$ReadingTrueFalseImplCopyWith<_$ReadingTrueFalseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ReadingShortAnswerImplCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory _$$ReadingShortAnswerImplCopyWith(_$ReadingShortAnswerImpl value,
          $Res Function(_$ReadingShortAnswerImpl) then) =
      __$$ReadingShortAnswerImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String prompt,
      String expectedAnswer,
      String? grammarPointId});
}

/// @nodoc
class __$$ReadingShortAnswerImplCopyWithImpl<$Res>
    extends _$InteractionCopyWithImpl<$Res, _$ReadingShortAnswerImpl>
    implements _$$ReadingShortAnswerImplCopyWith<$Res> {
  __$$ReadingShortAnswerImplCopyWithImpl(_$ReadingShortAnswerImpl _value,
      $Res Function(_$ReadingShortAnswerImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? expectedAnswer = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(_$ReadingShortAnswerImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _value.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      expectedAnswer: null == expectedAnswer
          ? _value.expectedAnswer
          : expectedAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReadingShortAnswerImpl implements ReadingShortAnswer {
  const _$ReadingShortAnswerImpl(
      {this.id = '',
      required this.prompt,
      required this.expectedAnswer,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'readingShortAnswer';

  factory _$ReadingShortAnswerImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReadingShortAnswerImplFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String prompt;
  @override
  final String expectedAnswer;
  @override
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'Interaction.readingShortAnswer(id: $id, prompt: $prompt, expectedAnswer: $expectedAnswer, grammarPointId: $grammarPointId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReadingShortAnswerImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.expectedAnswer, expectedAnswer) ||
                other.expectedAnswer == expectedAnswer) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, prompt, expectedAnswer, grammarPointId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReadingShortAnswerImplCopyWith<_$ReadingShortAnswerImpl> get copyWith =>
      __$$ReadingShortAnswerImplCopyWithImpl<_$ReadingShortAnswerImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)
        showWord,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)
        multipleChoice,
    required TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)
        multiSelect,
    required TResult Function(String id, String sentence, String answer,
            String? hint, String? grammarPointId)
        fillBlank,
    required TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)
        translateSentence,
    required TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)
        listenAndPick,
    required TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)
        typeTheWord,
    required TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)
        listenOnly,
    required TResult Function(String id, List<String> scrambled,
            List<String> correct, String? grammarPointId)
        reorderSentence,
    required TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)
        readingMcq,
    required TResult Function(
            String id, String statement, bool answer, String? grammarPointId)
        readingTrueFalse,
    required TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)
        readingShortAnswer,
  }) {
    return readingShortAnswer(id, prompt, expectedAnswer, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult? Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult? Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult? Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult? Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult? Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult? Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult? Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult? Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult? Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult? Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
  }) {
    return readingShortAnswer?.call(id, prompt, expectedAnswer, grammarPointId);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String wordId, String? context,
            String? grammarPointId, String? expressionId)?
        showWord,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? imageAsset, String? grammarPointId)?
        multipleChoice,
    TResult Function(
            String id,
            String prompt,
            List<String> options,
            List<int> correctIndices,
            int minSelections,
            int maxSelections,
            String? imageAsset,
            String? grammarPointId)?
        multiSelect,
    TResult Function(String id, String sentence, String answer, String? hint,
            String? grammarPointId)?
        fillBlank,
    TResult Function(String id, String source, String expected,
            List<String> hints, String? grammarPointId)?
        translateSentence,
    TResult Function(String id, String audioAsset, String prompt,
            List<String> options, int correctIndex, String? grammarPointId)?
        listenAndPick,
    TResult Function(String id, String audioAsset, String prompt,
            String expected, String? grammarPointId)?
        typeTheWord,
    TResult Function(String id, String? audioAsset, String transcript,
            String prompt, String? grammarPointId)?
        listenOnly,
    TResult Function(String id, List<String> scrambled, List<String> correct,
            String? grammarPointId)?
        reorderSentence,
    TResult Function(String id, String prompt, List<String> options,
            int correctIndex, String? grammarPointId)?
        readingMcq,
    TResult Function(
            String id, String statement, bool answer, String? grammarPointId)?
        readingTrueFalse,
    TResult Function(String id, String prompt, String expectedAnswer,
            String? grammarPointId)?
        readingShortAnswer,
    required TResult orElse(),
  }) {
    if (readingShortAnswer != null) {
      return readingShortAnswer(id, prompt, expectedAnswer, grammarPointId);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ShowWord value) showWord,
    required TResult Function(MultipleChoice value) multipleChoice,
    required TResult Function(MultiSelect value) multiSelect,
    required TResult Function(FillBlank value) fillBlank,
    required TResult Function(TranslateSentence value) translateSentence,
    required TResult Function(ListenAndPick value) listenAndPick,
    required TResult Function(TypeTheWord value) typeTheWord,
    required TResult Function(ListenOnly value) listenOnly,
    required TResult Function(ReorderSentence value) reorderSentence,
    required TResult Function(ReadingMcq value) readingMcq,
    required TResult Function(ReadingTrueFalse value) readingTrueFalse,
    required TResult Function(ReadingShortAnswer value) readingShortAnswer,
  }) {
    return readingShortAnswer(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ShowWord value)? showWord,
    TResult? Function(MultipleChoice value)? multipleChoice,
    TResult? Function(MultiSelect value)? multiSelect,
    TResult? Function(FillBlank value)? fillBlank,
    TResult? Function(TranslateSentence value)? translateSentence,
    TResult? Function(ListenAndPick value)? listenAndPick,
    TResult? Function(TypeTheWord value)? typeTheWord,
    TResult? Function(ListenOnly value)? listenOnly,
    TResult? Function(ReorderSentence value)? reorderSentence,
    TResult? Function(ReadingMcq value)? readingMcq,
    TResult? Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult? Function(ReadingShortAnswer value)? readingShortAnswer,
  }) {
    return readingShortAnswer?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ShowWord value)? showWord,
    TResult Function(MultipleChoice value)? multipleChoice,
    TResult Function(MultiSelect value)? multiSelect,
    TResult Function(FillBlank value)? fillBlank,
    TResult Function(TranslateSentence value)? translateSentence,
    TResult Function(ListenAndPick value)? listenAndPick,
    TResult Function(TypeTheWord value)? typeTheWord,
    TResult Function(ListenOnly value)? listenOnly,
    TResult Function(ReorderSentence value)? reorderSentence,
    TResult Function(ReadingMcq value)? readingMcq,
    TResult Function(ReadingTrueFalse value)? readingTrueFalse,
    TResult Function(ReadingShortAnswer value)? readingShortAnswer,
    required TResult orElse(),
  }) {
    if (readingShortAnswer != null) {
      return readingShortAnswer(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ReadingShortAnswerImplToJson(
      this,
    );
  }
}

abstract class ReadingShortAnswer implements Interaction {
  const factory ReadingShortAnswer(
      {final String id,
      required final String prompt,
      required final String expectedAnswer,
      final String? grammarPointId}) = _$ReadingShortAnswerImpl;

  factory ReadingShortAnswer.fromJson(Map<String, dynamic> json) =
      _$ReadingShortAnswerImpl.fromJson;

  @override
  String get id;
  String get prompt;
  String get expectedAnswer;
  @override
  String? get grammarPointId;
  @override
  @JsonKey(ignore: true)
  _$$ReadingShortAnswerImplCopyWith<_$ReadingShortAnswerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
