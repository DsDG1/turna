// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'srs_word.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SrsWord {
  String get wordId;
  DateTime get dueAt;
  int get intervalDays;
  double get ease;
  int get reps;
  int get lapses;
  bool get isLeech;

  /// Imported scheduling states that Anki intentionally keeps out of the
  /// ordinary due queue. They are explicit instead of being mislabelled as
  /// leeches, so the original state can be restored or inspected later.
  bool get isSuspended;
  bool get isBuried;
  SrsItemType get type;

  /// Wall-clock time of the most recent review (null for never-reviewed
  /// cards). Used with [stability] for \(R(t)\) without a DB join.
  DateTime? get lastReviewedAt;

  /// FSRS memory stability \(S\) (days until predicted R ≈ 90%). Null until
  /// first FSRS review or SM-2→FSRS migration seed.
  double? get stability;

  /// FSRS difficulty \(D\) in \[1, 10\]. Null until seeded.
  double? get difficulty;

  /// FSRS learning state value: 1=learning, 2=review, 3=relearning.
  int get fsrsState;

  /// FSRS learning/relearning step index (null when in pure review state).
  int? get learningStep;

  /// Create a copy of SrsWord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SrsWordCopyWith<SrsWord> get copyWith =>
      _$SrsWordCopyWithImpl<SrsWord>(this as SrsWord, _$identity);

  /// Serializes this SrsWord to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SrsWord &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.dueAt, dueAt) || other.dueAt == dueAt) &&
            (identical(other.intervalDays, intervalDays) ||
                other.intervalDays == intervalDays) &&
            (identical(other.ease, ease) || other.ease == ease) &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.lapses, lapses) || other.lapses == lapses) &&
            (identical(other.isLeech, isLeech) || other.isLeech == isLeech) &&
            (identical(other.isSuspended, isSuspended) ||
                other.isSuspended == isSuspended) &&
            (identical(other.isBuried, isBuried) ||
                other.isBuried == isBuried) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.lastReviewedAt, lastReviewedAt) ||
                other.lastReviewedAt == lastReviewedAt) &&
            (identical(other.stability, stability) ||
                other.stability == stability) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            (identical(other.fsrsState, fsrsState) ||
                other.fsrsState == fsrsState) &&
            (identical(other.learningStep, learningStep) ||
                other.learningStep == learningStep));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      wordId,
      dueAt,
      intervalDays,
      ease,
      reps,
      lapses,
      isLeech,
      isSuspended,
      isBuried,
      type,
      lastReviewedAt,
      stability,
      difficulty,
      fsrsState,
      learningStep);

  @override
  String toString() {
    return 'SrsWord(wordId: $wordId, dueAt: $dueAt, intervalDays: $intervalDays, ease: $ease, reps: $reps, lapses: $lapses, isLeech: $isLeech, isSuspended: $isSuspended, isBuried: $isBuried, type: $type, lastReviewedAt: $lastReviewedAt, stability: $stability, difficulty: $difficulty, fsrsState: $fsrsState, learningStep: $learningStep)';
  }
}

/// @nodoc
abstract mixin class $SrsWordCopyWith<$Res> {
  factory $SrsWordCopyWith(SrsWord value, $Res Function(SrsWord) _then) =
      _$SrsWordCopyWithImpl;
  @useResult
  $Res call(
      {String wordId,
      DateTime dueAt,
      int intervalDays,
      double ease,
      int reps,
      int lapses,
      bool isLeech,
      bool isSuspended,
      bool isBuried,
      SrsItemType type,
      DateTime? lastReviewedAt,
      double? stability,
      double? difficulty,
      int fsrsState,
      int? learningStep});
}

/// @nodoc
class _$SrsWordCopyWithImpl<$Res> implements $SrsWordCopyWith<$Res> {
  _$SrsWordCopyWithImpl(this._self, this._then);

  final SrsWord _self;
  final $Res Function(SrsWord) _then;

