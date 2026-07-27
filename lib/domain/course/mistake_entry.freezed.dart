// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mistake_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MistakeEntry {
  String get id;

  /// The lesson this mistake happened in.
  String get lessonId;

  /// The stage id within the lesson (or sub-lesson id if applicable).
  String get stageId;

  /// The interaction id within the stage.
  String get interactionId;

  /// Related word id, if this mistake was tied to a vocabulary word.
  String? get wordId;

  /// Related expression id, if this mistake was tied to an expression.
  String? get expressionId;

  /// Related grammar point id for cross-routing into grammar review.
  String? get grammarPointId;

  /// A snapshot of the interaction that produced this mistake, used to
  /// recreate it for practice.
  @JsonKey(
      fromJson: _interactionSnapshotFromJson,
      toJson: _interactionSnapshotToJson)
  Interaction? get interactionSnapshot;

  /// What the user answered.
  String get userAnswer;

  /// The correct answer.
  String get correctAnswer;

  /// When the mistake was made.
  DateTime get timestamp;

  /// How many times the user has rewritten this mistake correctly.
  int get rewriteCount;

  /// Create a copy of MistakeEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $MistakeEntryCopyWith<MistakeEntry> get copyWith =>
      _$MistakeEntryCopyWithImpl<MistakeEntry>(
          this as MistakeEntry, _$identity);

  /// Serializes this MistakeEntry to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is MistakeEntry &&
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

  @JsonKey(includeFromJson: false, includeToJson: false)
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

  @override
  String toString() {
    return 'MistakeEntry(id: $id, lessonId: $lessonId, stageId: $stageId, interactionId: $interactionId, wordId: $wordId, expressionId: $expressionId, grammarPointId: $grammarPointId, interactionSnapshot: $interactionSnapshot, userAnswer: $userAnswer, correctAnswer: $correctAnswer, timestamp: $timestamp, rewriteCount: $rewriteCount)';
  }
}

/// @nodoc
abstract mixin class $MistakeEntryCopyWith<$Res> {
  factory $MistakeEntryCopyWith(
          MistakeEntry value, $Res Function(MistakeEntry) _then) =
      _$MistakeEntryCopyWithImpl;
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
class _$MistakeEntryCopyWithImpl<$Res> implements $MistakeEntryCopyWith<$Res> {
  _$MistakeEntryCopyWithImpl(this._self, this._then);

  final MistakeEntry _self;
  final $Res Function(MistakeEntry) _then;

  /// Create a copy of MistakeEntry
  /// with the given fields replaced by the non-null parameter values.
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
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _self.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      stageId: null == stageId
          ? _self.stageId
          : stageId // ignore: cast_nullable_to_non_nullable
              as String,
      interactionId: null == interactionId
          ? _self.interactionId
          : interactionId // ignore: cast_nullable_to_non_nullable
              as String,
      wordId: freezed == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String?,
      expressionId: freezed == expressionId
          ? _self.expressionId
          : expressionId // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
      interactionSnapshot: freezed == interactionSnapshot
          ? _self.interactionSnapshot
          : interactionSnapshot // ignore: cast_nullable_to_non_nullable
              as Interaction?,
      userAnswer: null == userAnswer
          ? _self.userAnswer
          : userAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      correctAnswer: null == correctAnswer
          ? _self.correctAnswer
          : correctAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      rewriteCount: null == rewriteCount
          ? _self.rewriteCount
          : rewriteCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }

  /// Create a copy of MistakeEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $InteractionCopyWith<$Res>? get interactionSnapshot {
    if (_self.interactionSnapshot == null) {
      return null;
    }

    return $InteractionCopyWith<$Res>(_self.interactionSnapshot!, (value) {
      return _then(_self.copyWith(interactionSnapshot: value));
    });
  }
}

