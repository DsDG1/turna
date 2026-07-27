// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
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
    case 'ankiCard':
      return AnkiCard.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'Interaction',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$Interaction {
  String get id;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $InteractionCopyWith<Interaction> get copyWith =>
      _$InteractionCopyWithImpl<Interaction>(this as Interaction, _$identity);

  /// Serializes this Interaction to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Interaction &&
            (identical(other.id, id) || other.id == id));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id);

  @override
  String toString() {
    return 'Interaction(id: $id)';
  }
}

/// @nodoc
abstract mixin class $InteractionCopyWith<$Res> {
  factory $InteractionCopyWith(
          Interaction value, $Res Function(Interaction) _then) =
      _$InteractionCopyWithImpl;
  @useResult
  $Res call({String id});
}

/// @nodoc
class _$InteractionCopyWithImpl<$Res> implements $InteractionCopyWith<$Res> {
  _$InteractionCopyWithImpl(this._self, this._then);

  final Interaction _self;
  final $Res Function(Interaction) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [Interaction].
extension InteractionPatterns on Interaction {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

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
    TResult Function(AnkiCard value)? ankiCard,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case ShowWord() when showWord != null:
        return showWord(_that);
      case MultipleChoice() when multipleChoice != null:
        return multipleChoice(_that);
      case MultiSelect() when multiSelect != null:
        return multiSelect(_that);
      case FillBlank() when fillBlank != null:
        return fillBlank(_that);
      case TranslateSentence() when translateSentence != null:
        return translateSentence(_that);
      case ListenAndPick() when listenAndPick != null:
        return listenAndPick(_that);
      case TypeTheWord() when typeTheWord != null:
        return typeTheWord(_that);
      case ListenOnly() when listenOnly != null:
        return listenOnly(_that);
      case ReorderSentence() when reorderSentence != null:
        return reorderSentence(_that);
      case ReadingMcq() when readingMcq != null:
        return readingMcq(_that);
      case ReadingTrueFalse() when readingTrueFalse != null:
        return readingTrueFalse(_that);
      case ReadingShortAnswer() when readingShortAnswer != null:
        return readingShortAnswer(_that);
      case AnkiCard() when ankiCard != null:
        return ankiCard(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

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
    required TResult Function(AnkiCard value) ankiCard,
  }) {
    final _that = this;
    switch (_that) {
      case ShowWord():
        return showWord(_that);
      case MultipleChoice():
        return multipleChoice(_that);
      case MultiSelect():
        return multiSelect(_that);
      case FillBlank():
        return fillBlank(_that);
      case TranslateSentence():
        return translateSentence(_that);
      case ListenAndPick():
        return listenAndPick(_that);
      case TypeTheWord():
        return typeTheWord(_that);
      case ListenOnly():
        return listenOnly(_that);
      case ReorderSentence():
        return reorderSentence(_that);
      case ReadingMcq():
        return readingMcq(_that);
      case ReadingTrueFalse():
        return readingTrueFalse(_that);
      case ReadingShortAnswer():
        return readingShortAnswer(_that);
      case AnkiCard():
        return ankiCard(_that);
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

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
    TResult? Function(AnkiCard value)? ankiCard,
  }) {
    final _that = this;
    switch (_that) {
      case ShowWord() when showWord != null:
        return showWord(_that);
      case MultipleChoice() when multipleChoice != null:
        return multipleChoice(_that);
      case MultiSelect() when multiSelect != null:
        return multiSelect(_that);
      case FillBlank() when fillBlank != null:
        return fillBlank(_that);
      case TranslateSentence() when translateSentence != null:
        return translateSentence(_that);
      case ListenAndPick() when listenAndPick != null:
        return listenAndPick(_that);
      case TypeTheWord() when typeTheWord != null:
        return typeTheWord(_that);
      case ListenOnly() when listenOnly != null:
        return listenOnly(_that);
      case ReorderSentence() when reorderSentence != null:
        return reorderSentence(_that);
      case ReadingMcq() when readingMcq != null:
        return readingMcq(_that);
      case ReadingTrueFalse() when readingTrueFalse != null:
        return readingTrueFalse(_that);
      case ReadingShortAnswer() when readingShortAnswer != null:
        return readingShortAnswer(_that);
      case AnkiCard() when ankiCard != null:
        return ankiCard(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

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
    TResult Function(
            String id,
            String front,
            String back,
            List<String> audioAssets,
            List<String> imageAssets,
            String? hint,
            String? sourceNoteId)?
        ankiCard,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case ShowWord() when showWord != null:
        return showWord(_that.id, _that.wordId, _that.context,
            _that.grammarPointId, _that.expressionId);
      case MultipleChoice() when multipleChoice != null:
        return multipleChoice(_that.id, _that.prompt, _that.options,
            _that.correctIndex, _that.imageAsset, _that.grammarPointId);
      case MultiSelect() when multiSelect != null:
        return multiSelect(
            _that.id,
            _that.prompt,
            _that.options,
            _that.correctIndices,
            _that.minSelections,
            _that.maxSelections,
            _that.imageAsset,
            _that.grammarPointId);
      case FillBlank() when fillBlank != null:
        return fillBlank(_that.id, _that.sentence, _that.answer, _that.hint,
            _that.grammarPointId);
      case TranslateSentence() when translateSentence != null:
        return translateSentence(_that.id, _that.source, _that.expected,
            _that.hints, _that.grammarPointId);
      case ListenAndPick() when listenAndPick != null:
        return listenAndPick(_that.id, _that.audioAsset, _that.prompt,
            _that.options, _that.correctIndex, _that.grammarPointId);
      case TypeTheWord() when typeTheWord != null:
        return typeTheWord(_that.id, _that.audioAsset, _that.prompt,
            _that.expected, _that.grammarPointId);
      case ListenOnly() when listenOnly != null:
        return listenOnly(_that.id, _that.audioAsset, _that.transcript,
            _that.prompt, _that.grammarPointId);
      case ReorderSentence() when reorderSentence != null:
        return reorderSentence(
            _that.id, _that.scrambled, _that.correct, _that.grammarPointId);
      case ReadingMcq() when readingMcq != null:
        return readingMcq(_that.id, _that.prompt, _that.options,
            _that.correctIndex, _that.grammarPointId);
      case ReadingTrueFalse() when readingTrueFalse != null:
        return readingTrueFalse(
            _that.id, _that.statement, _that.answer, _that.grammarPointId);
      case ReadingShortAnswer() when readingShortAnswer != null:
        return readingShortAnswer(
            _that.id, _that.prompt, _that.expectedAnswer, _that.grammarPointId);
      case AnkiCard() when ankiCard != null:
        return ankiCard(_that.id, _that.front, _that.back, _that.audioAssets,
            _that.imageAssets, _that.hint, _that.sourceNoteId);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

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
    required TResult Function(
            String id,
            String front,
            String back,
            List<String> audioAssets,
            List<String> imageAssets,
            String? hint,
            String? sourceNoteId)
        ankiCard,
  }) {
    final _that = this;
    switch (_that) {
      case ShowWord():
        return showWord(_that.id, _that.wordId, _that.context,
            _that.grammarPointId, _that.expressionId);
      case MultipleChoice():
        return multipleChoice(_that.id, _that.prompt, _that.options,
            _that.correctIndex, _that.imageAsset, _that.grammarPointId);
      case MultiSelect():
        return multiSelect(
            _that.id,
            _that.prompt,
            _that.options,
            _that.correctIndices,
            _that.minSelections,
            _that.maxSelections,
            _that.imageAsset,
            _that.grammarPointId);
      case FillBlank():
        return fillBlank(_that.id, _that.sentence, _that.answer, _that.hint,
            _that.grammarPointId);
      case TranslateSentence():
        return translateSentence(_that.id, _that.source, _that.expected,
            _that.hints, _that.grammarPointId);
      case ListenAndPick():
        return listenAndPick(_that.id, _that.audioAsset, _that.prompt,
            _that.options, _that.correctIndex, _that.grammarPointId);
      case TypeTheWord():
        return typeTheWord(_that.id, _that.audioAsset, _that.prompt,
            _that.expected, _that.grammarPointId);
      case ListenOnly():
        return listenOnly(_that.id, _that.audioAsset, _that.transcript,
            _that.prompt, _that.grammarPointId);
      case ReorderSentence():
        return reorderSentence(
            _that.id, _that.scrambled, _that.correct, _that.grammarPointId);
      case ReadingMcq():
        return readingMcq(_that.id, _that.prompt, _that.options,
            _that.correctIndex, _that.grammarPointId);
      case ReadingTrueFalse():
        return readingTrueFalse(
            _that.id, _that.statement, _that.answer, _that.grammarPointId);
      case ReadingShortAnswer():
        return readingShortAnswer(
            _that.id, _that.prompt, _that.expectedAnswer, _that.grammarPointId);
      case AnkiCard():
        return ankiCard(_that.id, _that.front, _that.back, _that.audioAssets,
            _that.imageAssets, _that.hint, _that.sourceNoteId);
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

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
    TResult? Function(
            String id,
            String front,
            String back,
            List<String> audioAssets,
            List<String> imageAssets,
            String? hint,
            String? sourceNoteId)?
        ankiCard,
  }) {
    final _that = this;
    switch (_that) {
      case ShowWord() when showWord != null:
        return showWord(_that.id, _that.wordId, _that.context,
            _that.grammarPointId, _that.expressionId);
      case MultipleChoice() when multipleChoice != null:
        return multipleChoice(_that.id, _that.prompt, _that.options,
            _that.correctIndex, _that.imageAsset, _that.grammarPointId);
      case MultiSelect() when multiSelect != null:
        return multiSelect(
            _that.id,
            _that.prompt,
            _that.options,
            _that.correctIndices,
            _that.minSelections,
            _that.maxSelections,
            _that.imageAsset,
            _that.grammarPointId);
      case FillBlank() when fillBlank != null:
        return fillBlank(_that.id, _that.sentence, _that.answer, _that.hint,
            _that.grammarPointId);
      case TranslateSentence() when translateSentence != null:
        return translateSentence(_that.id, _that.source, _that.expected,
            _that.hints, _that.grammarPointId);
      case ListenAndPick() when listenAndPick != null:
        return listenAndPick(_that.id, _that.audioAsset, _that.prompt,
            _that.options, _that.correctIndex, _that.grammarPointId);
      case TypeTheWord() when typeTheWord != null:
        return typeTheWord(_that.id, _that.audioAsset, _that.prompt,
            _that.expected, _that.grammarPointId);
      case ListenOnly() when listenOnly != null:
        return listenOnly(_that.id, _that.audioAsset, _that.transcript,
            _that.prompt, _that.grammarPointId);
      case ReorderSentence() when reorderSentence != null:
        return reorderSentence(
            _that.id, _that.scrambled, _that.correct, _that.grammarPointId);
      case ReadingMcq() when readingMcq != null:
        return readingMcq(_that.id, _that.prompt, _that.options,
            _that.correctIndex, _that.grammarPointId);
      case ReadingTrueFalse() when readingTrueFalse != null:
        return readingTrueFalse(
            _that.id, _that.statement, _that.answer, _that.grammarPointId);
      case ReadingShortAnswer() when readingShortAnswer != null:
        return readingShortAnswer(
            _that.id, _that.prompt, _that.expectedAnswer, _that.grammarPointId);
      case AnkiCard() when ankiCard != null:
        return ankiCard(_that.id, _that.front, _that.back, _that.audioAssets,
            _that.imageAssets, _that.hint, _that.sourceNoteId);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class ShowWord implements Interaction {
  const ShowWord(
      {this.id = '',
      required this.wordId,
      this.context,
      this.grammarPointId,
      this.expressionId,
      final String? $type})
      : $type = $type ?? 'showWord';
  factory ShowWord.fromJson(Map<String, dynamic> json) =>
      _$ShowWordFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String wordId;
  final String? context;
  final String? grammarPointId;
  final String? expressionId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ShowWordCopyWith<ShowWord> get copyWith =>
      _$ShowWordCopyWithImpl<ShowWord>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ShowWordToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ShowWord &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.context, context) || other.context == context) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId) &&
            (identical(other.expressionId, expressionId) ||
                other.expressionId == expressionId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, wordId, context, grammarPointId, expressionId);

  @override
  String toString() {
    return 'Interaction.showWord(id: $id, wordId: $wordId, context: $context, grammarPointId: $grammarPointId, expressionId: $expressionId)';
  }
}

/// @nodoc
abstract mixin class $ShowWordCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ShowWordCopyWith(ShowWord value, $Res Function(ShowWord) _then) =
      _$ShowWordCopyWithImpl;
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
class _$ShowWordCopyWithImpl<$Res> implements $ShowWordCopyWith<$Res> {
  _$ShowWordCopyWithImpl(this._self, this._then);