  /// Create a copy of SrsWord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? wordId = null,
    Object? dueAt = null,
    Object? intervalDays = null,
    Object? ease = null,
    Object? reps = null,
    Object? lapses = null,
    Object? isLeech = null,
    Object? isSuspended = null,
    Object? isBuried = null,
    Object? type = null,
    Object? lastReviewedAt = freezed,
    Object? stability = freezed,
    Object? difficulty = freezed,
    Object? fsrsState = null,
    Object? learningStep = freezed,
  }) {
    return _then(_self.copyWith(
      wordId: null == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      dueAt: null == dueAt
          ? _self.dueAt
          : dueAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      intervalDays: null == intervalDays
          ? _self.intervalDays
          : intervalDays // ignore: cast_nullable_to_non_nullable
              as int,
      ease: null == ease
          ? _self.ease
          : ease // ignore: cast_nullable_to_non_nullable
              as double,
      reps: null == reps
          ? _self.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      lapses: null == lapses
          ? _self.lapses
          : lapses // ignore: cast_nullable_to_non_nullable
              as int,
      isLeech: null == isLeech
          ? _self.isLeech
          : isLeech // ignore: cast_nullable_to_non_nullable
              as bool,
      isSuspended: null == isSuspended
          ? _self.isSuspended
          : isSuspended // ignore: cast_nullable_to_non_nullable
              as bool,
      isBuried: null == isBuried
          ? _self.isBuried
          : isBuried // ignore: cast_nullable_to_non_nullable
              as bool,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as SrsItemType,
      lastReviewedAt: freezed == lastReviewedAt
          ? _self.lastReviewedAt
          : lastReviewedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      stability: freezed == stability
          ? _self.stability
          : stability // ignore: cast_nullable_to_non_nullable
              as double?,
      difficulty: freezed == difficulty
          ? _self.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as double?,
      fsrsState: null == fsrsState
          ? _self.fsrsState
          : fsrsState // ignore: cast_nullable_to_non_nullable
              as int,
      learningStep: freezed == learningStep
          ? _self.learningStep
          : learningStep // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// Adds pattern-matching-related methods to [SrsWord].
extension SrsWordPatterns on SrsWord {
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
    TResult Function(_SrsWord value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SrsWord() when $default != null:
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
    TResult Function(_SrsWord value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SrsWord():
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
    TResult? Function(_SrsWord value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SrsWord() when $default != null:
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
            String wordId,
            DateTime dueAt,
            int intervalDays,
            double ease,
            int reps,
            int lapses,
            bool isLeech,
            bool isSuspended,
            bool isBuried,
            SrsItemType type,
            DateTime? lastReviewedAt,
            double? stability,
            double? difficulty,
            int fsrsState,
            int? learningStep)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SrsWord() when $default != null:
        return $default(
            _that.wordId,
            _that.dueAt,
            _that.intervalDays,
            _that.ease,
            _that.reps,
            _that.lapses,
            _that.isLeech,
            _that.isSuspended,
            _that.isBuried,
            _that.type,
            _that.lastReviewedAt,
            _that.stability,
            _that.difficulty,
            _that.fsrsState,
            _that.learningStep);
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
            String wordId,
            DateTime dueAt,
            int intervalDays,
            double ease,
            int reps,
            int lapses,
            bool isLeech,
            bool isSuspended,
            bool isBuried,
            SrsItemType type,
            DateTime? lastReviewedAt,
            double? stability,
            double? difficulty,
            int fsrsState,
            int? learningStep)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SrsWord():
        return $default(
            _that.wordId,
            _that.dueAt,
            _that.intervalDays,
            _that.ease,
            _that.reps,
            _that.lapses,
            _that.isLeech,
            _that.isSuspended,
            _that.isBuried,
            _that.type,
            _that.lastReviewedAt,
            _that.stability,
            _that.difficulty,
            _that.fsrsState,
            _that.learningStep);
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
            String wordId,
            DateTime dueAt,
            int intervalDays,
            double ease,
            int reps,
            int lapses,
            bool isLeech,
            bool isSuspended,
            bool isBuried,
            SrsItemType type,
            DateTime? lastReviewedAt,
            double? stability,
            double? difficulty,
            int fsrsState,
            int? learningStep)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SrsWord() when $default != null:
        return $default(
            _that.wordId,
            _that.dueAt,
            _that.intervalDays,
            _that.ease,
            _that.reps,
            _that.lapses,
            _that.isLeech,
            _that.isSuspended,
            _that.isBuried,
            _that.type,
            _that.lastReviewedAt,
            _that.stability,
            _that.difficulty,
            _that.fsrsState,
            _that.learningStep);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _SrsWord implements SrsWord {
  const _SrsWord(
      {required this.wordId,
      required this.dueAt,
      this.intervalDays = 1,
      this.ease = 2.5,
      this.reps = 0,
      this.lapses = 0,
      this.isLeech = false,
      this.isSuspended = false,
      this.isBuried = false,
      this.type = SrsItemType.word,
      this.lastReviewedAt,
      this.stability,
      this.difficulty,
      this.fsrsState = 1,
      this.learningStep});
  factory _SrsWord.fromJson(Map<String, dynamic> json) =>
      _$SrsWordFromJson(json);

  @override
  final String wordId;
  @override
  final DateTime dueAt;
  @override
  @JsonKey()
  final int intervalDays;
  @override
  @JsonKey()
  final double ease;
  @override
  @JsonKey()
  final int reps;
  @override
  @JsonKey()
  final int lapses;
  @override
  @JsonKey()
  final bool isLeech;

  /// Imported scheduling states that Anki intentionally keeps out of the
  /// ordinary due queue. They are explicit instead of being mislabelled as
  /// leeches, so the original state can be restored or inspected later.
  @override
  @JsonKey()
  final bool isSuspended;
  @override
  @JsonKey()
  final bool isBuried;
  @override
  @JsonKey()
  final SrsItemType type;

  /// Wall-clock time of the most recent review (null for never-reviewed
  /// cards). Used with [stability] for \(R(t)\) without a DB join.
  @override
  final DateTime? lastReviewedAt;

  /// FSRS memory stability \(S\) (days until predicted R ≈ 90%). Null until
  /// first FSRS review or SM-2→FSRS migration seed.
  @override
  final double? stability;

  /// FSRS difficulty \(D\) in \[1, 10\]. Null until seeded.
  @override
  final double? difficulty;

  /// FSRS learning state value: 1=learning, 2=review, 3=relearning.
  @override
  @JsonKey()
  final int fsrsState;

  /// FSRS learning/relearning step index (null when in pure review state).
  @override
  final int? learningStep;

  /// Create a copy of SrsWord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SrsWordCopyWith<_SrsWord> get copyWith =>
      __$SrsWordCopyWithImpl<_SrsWord>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$SrsWordToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SrsWord &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.dueAt, dueAt) || other.dueAt == dueAt) &&
            (identical(other.intervalDays, intervalDays) ||
                other.intervalDays == intervalDays) &&
            (identical(other.ease, ease) || other.ease == ease) &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.lapses, lapses) || other.lapses == lapses) &&
            (identical(other.isLeech, isLeech) || other.isLeech == isLeech) &&
            (identical(other.isSuspended, isSuspended) ||
                other.isSuspended == isSuspended) &&
            (identical(other.isBuried, isBuried) ||
                other.isBuried == isBuried) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.lastReviewedAt, lastReviewedAt) ||
                other.lastReviewedAt == lastReviewedAt) &&
            (identical(other.stability, stability) ||
                other.stability == stability) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            (identical(other.fsrsState, fsrsState) ||
                other.fsrsState == fsrsState) &&
            (identical(other.learningStep, learningStep) ||
                other.learningStep == learningStep));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      wordId,
      dueAt,
      intervalDays,
      ease,
      reps,
      lapses,
      isLeech,
      isSuspended,
      isBuried,
      type,
      lastReviewedAt,
      stability,
      difficulty,
      fsrsState,
      learningStep);

  @override
  String toString() {
    return 'SrsWord(wordId: $wordId, dueAt: $dueAt, intervalDays: $intervalDays, ease: $ease, reps: $reps, lapses: $lapses, isLeech: $isLeech, isSuspended: $isSuspended, isBuried: $isBuried, type: $type, lastReviewedAt: $lastReviewedAt, stability: $stability, difficulty: $difficulty, fsrsState: $fsrsState, learningStep: $learningStep)';
  }
}

