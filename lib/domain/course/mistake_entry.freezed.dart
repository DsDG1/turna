// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mistake_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MistakeEntry _$MistakeEntryFromJson(Map<String, dynamic> json) {
  return _MistakeEntry.fromJson(json);
}

/// @nodoc
mixin _$MistakeEntry {
  String get id => throw _privateConstructorUsedError;

  /// The lesson this mistake happened in.
  String get lessonId => throw _privateConstructorUsedError;

  /// The stage id within the lesson (or sub-lesson id if applicable).
  String get stageId => throw _privateConstructorUsedError;

  /// The interaction id within the stage.
  String get interactionId => throw _privateConstructorUsedError;

  /// Related word id, if this mistake was tied to a vocabulary word.
  String? get wordId => throw _privateConstructorUsedError;

  /// Related expression id, if this mistake was tied to an expression.
  String? get expressionId => throw _privateConstructorUsedError;

  /// Related grammar point id for cross-routing into grammar review.
  String? get grammarPointId => throw _privateConstructorUsedError;

  /// A snapshot of the interaction that produced this mistake, used to
  /// recreate it for practice.
  @JsonKey(
      fromJson: _interactionSnapshotFromJson,
      toJson: _interactionSnapshotToJson)
  Interaction? get interactionSnapshot => throw _privateConstructorUsedError;

  /// What the user answered.
  String get userAnswer => throw _privateConstructorUsedError;

  /// The correct answer.
  String get correctAnswer => throw _privateConstructorUsedError;

  /// When the mistake was made.
  DateTime get timestamp => throw _privateConstructorUsedError;

  /// How many times the user has rewritten this mistake correctly.
  int get rewriteCount => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $MistakeEntryCopyWith<MistakeEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MistakeEntryCopyWith<$Res> {
  factory $MistakeEntryCopyWith(
          MistakeEntry value, $Res Function(MistakeEntry) then) =
      _$MistakeEntryCopyWithImpl<$Res, MistakeEntry>;
  @useResult
  $Res call(
      {String id,
      String lessonId,
      String stageId,
      String interactionId,
      String? wordId,
      String? expressionId,
      String? grammarPointId,
      @JsonKey(
          fromJson: _interactionSnapshotFromJson,
          toJson: _interactionSnapshotToJson)
      Interaction? interactionSnapshot,
      String userAnswer,
      String correctAnswer,
      DateTime timestamp,
      int rewriteCount});

  $InteractionCopyWith<$Res>? get interactionSnapshot;
}

/// @nodoc
class _$MistakeEntryCopyWithImpl<$Res, $Val extends MistakeEntry>
    implements $MistakeEntryCopyWith<$Res> {
  _$MistakeEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? lessonId = null,
    Object? stageId = null,
    Object? interactionId = null,
    Object? wordId = freezed,
    Object? expressionId = freezed,
    Object? grammarPointId = freezed,
    Object? interactionSnapshot = freezed,
    Object? userAnswer = null,
    Object? correctAnswer = null,
    Object? timestamp = null,
    Object? rewriteCount = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _value.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      stageId: null == stageId
          ? _value.stageId
          : stageId // ignore: cast_nullable_to_non_nullable
              as String,
      interactionId: null == interactionId
          ? _value.interactionId
          : interactionId // ignore: cast_nullable_to_non_nullable
              as String,
      wordId: freezed == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String?,
      expressionId: freezed == expressionId
          ? _value.expressionId
          : expressionId // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
      interactionSnapshot: freezed == interactionSnapshot
          ? _value.interactionSnapshot
          : interactionSnapshot // ignore: cast_nullable_to_non_nullable
              as Interaction?,
      userAnswer: null == userAnswer
          ? _value.userAnswer
          : userAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      correctAnswer: null == correctAnswer
          ? _value.correctAnswer
          : correctAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      rewriteCount: null == rewriteCount
          ? _value.rewriteCount
          : rewriteCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $InteractionCopyWith<$Res>? get interactionSnapshot {
    if (_value.interactionSnapshot == null) {
      return null;
    }

    return $InteractionCopyWith<$Res>(_value.interactionSnapshot!, (value) {
      return _then(_value.copyWith(interactionSnapshot: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$MistakeEntryImplCopyWith<$Res>
    implements $MistakeEntryCopyWith<$Res> {
  factory _$$MistakeEntryImplCopyWith(
          _$MistakeEntryImpl value, $Res Function(_$MistakeEntryImpl) then) =
      __$$MistakeEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String lessonId,
      String stageId,
      String interactionId,
      String? wordId,
      String? expressionId,
      String? grammarPointId,
      @JsonKey(
          fromJson: _interactionSnapshotFromJson,
          toJson: _interactionSnapshotToJson)
      Interaction? interactionSnapshot,
      String userAnswer,
      String correctAnswer,
      DateTime timestamp,
      int rewriteCount});

  @override
  $InteractionCopyWith<$Res>? get interactionSnapshot;
}

/// @nodoc
class __$$MistakeEntryImplCopyWithImpl<$Res>
    extends _$MistakeEntryCopyWithImpl<$Res, _$MistakeEntryImpl>
    implements _$$MistakeEntryImplCopyWith<$Res> {
  __$$MistakeEntryImplCopyWithImpl(
      _$MistakeEntryImpl _value, $Res Function(_$MistakeEntryImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? lessonId = null,
    Object? stageId = null,
    Object? interactionId = null,
    Object? wordId = freezed,
    Object? expressionId = freezed,
    Object? grammarPointId = freezed,
    Object? interactionSnapshot = freezed,
    Object? userAnswer = null,
    Object? correctAnswer = null,
    Object? timestamp = null,
    Object? rewriteCount = null,
  }) {
    return _then(_$MistakeEntryImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _value.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      stageId: null == stageId
          ? _value.stageId
          : stageId // ignore: cast_nullable_to_non_nullable
              as String,
      interactionId: null == interactionId
          ? _value.interactionId
          : interactionId // ignore: cast_nullable_to_non_nullable
              as String,
      wordId: freezed == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String?,
      expressionId: freezed == expressionId
          ? _value.expressionId
          : expressionId // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _value.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
      interactionSnapshot: freezed == interactionSnapshot
          ? _value.interactionSnapshot
          : interactionSnapshot // ignore: cast_nullable_to_non_nullable
              as Interaction?,
      userAnswer: null == userAnswer
          ? _value.userAnswer
          : userAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      correctAnswer: null == correctAnswer
          ? _value.correctAnswer
          : correctAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      rewriteCount: null == rewriteCount
          ? _value.rewriteCount
          : rewriteCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MistakeEntryImpl implements _MistakeEntry {
  const _$MistakeEntryImpl(
      {required this.id,
      required this.lessonId,
      required this.stageId,
      required this.interactionId,
      this.wordId,
      this.expressionId,
      this.grammarPointId,
      @JsonKey(
          fromJson: _interactionSnapshotFromJson,
          toJson: _interactionSnapshotToJson)
      this.interactionSnapshot,
      this.userAnswer = '',
      this.correctAnswer = '',
      required this.timestamp,
      this.rewriteCount = 0});

  factory _$MistakeEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$MistakeEntryImplFromJson(json);

  @override
  final String id;

  /// The lesson this mistake happened in.
  @override
  final String lessonId;

  /// The stage id within the lesson (or sub-lesson id if applicable).
  @override
  final String stageId;

  /// The interaction id within the stage.
  @override
  final String interactionId;

  /// Related word id, if this mistake was tied to a vocabulary word.
  @override
  final String? wordId;

  /// Related expression id, if this mistake was tied to an expression.
  @override
  final String? expressionId;

  /// Related grammar point id for cross-routing into grammar review.
  @override
  final String? grammarPointId;

  /// A snapshot of the interaction that produced this mistake, used to
  /// recreate it for practice.
  @override
  @JsonKey(
      fromJson: _interactionSnapshotFromJson,
      toJson: _interactionSnapshotToJson)
  final Interaction? interactionSnapshot;

  /// What the user answered.
  @override
  @JsonKey()
  final String userAnswer;

  /// The correct answer.
  @override
  @JsonKey()
  final String correctAnswer;

  /// When the mistake was made.
  @override
  final DateTime timestamp;

  /// How many times the user has rewritten this mistake correctly.
  @override
  @JsonKey()
  final int rewriteCount;

  @override
  String toString() {
    return 'MistakeEntry(id: $id, lessonId: $lessonId, stageId: $stageId, interactionId: $interactionId, wordId: $wordId, expressionId: $expressionId, grammarPointId: $grammarPointId, interactionSnapshot: $interactionSnapshot, userAnswer: $userAnswer, correctAnswer: $correctAnswer, timestamp: $timestamp, rewriteCount: $rewriteCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MistakeEntryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.lessonId, lessonId) ||
                other.lessonId == lessonId) &&
            (identical(other.stageId, stageId) || other.stageId == stageId) &&
            (identical(other.interactionId, interactionId) ||
                other.interactionId == interactionId) &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.expressionId, expressionId) ||
                other.expressionId == expressionId) &&
            (identical(other.grammarPointId, grammarPointId) ||
                other.grammarPointId == grammarPointId) &&
            (identical(other.interactionSnapshot, interactionSnapshot) ||
                other.interactionSnapshot == interactionSnapshot) &&
            (identical(other.userAnswer, userAnswer) ||
                other.userAnswer == userAnswer) &&
            (identical(other.correctAnswer, correctAnswer) ||
                other.correctAnswer == correctAnswer) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.rewriteCount, rewriteCount) ||
                other.rewriteCount == rewriteCount));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      lessonId,
      stageId,
      interactionId,
      wordId,
      expressionId,
      grammarPointId,
      interactionSnapshot,
      userAnswer,
      correctAnswer,
      timestamp,
      rewriteCount);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MistakeEntryImplCopyWith<_$MistakeEntryImpl> get copyWith =>
      __$$MistakeEntryImplCopyWithImpl<_$MistakeEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MistakeEntryImplToJson(
      this,
    );
  }
}

abstract class _MistakeEntry implements MistakeEntry {
  const factory _MistakeEntry(
      {required final String id,
      required final String lessonId,
      required final String stageId,
      required final String interactionId,
      final String? wordId,
      final String? expressionId,
      final String? grammarPointId,
      @JsonKey(
          fromJson: _interactionSnapshotFromJson,
          toJson: _interactionSnapshotToJson)
      final Interaction? interactionSnapshot,
      final String userAnswer,
      final String correctAnswer,
      required final DateTime timestamp,
      final int rewriteCount}) = _$MistakeEntryImpl;

  factory _MistakeEntry.fromJson(Map<String, dynamic> json) =
      _$MistakeEntryImpl.fromJson;

  @override
  String get id;
  @override

  /// The lesson this mistake happened in.
  String get lessonId;
  @override

  /// The stage id within the lesson (or sub-lesson id if applicable).
  String get stageId;
  @override

  /// The interaction id within the stage.
  String get interactionId;
  @override

  /// Related word id, if this mistake was tied to a vocabulary word.
  String? get wordId;
  @override

  /// Related expression id, if this mistake was tied to an expression.
  String? get expressionId;
  @override

  /// Related grammar point id for cross-routing into grammar review.
  String? get grammarPointId;
  @override

  /// A snapshot of the interaction that produced this mistake, used to
  /// recreate it for practice.
  @JsonKey(
      fromJson: _interactionSnapshotFromJson,
      toJson: _interactionSnapshotToJson)
  Interaction? get interactionSnapshot;
  @override

  /// What the user answered.
  String get userAnswer;
  @override

  /// The correct answer.
  String get correctAnswer;
  @override

  /// When the mistake was made.
  DateTime get timestamp;
  @override

  /// How many times the user has rewritten this mistake correctly.
  int get rewriteCount;
  @override
  @JsonKey(ignore: true)
  _$$MistakeEntryImplCopyWith<_$MistakeEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