  final ShowWord _self;
  final $Res Function(ShowWord) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? wordId = null,
    Object? context = freezed,
    Object? grammarPointId = freezed,
    Object? expressionId = freezed,
  }) {
    return _then(ShowWord(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      wordId: null == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      context: freezed == context
          ? _self.context
          : context // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
      expressionId: freezed == expressionId
          ? _self.expressionId
          : expressionId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class MultipleChoice implements Interaction {
  const MultipleChoice(
      {this.id = '',
      required this.prompt,
      required final List<String> options,
      required this.correctIndex,
      this.imageAsset,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        $type = $type ?? 'multipleChoice';
  factory MultipleChoice.fromJson(Map<String, dynamic> json) =>
      _$MultipleChoiceFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String prompt;
  final List<String> _options;
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  final int correctIndex;
  final String? imageAsset;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $MultipleChoiceCopyWith<MultipleChoice> get copyWith =>
      _$MultipleChoiceCopyWithImpl<MultipleChoice>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$MultipleChoiceToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is MultipleChoice &&
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

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      prompt,
      const DeepCollectionEquality().hash(_options),
      correctIndex,
      imageAsset,
      grammarPointId);

  @override
  String toString() {
    return 'Interaction.multipleChoice(id: $id, prompt: $prompt, options: $options, correctIndex: $correctIndex, imageAsset: $imageAsset, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $MultipleChoiceCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $MultipleChoiceCopyWith(
          MultipleChoice value, $Res Function(MultipleChoice) _then) =
      _$MultipleChoiceCopyWithImpl;
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
class _$MultipleChoiceCopyWithImpl<$Res>
    implements $MultipleChoiceCopyWith<$Res> {
  _$MultipleChoiceCopyWithImpl(this._self, this._then);

  final MultipleChoice _self;
  final $Res Function(MultipleChoice) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndex = null,
    Object? imageAsset = freezed,
    Object? grammarPointId = freezed,
  }) {
    return _then(MultipleChoice(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _self._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndex: null == correctIndex
          ? _self.correctIndex
          : correctIndex // ignore: cast_nullable_to_non_nullable
              as int,
      imageAsset: freezed == imageAsset
          ? _self.imageAsset
          : imageAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class MultiSelect implements Interaction {
  const MultiSelect(
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
  factory MultiSelect.fromJson(Map<String, dynamic> json) =>
      _$MultiSelectFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String prompt;
  final List<String> _options;
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  final List<int> _correctIndices;
  List<int> get correctIndices {
    if (_correctIndices is EqualUnmodifiableListView) return _correctIndices;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_correctIndices);
  }

  @JsonKey()
  final int minSelections;
  @JsonKey()
  final int maxSelections;
  final String? imageAsset;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $MultiSelectCopyWith<MultiSelect> get copyWith =>
      _$MultiSelectCopyWithImpl<MultiSelect>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$MultiSelectToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is MultiSelect &&
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

  @JsonKey(includeFromJson: false, includeToJson: false)
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

  @override
  String toString() {
    return 'Interaction.multiSelect(id: $id, prompt: $prompt, options: $options, correctIndices: $correctIndices, minSelections: $minSelections, maxSelections: $maxSelections, imageAsset: $imageAsset, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $MultiSelectCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $MultiSelectCopyWith(
          MultiSelect value, $Res Function(MultiSelect) _then) =
      _$MultiSelectCopyWithImpl;
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
class _$MultiSelectCopyWithImpl<$Res> implements $MultiSelectCopyWith<$Res> {
  _$MultiSelectCopyWithImpl(this._self, this._then);

  final MultiSelect _self;
  final $Res Function(MultiSelect) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
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
    return _then(MultiSelect(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _self._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndices: null == correctIndices
          ? _self._correctIndices
          : correctIndices // ignore: cast_nullable_to_non_nullable
              as List<int>,
      minSelections: null == minSelections
          ? _self.minSelections
          : minSelections // ignore: cast_nullable_to_non_nullable
              as int,
      maxSelections: null == maxSelections
          ? _self.maxSelections
          : maxSelections // ignore: cast_nullable_to_non_nullable
              as int,
      imageAsset: freezed == imageAsset
          ? _self.imageAsset
          : imageAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class FillBlank implements Interaction {
  const FillBlank(
      {this.id = '',
      required this.sentence,
      required this.answer,
      this.hint,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'fillBlank';
  factory FillBlank.fromJson(Map<String, dynamic> json) =>
      _$FillBlankFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String sentence;
  final String answer;
  final String? hint;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $FillBlankCopyWith<FillBlank> get copyWith =>
      _$FillBlankCopyWithImpl<FillBlank>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$FillBlankToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is FillBlank &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sentence, sentence) ||
                other.sentence == sentence) &&
            (identical(other.answer, answer) || other.answer == answer) &&
            (identical(other.hint, hint) || other.hint == hint) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, sentence, answer, hint, grammarPointId);

  @override
  String toString() {
    return 'Interaction.fillBlank(id: $id, sentence: $sentence, answer: $answer, hint: $hint, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $FillBlankCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $FillBlankCopyWith(FillBlank value, $Res Function(FillBlank) _then) =
      _$FillBlankCopyWithImpl;
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
class _$FillBlankCopyWithImpl<$Res> implements $FillBlankCopyWith<$Res> {
  _$FillBlankCopyWithImpl(this._self, this._then);

  final FillBlank _self;
  final $Res Function(FillBlank) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? sentence = null,
    Object? answer = null,
    Object? hint = freezed,
    Object? grammarPointId = freezed,
  }) {
    return _then(FillBlank(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sentence: null == sentence
          ? _self.sentence
          : sentence // ignore: cast_nullable_to_non_nullable
              as String,
      answer: null == answer
          ? _self.answer
          : answer // ignore: cast_nullable_to_non_nullable
              as String,
      hint: freezed == hint
          ? _self.hint
          : hint // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class TranslateSentence implements Interaction {
  const TranslateSentence(
      {this.id = '',
      required this.source,
      required this.expected,
      final List<String> hints = const <String>[],
      this.grammarPointId,
      final String? $type})
      : _hints = hints,
        $type = $type ?? 'translateSentence';
  factory TranslateSentence.fromJson(Map<String, dynamic> json) =>
      _$TranslateSentenceFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String source;
  final String expected;
  final List<String> _hints;
  @JsonKey()
  List<String> get hints {
    if (_hints is EqualUnmodifiableListView) return _hints;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_hints);
  }

  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $TranslateSentenceCopyWith<TranslateSentence> get copyWith =>
      _$TranslateSentenceCopyWithImpl<TranslateSentence>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$TranslateSentenceToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is TranslateSentence &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.expected, expected) ||
                other.expected == expected) &&
            const DeepCollectionEquality().equals(other._hints, _hints) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, source, expected,
      const DeepCollectionEquality().hash(_hints), grammarPointId);

  @override
  String toString() {
    return 'Interaction.translateSentence(id: $id, source: $source, expected: $expected, hints: $hints, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $TranslateSentenceCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $TranslateSentenceCopyWith(
          TranslateSentence value, $Res Function(TranslateSentence) _then) =
      _$TranslateSentenceCopyWithImpl;
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
class _$TranslateSentenceCopyWithImpl<$Res>
    implements $TranslateSentenceCopyWith<$Res> {
  _$TranslateSentenceCopyWithImpl(this._self, this._then);

  final TranslateSentence _self;
  final $Res Function(TranslateSentence) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? source = null,
    Object? expected = null,
    Object? hints = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(TranslateSentence(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _self.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      expected: null == expected
          ? _self.expected
          : expected // ignore: cast_nullable_to_non_nullable
              as String,
      hints: null == hints
          ? _self._hints
          : hints // ignore: cast_nullable_to_non_nullable
              as List<String>,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class ListenAndPick implements Interaction {
  const ListenAndPick(
      {this.id = '',
      required this.audioAsset,
      required this.prompt,
      required final List<String> options,
      required this.correctIndex,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        $type = $type ?? 'listenAndPick';
  factory ListenAndPick.fromJson(Map<String, dynamic> json) =>
      _$ListenAndPickFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String audioAsset;
  final String prompt;
  final List<String> _options;
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  final int correctIndex;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ListenAndPickCopyWith<ListenAndPick> get copyWith =>
      _$ListenAndPickCopyWithImpl<ListenAndPick>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ListenAndPickToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ListenAndPick &&
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

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      audioAsset,
      prompt,
      const DeepCollectionEquality().hash(_options),
      correctIndex,
      grammarPointId);

  @override
  String toString() {
    return 'Interaction.listenAndPick(id: $id, audioAsset: $audioAsset, prompt: $prompt, options: $options, correctIndex: $correctIndex, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $ListenAndPickCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ListenAndPickCopyWith(
          ListenAndPick value, $Res Function(ListenAndPick) _then) =
      _$ListenAndPickCopyWithImpl;
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
class _$ListenAndPickCopyWithImpl<$Res>
    implements $ListenAndPickCopyWith<$Res> {
  _$ListenAndPickCopyWithImpl(this._self, this._then);

  final ListenAndPick _self;
  final $Res Function(ListenAndPick) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? audioAsset = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndex = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(ListenAndPick(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: null == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _self._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndex: null == correctIndex
          ? _self.correctIndex
          : correctIndex // ignore: cast_nullable_to_non_nullable
              as int,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class TypeTheWord implements Interaction {
  const TypeTheWord(
      {this.id = '',
      required this.audioAsset,
      required this.prompt,
      required this.expected,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'typeTheWord';
  factory TypeTheWord.fromJson(Map<String, dynamic> json) =>
      _$TypeTheWordFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String audioAsset;
  final String prompt;
  final String expected;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $TypeTheWordCopyWith<TypeTheWord> get copyWith =>
      _$TypeTheWordCopyWithImpl<TypeTheWord>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$TypeTheWordToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is TypeTheWord &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.expected, expected) ||
                other.expected == expected) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, audioAsset, prompt, expected, grammarPointId);

  @override
  String toString() {
    return 'Interaction.typeTheWord(id: $id, audioAsset: $audioAsset, prompt: $prompt, expected: $expected, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $TypeTheWordCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $TypeTheWordCopyWith(
          TypeTheWord value, $Res Function(TypeTheWord) _then) =
      _$TypeTheWordCopyWithImpl;
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
class _$TypeTheWordCopyWithImpl<$Res> implements $TypeTheWordCopyWith<$Res> {
  _$TypeTheWordCopyWithImpl(this._self, this._then);

  final TypeTheWord _self;
  final $Res Function(TypeTheWord) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? audioAsset = null,
    Object? prompt = null,
    Object? expected = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(TypeTheWord(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: null == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      expected: null == expected
          ? _self.expected
          : expected // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class ListenOnly implements Interaction {
  const ListenOnly(
      {this.id = '',
      this.audioAsset,
      this.transcript = '',
      this.prompt = 'Listen to the summary',
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'listenOnly';
  factory ListenOnly.fromJson(Map<String, dynamic> json) =>
      _$ListenOnlyFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String? audioAsset;
  @JsonKey()
  final String transcript;
  @JsonKey()
  final String prompt;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ListenOnlyCopyWith<ListenOnly> get copyWith =>
      _$ListenOnlyCopyWithImpl<ListenOnly>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ListenOnlyToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ListenOnly &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.transcript, transcript) ||
                other.transcript == transcript) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, audioAsset, transcript, prompt, grammarPointId);

  @override
  String toString() {
    return 'Interaction.listenOnly(id: $id, audioAsset: $audioAsset, transcript: $transcript, prompt: $prompt, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $ListenOnlyCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ListenOnlyCopyWith(
          ListenOnly value, $Res Function(ListenOnly) _then) =
      _$ListenOnlyCopyWithImpl;
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
class _$ListenOnlyCopyWithImpl<$Res> implements $ListenOnlyCopyWith<$Res> {
  _$ListenOnlyCopyWithImpl(this._self, this._then);

  final ListenOnly _self;
  final $Res Function(ListenOnly) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? audioAsset = freezed,
    Object? transcript = null,
    Object? prompt = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(ListenOnly(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: null == transcript
          ? _self.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class ReorderSentence implements Interaction {
  const ReorderSentence(
      {this.id = '',
      required final List<String> scrambled,
      required final List<String> correct,
      this.grammarPointId,
      final String? $type})
      : _scrambled = scrambled,
        _correct = correct,
        $type = $type ?? 'reorderSentence';
  factory ReorderSentence.fromJson(Map<String, dynamic> json) =>
      _$ReorderSentenceFromJson(json);

  @override
  @JsonKey()
  final String id;
  final List<String> _scrambled;
  List<String> get scrambled {
    if (_scrambled is EqualUnmodifiableListView) return _scrambled;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_scrambled);
  }

  final List<String> _correct;
  List<String> get correct {
    if (_correct is EqualUnmodifiableListView) return _correct;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_correct);
  }

  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReorderSentenceCopyWith<ReorderSentence> get copyWith =>
      _$ReorderSentenceCopyWithImpl<ReorderSentence>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ReorderSentenceToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReorderSentence &&
            (identical(other.id, id) || other.id == id) &&
            const DeepCollectionEquality()
                .equals(other._scrambled, _scrambled) &&
            const DeepCollectionEquality().equals(other._correct, _correct) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      const DeepCollectionEquality().hash(_scrambled),
      const DeepCollectionEquality().hash(_correct),
      grammarPointId);

  @override
  String toString() {
    return 'Interaction.reorderSentence(id: $id, scrambled: $scrambled, correct: $correct, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $ReorderSentenceCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ReorderSentenceCopyWith(
          ReorderSentence value, $Res Function(ReorderSentence) _then) =
      _$ReorderSentenceCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      List<String> scrambled,
      List<String> correct,
      String? grammarPointId});
}

/// @nodoc
class _$ReorderSentenceCopyWithImpl<$Res>
    implements $ReorderSentenceCopyWith<$Res> {
  _$ReorderSentenceCopyWithImpl(this._self, this._then);

  final ReorderSentence _self;
  final $Res Function(ReorderSentence) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? scrambled = null,
    Object? correct = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(ReorderSentence(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      scrambled: null == scrambled
          ? _self._scrambled
          : scrambled // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correct: null == correct
          ? _self._correct
          : correct // ignore: cast_nullable_to_non_nullable
              as List<String>,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class ReadingMcq implements Interaction {
  const ReadingMcq(
      {this.id = '',
      required this.prompt,
      required final List<String> options,
      required this.correctIndex,
      this.grammarPointId,
      final String? $type})
      : _options = options,
        $type = $type ?? 'readingMcq';
  factory ReadingMcq.fromJson(Map<String, dynamic> json) =>
      _$ReadingMcqFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String prompt;
  final List<String> _options;
  List<String> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  final int correctIndex;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReadingMcqCopyWith<ReadingMcq> get copyWith =>
      _$ReadingMcqCopyWithImpl<ReadingMcq>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ReadingMcqToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReadingMcq &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            const DeepCollectionEquality().equals(other._options, _options) &&
            (identical(other.correctIndex, correctIndex) ||
                other.correctIndex == correctIndex) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      prompt,
      const DeepCollectionEquality().hash(_options),
      correctIndex,
      grammarPointId);

  @override
  String toString() {
    return 'Interaction.readingMcq(id: $id, prompt: $prompt, options: $options, correctIndex: $correctIndex, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $ReadingMcqCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ReadingMcqCopyWith(
          ReadingMcq value, $Res Function(ReadingMcq) _then) =
      _$ReadingMcqCopyWithImpl;
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
class _$ReadingMcqCopyWithImpl<$Res> implements $ReadingMcqCopyWith<$Res> {
  _$ReadingMcqCopyWithImpl(this._self, this._then);

  final ReadingMcq _self;
  final $Res Function(ReadingMcq) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? options = null,
    Object? correctIndex = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(ReadingMcq(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _self._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<String>,
      correctIndex: null == correctIndex
          ? _self.correctIndex
          : correctIndex // ignore: cast_nullable_to_non_nullable
              as int,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class ReadingTrueFalse implements Interaction {
  const ReadingTrueFalse(
      {this.id = '',
      required this.statement,
      required this.answer,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'readingTrueFalse';
  factory ReadingTrueFalse.fromJson(Map<String, dynamic> json) =>
      _$ReadingTrueFalseFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String statement;
  final bool answer;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReadingTrueFalseCopyWith<ReadingTrueFalse> get copyWith =>
      _$ReadingTrueFalseCopyWithImpl<ReadingTrueFalse>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ReadingTrueFalseToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReadingTrueFalse &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.statement, statement) ||
                other.statement == statement) &&
            (identical(other.answer, answer) || other.answer == answer) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, statement, answer, grammarPointId);

  @override
  String toString() {
    return 'Interaction.readingTrueFalse(id: $id, statement: $statement, answer: $answer, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $ReadingTrueFalseCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ReadingTrueFalseCopyWith(
          ReadingTrueFalse value, $Res Function(ReadingTrueFalse) _then) =
      _$ReadingTrueFalseCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String statement, bool answer, String? grammarPointId});
}

/// @nodoc
class _$ReadingTrueFalseCopyWithImpl<$Res>
    implements $ReadingTrueFalseCopyWith<$Res> {
  _$ReadingTrueFalseCopyWithImpl(this._self, this._then);

  final ReadingTrueFalse _self;
  final $Res Function(ReadingTrueFalse) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? statement = null,
    Object? answer = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(ReadingTrueFalse(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      statement: null == statement
          ? _self.statement
          : statement // ignore: cast_nullable_to_non_nullable
              as String,
      answer: null == answer
          ? _self.answer
          : answer // ignore: cast_nullable_to_non_nullable
              as bool,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class ReadingShortAnswer implements Interaction {
  const ReadingShortAnswer(
      {this.id = '',
      required this.prompt,
      required this.expectedAnswer,
      this.grammarPointId,
      final String? $type})
      : $type = $type ?? 'readingShortAnswer';
  factory ReadingShortAnswer.fromJson(Map<String, dynamic> json) =>
      _$ReadingShortAnswerFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String prompt;
  final String expectedAnswer;
  final String? grammarPointId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReadingShortAnswerCopyWith<ReadingShortAnswer> get copyWith =>
      _$ReadingShortAnswerCopyWithImpl<ReadingShortAnswer>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ReadingShortAnswerToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReadingShortAnswer &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.prompt, prompt) || other.prompt == prompt) &&
            (identical(other.expectedAnswer, expectedAnswer) ||
                other.expectedAnswer == expectedAnswer) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, prompt, expectedAnswer, grammarPointId);

  @override
  String toString() {
    return 'Interaction.readingShortAnswer(id: $id, prompt: $prompt, expectedAnswer: $expectedAnswer, grammarPointId: $grammarPointId)';
  }
}

/// @nodoc
abstract mixin class $ReadingShortAnswerCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $ReadingShortAnswerCopyWith(
          ReadingShortAnswer value, $Res Function(ReadingShortAnswer) _then) =
      _$ReadingShortAnswerCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String prompt,
      String expectedAnswer,
      String? grammarPointId});
}

/// @nodoc
class _$ReadingShortAnswerCopyWithImpl<$Res>
    implements $ReadingShortAnswerCopyWith<$Res> {
  _$ReadingShortAnswerCopyWithImpl(this._self, this._then);

  final ReadingShortAnswer _self;
  final $Res Function(ReadingShortAnswer) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? prompt = null,
    Object? expectedAnswer = null,
    Object? grammarPointId = freezed,
  }) {
    return _then(ReadingShortAnswer(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      prompt: null == prompt
          ? _self.prompt
          : prompt // ignore: cast_nullable_to_non_nullable
              as String,
      expectedAnswer: null == expectedAnswer
          ? _self.expectedAnswer
          : expectedAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class AnkiCard implements Interaction {
  const AnkiCard(
      {this.id = '',
      required this.front,
      required this.back,
      final List<String> audioAssets = const <String>[],
      final List<String> imageAssets = const <String>[],
      this.hint,
      this.sourceNoteId,
      final String? $type})
      : _audioAssets = audioAssets,
        _imageAssets = imageAssets,
        $type = $type ?? 'ankiCard';
  factory AnkiCard.fromJson(Map<String, dynamic> json) =>
      _$AnkiCardFromJson(json);

  @override
  @JsonKey()
  final String id;
  final String front;
  final String back;
  final List<String> _audioAssets;
  @JsonKey()
  List<String> get audioAssets {
    if (_audioAssets is EqualUnmodifiableListView) return _audioAssets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_audioAssets);
  }

  final List<String> _imageAssets;
  @JsonKey()
  List<String> get imageAssets {
    if (_imageAssets is EqualUnmodifiableListView) return _imageAssets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_imageAssets);
  }

  final String? hint;
  final String? sourceNoteId;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiCardCopyWith<AnkiCard> get copyWith =>
      _$AnkiCardCopyWithImpl<AnkiCard>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AnkiCardToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiCard &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.front, front) || other.front == front) &&
            (identical(other.back, back) || other.back == back) &&
            const DeepCollectionEquality()
                .equals(other._audioAssets, _audioAssets) &&
            const DeepCollectionEquality()
                .equals(other._imageAssets, _imageAssets) &&
            (identical(other.hint, hint) || other.hint == hint) &&
            (identical(other.sourceNoteId, sourceNoteId) ||
                other.sourceNoteId == sourceNoteId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      front,
      back,
      const DeepCollectionEquality().hash(_audioAssets),
      const DeepCollectionEquality().hash(_imageAssets),
      hint,
      sourceNoteId);

  @override
  String toString() {
    return 'Interaction.ankiCard(id: $id, front: $front, back: $back, audioAssets: $audioAssets, imageAssets: $imageAssets, hint: $hint, sourceNoteId: $sourceNoteId)';
  }
}

/// @nodoc
abstract mixin class $AnkiCardCopyWith<$Res>
    implements $InteractionCopyWith<$Res> {
  factory $AnkiCardCopyWith(AnkiCard value, $Res Function(AnkiCard) _then) =
      _$AnkiCardCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String front,
      String back,
      List<String> audioAssets,
      List<String> imageAssets,
      String? hint,
      String? sourceNoteId});
}

/// @nodoc
class _$AnkiCardCopyWithImpl<$Res> implements $AnkiCardCopyWith<$Res> {
  _$AnkiCardCopyWithImpl(this._self, this._then);

  final AnkiCard _self;
  final $Res Function(AnkiCard) _then;

  /// Create a copy of Interaction
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? front = null,
    Object? back = null,
    Object? audioAssets = null,
    Object? imageAssets = null,
    Object? hint = freezed,
    Object? sourceNoteId = freezed,
  }) {
    return _then(AnkiCard(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      front: null == front
          ? _self.front
          : front // ignore: cast_nullable_to_non_nullable
              as String,
      back: null == back
          ? _self.back
          : back // ignore: cast_nullable_to_non_nullable
              as String,
      audioAssets: null == audioAssets
          ? _self._audioAssets
          : audioAssets // ignore: cast_nullable_to_non_nullable
              as List<String>,
      imageAssets: null == imageAssets
          ? _self._imageAssets
          : imageAssets // ignore: cast_nullable_to_non_nullable
              as List<String>,
      hint: freezed == hint
          ? _self.hint
          : hint // ignore: cast_nullable_to_non_nullable
              as String?,
      sourceNoteId: freezed == sourceNoteId
          ? _self.sourceNoteId
          : sourceNoteId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on