/// Adds pattern-matching-related methods to [MistakeEntry].
extension MistakeEntryPatterns on MistakeEntry {
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
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_MistakeEntry value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _MistakeEntry() when $default != null:
        return $default(_that);
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
  TResult map<TResult extends Object?>(
    TResult Function(_MistakeEntry value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MistakeEntry():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
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
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_MistakeEntry value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MistakeEntry() when $default != null:
        return $default(_that);
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
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String id,
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
            int rewriteCount)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _MistakeEntry() when $default != null:
        return $default(
            _that.id,
            _that.lessonId,
            _that.stageId,
            _that.interactionId,
            _that.wordId,
            _that.expressionId,
            _that.grammarPointId,
            _that.interactionSnapshot,
            _that.userAnswer,
            _that.correctAnswer,
            _that.timestamp,
            _that.rewriteCount);
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
  TResult when<TResult extends Object?>(
    TResult Function(
            String id,
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
            int rewriteCount)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MistakeEntry():
        return $default(
            _that.id,
            _that.lessonId,
            _that.stageId,
            _that.interactionId,
            _that.wordId,
            _that.expressionId,
            _that.grammarPointId,
            _that.interactionSnapshot,
            _that.userAnswer,
            _that.correctAnswer,
            _that.timestamp,
            _that.rewriteCount);
      case _:
        throw StateError('Unexpected subclass');
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
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String id,
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
            int rewriteCount)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _MistakeEntry() when $default != null:
        return $default(
            _that.id,
            _that.lessonId,
            _that.stageId,
            _that.interactionId,
            _that.wordId,
            _that.expressionId,
            _that.grammarPointId,
            _that.interactionSnapshot,
            _that.userAnswer,
            _that.correctAnswer,
            _that.timestamp,
            _that.rewriteCount);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _MistakeEntry implements MistakeEntry {
  const _MistakeEntry(
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
  factory _MistakeEntry.fromJson(Map<String, dynamic> json) =>
      _$MistakeEntryFromJson(json);

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

  /// Create a copy of MistakeEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$MistakeEntryCopyWith<_MistakeEntry> get copyWith =>
      __$MistakeEntryCopyWithImpl<_MistakeEntry>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$MistakeEntryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _MistakeEntry &&
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

  @JsonKey(includeFromJson: false, includeToJson: false)
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

  @override
  String toString() {
    return 'MistakeEntry(id: $id, lessonId: $lessonId, stageId: $stageId, interactionId: $interactionId, wordId: $wordId, expressionId: $expressionId, grammarPointId: $grammarPointId, interactionSnapshot: $interactionSnapshot, userAnswer: $userAnswer, correctAnswer: $correctAnswer, timestamp: $timestamp, rewriteCount: $rewriteCount)';
  }
}

/// @nodoc
abstract mixin class _$MistakeEntryCopyWith<$Res>
    implements $MistakeEntryCopyWith<$Res> {
  factory _$MistakeEntryCopyWith(
          _MistakeEntry value, $Res Function(_MistakeEntry) _then) =
      __$MistakeEntryCopyWithImpl;
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
class __$MistakeEntryCopyWithImpl<$Res>
    implements _$MistakeEntryCopyWith<$Res> {
  __$MistakeEntryCopyWithImpl(this._self, this._then);

  final _MistakeEntry _self;
  final $Res Function(_MistakeEntry) _then;

  /// Create a copy of MistakeEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
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
    return _then(_MistakeEntry(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _self.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      stageId: null == stageId
          ? _self.stageId
          : stageId // ignore: cast_nullable_to_non_nullable
              as String,
      interactionId: null == interactionId
          ? _self.interactionId
          : interactionId // ignore: cast_nullable_to_non_nullable
              as String,
      wordId: freezed == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String?,
      expressionId: freezed == expressionId
          ? _self.expressionId
          : expressionId // ignore: cast_nullable_to_non_nullable
              as String?,
      grammarPointId: freezed == grammarPointId
          ? _self.grammarPointId
          : grammarPointId // ignore: cast_nullable_to_non_nullable
              as String?,
      interactionSnapshot: freezed == interactionSnapshot
          ? _self.interactionSnapshot
          : interactionSnapshot // ignore: cast_nullable_to_non_nullable
              as Interaction?,
      userAnswer: null == userAnswer
          ? _self.userAnswer
          : userAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      correctAnswer: null == correctAnswer
          ? _self.correctAnswer
          : correctAnswer // ignore: cast_nullable_to_non_nullable
              as String,
      timestamp: null == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      rewriteCount: null == rewriteCount
          ? _self.rewriteCount
          : rewriteCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }

  /// Create a copy of MistakeEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $InteractionCopyWith<$Res>? get interactionSnapshot {
    if (_self.interactionSnapshot == null) {
      return null;
    }

    return $InteractionCopyWith<$Res>(_self.interactionSnapshot!, (value) {
      return _then(_self.copyWith(interactionSnapshot: value));
    });
  }
}

// dart format on