/// @nodoc
abstract mixin class _$SrsWordCopyWith<$Res> implements $SrsWordCopyWith<$Res> {
  factory _$SrsWordCopyWith(_SrsWord value, $Res Function(_SrsWord) _then) =
      __$SrsWordCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String wordId,
      DateTime dueAt,
      int intervalDays,
      double ease,
      int reps,
      int lapses,
      bool isLeech,
      bool isSuspended,
      bool isBuried,
      SrsItemType type,
      DateTime? lastReviewedAt,
      double? stability,
      double? difficulty,
      int fsrsState,
      int? learningStep});
}

/// @nodoc
class __$SrsWordCopyWithImpl<$Res> implements _$SrsWordCopyWith<$Res> {
  __$SrsWordCopyWithImpl(this._self, this._then);

  final _SrsWord _self;
  final $Res Function(_SrsWord) _then;

  /// Create a copy of SrsWord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? wordId = null,
    Object? dueAt = null,
    Object? intervalDays = null,
    Object? ease = null,
    Object? reps = null,
    Object? lapses = null,
    Object? isLeech = null,
    Object? isSuspended = null,
    Object? isBuried = null,
    Object? type = null,
    Object? lastReviewedAt = freezed,
    Object? stability = freezed,
    Object? difficulty = freezed,
    Object? fsrsState = null,
    Object? learningStep = freezed,
  }) {
    return _then(_SrsWord(
      wordId: null == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      dueAt: null == dueAt
          ? _self.dueAt
          : dueAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      intervalDays: null == intervalDays
          ? _self.intervalDays
          : intervalDays // ignore: cast_nullable_to_non_nullable
              as int,
      ease: null == ease
          ? _self.ease
          : ease // ignore: cast_nullable_to_non_nullable
              as double,
      reps: null == reps
          ? _self.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      lapses: null == lapses
          ? _self.lapses
          : lapses // ignore: cast_nullable_to_non_nullable
              as int,
      isLeech: null == isLeech
          ? _self.isLeech
          : isLeech // ignore: cast_nullable_to_non_nullable
              as bool,
      isSuspended: null == isSuspended
          ? _self.isSuspended
          : isSuspended // ignore: cast_nullable_to_non_nullable
              as bool,
      isBuried: null == isBuried
          ? _self.isBuried
          : isBuried // ignore: cast_nullable_to_non_nullable
              as bool,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as SrsItemType,
      lastReviewedAt: freezed == lastReviewedAt
          ? _self.lastReviewedAt
          : lastReviewedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      stability: freezed == stability
          ? _self.stability
          : stability // ignore: cast_nullable_to_non_nullable
              as double?,
      difficulty: freezed == difficulty
          ? _self.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as double?,
      fsrsState: null == fsrsState
          ? _self.fsrsState
          : fsrsState // ignore: cast_nullable_to_non_nullable
              as int,
      learningStep: freezed == learningStep
          ? _self.learningStep
          : learningStep // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

// dart format on
