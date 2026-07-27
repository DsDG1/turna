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
  SrsItemType get type;

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
            (identical(other.type, type) || other.type == type));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, wordId, dueAt, intervalDays,
      ease, reps, lapses, isLeech, type);

  @override
  String toString() {
    return 'SrsWord(wordId: $wordId, dueAt: $dueAt, intervalDays: $intervalDays, ease: $ease, reps: $reps, lapses: $lapses, isLeech: $isLeech, type: $type)';
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
      SrsItemType type});
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
    Object? type = null,
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
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as SrsItemType,
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
    TResult Function(String wordId, DateTime dueAt, int intervalDays,
            double ease, int reps, int lapses, bool isLeech, SrsItemType type)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SrsWord() when $default != null:
        return $default(_that.wordId, _that.dueAt, _that.intervalDays,
            _that.ease, _that.reps, _that.lapses, _that.isLeech, _that.type);
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
    TResult Function(String wordId, DateTime dueAt, int intervalDays,
            double ease, int reps, int lapses, bool isLeech, SrsItemType type)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SrsWord():
        return $default(_that.wordId, _that.dueAt, _that.intervalDays,
            _that.ease, _that.reps, _that.lapses, _that.isLeech, _that.type);
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
    TResult? Function(String wordId, DateTime dueAt, int intervalDays,
            double ease, int reps, int lapses, bool isLeech, SrsItemType type)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SrsWord() when $default != null:
        return $default(_that.wordId, _that.dueAt, _that.intervalDays,
            _that.ease, _that.reps, _that.lapses, _that.isLeech, _that.type);
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
      this.type = SrsItemType.word});
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
  @override
  @JsonKey()
  final SrsItemType type;

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
            (identical(other.type, type) || other.type == type));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, wordId, dueAt, intervalDays,
      ease, reps, lapses, isLeech, type);

  @override
  String toString() {
    return 'SrsWord(wordId: $wordId, dueAt: $dueAt, intervalDays: $intervalDays, ease: $ease, reps: $reps, lapses: $lapses, isLeech: $isLeech, type: $type)';
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
      SrsItemType type});
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
    Object? type = null,
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
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as SrsItemType,
    ));
  }
}

// dart format on
