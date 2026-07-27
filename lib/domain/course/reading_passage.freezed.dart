// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reading_passage.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ReadingPassage {
  /// Passage title.
  String get title;

  /// Paragraphs of the passage.
  List<String> get paragraphs;

  /// Approximate CEFR difficulty: 1=A1, 2=A2, 3=B1, 4=B2, etc.
  int get difficulty;

  /// IDs of words introduced or highlighted in this passage.
  List<String> get linkedWordIds;

  /// IDs of expressions highlighted in this passage.
  List<String> get linkedExpressionIds;

  /// Create a copy of ReadingPassage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReadingPassageCopyWith<ReadingPassage> get copyWith =>
      _$ReadingPassageCopyWithImpl<ReadingPassage>(
          this as ReadingPassage, _$identity);

  /// Serializes this ReadingPassage to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReadingPassage &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality()
                .equals(other.paragraphs, paragraphs) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            const DeepCollectionEquality()
                .equals(other.linkedWordIds, linkedWordIds) &&
            const DeepCollectionEquality()
                .equals(other.linkedExpressionIds, linkedExpressionIds));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      title,
      const DeepCollectionEquality().hash(paragraphs),
      difficulty,
      const DeepCollectionEquality().hash(linkedWordIds),
      const DeepCollectionEquality().hash(linkedExpressionIds));

  @override
  String toString() {
    return 'ReadingPassage(title: $title, paragraphs: $paragraphs, difficulty: $difficulty, linkedWordIds: $linkedWordIds, linkedExpressionIds: $linkedExpressionIds)';
  }
}

/// @nodoc
abstract mixin class $ReadingPassageCopyWith<$Res> {
  factory $ReadingPassageCopyWith(
          ReadingPassage value, $Res Function(ReadingPassage) _then) =
      _$ReadingPassageCopyWithImpl;
  @useResult
  $Res call(
      {String title,
      List<String> paragraphs,
      int difficulty,
      List<String> linkedWordIds,
      List<String> linkedExpressionIds});
}

/// @nodoc
class _$ReadingPassageCopyWithImpl<$Res>
    implements $ReadingPassageCopyWith<$Res> {
  _$ReadingPassageCopyWithImpl(this._self, this._then);

  final ReadingPassage _self;
  final $Res Function(ReadingPassage) _then;

  /// Create a copy of ReadingPassage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? paragraphs = null,
    Object? difficulty = null,
    Object? linkedWordIds = null,
    Object? linkedExpressionIds = null,
  }) {
    return _then(_self.copyWith(
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      paragraphs: null == paragraphs
          ? _self.paragraphs
          : paragraphs // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _self.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
      linkedWordIds: null == linkedWordIds
          ? _self.linkedWordIds
          : linkedWordIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      linkedExpressionIds: null == linkedExpressionIds
          ? _self.linkedExpressionIds
          : linkedExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// Adds pattern-matching-related methods to [ReadingPassage].
extension ReadingPassagePatterns on ReadingPassage {
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
    TResult Function(_ReadingPassage value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ReadingPassage() when $default != null:
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
    TResult Function(_ReadingPassage value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReadingPassage():
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
    TResult? Function(_ReadingPassage value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReadingPassage() when $default != null:
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
    TResult Function(String title, List<String> paragraphs, int difficulty,
            List<String> linkedWordIds, List<String> linkedExpressionIds)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ReadingPassage() when $default != null:
        return $default(_that.title, _that.paragraphs, _that.difficulty,
            _that.linkedWordIds, _that.linkedExpressionIds);
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
    TResult Function(String title, List<String> paragraphs, int difficulty,
            List<String> linkedWordIds, List<String> linkedExpressionIds)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReadingPassage():
        return $default(_that.title, _that.paragraphs, _that.difficulty,
            _that.linkedWordIds, _that.linkedExpressionIds);
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
    TResult? Function(String title, List<String> paragraphs, int difficulty,
            List<String> linkedWordIds, List<String> linkedExpressionIds)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReadingPassage() when $default != null:
        return $default(_that.title, _that.paragraphs, _that.difficulty,
            _that.linkedWordIds, _that.linkedExpressionIds);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _ReadingPassage implements ReadingPassage {
  const _ReadingPassage(
      {required this.title,
      final List<String> paragraphs = const <String>[],
      this.difficulty = 1,
      final List<String> linkedWordIds = const <String>[],
      final List<String> linkedExpressionIds = const <String>[]})
      : _paragraphs = paragraphs,
        _linkedWordIds = linkedWordIds,
        _linkedExpressionIds = linkedExpressionIds;
  factory _ReadingPassage.fromJson(Map<String, dynamic> json) =>
      _$ReadingPassageFromJson(json);

  /// Passage title.
  @override
  final String title;

  /// Paragraphs of the passage.
  final List<String> _paragraphs;

  /// Paragraphs of the passage.
  @override
  @JsonKey()
  List<String> get paragraphs {
    if (_paragraphs is EqualUnmodifiableListView) return _paragraphs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_paragraphs);
  }

  /// Approximate CEFR difficulty: 1=A1, 2=A2, 3=B1, 4=B2, etc.
  @override
  @JsonKey()
  final int difficulty;

  /// IDs of words introduced or highlighted in this passage.
  final List<String> _linkedWordIds;

  /// IDs of words introduced or highlighted in this passage.
  @override
  @JsonKey()
  List<String> get linkedWordIds {
    if (_linkedWordIds is EqualUnmodifiableListView) return _linkedWordIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedWordIds);
  }

  /// IDs of expressions highlighted in this passage.
  final List<String> _linkedExpressionIds;

  /// IDs of expressions highlighted in this passage.
  @override
  @JsonKey()
  List<String> get linkedExpressionIds {
    if (_linkedExpressionIds is EqualUnmodifiableListView)
      return _linkedExpressionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedExpressionIds);
  }

  /// Create a copy of ReadingPassage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ReadingPassageCopyWith<_ReadingPassage> get copyWith =>
      __$ReadingPassageCopyWithImpl<_ReadingPassage>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ReadingPassageToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ReadingPassage &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality()
                .equals(other._paragraphs, _paragraphs) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            const DeepCollectionEquality()
                .equals(other._linkedWordIds, _linkedWordIds) &&
            const DeepCollectionEquality()
                .equals(other._linkedExpressionIds, _linkedExpressionIds));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      title,
      const DeepCollectionEquality().hash(_paragraphs),
      difficulty,
      const DeepCollectionEquality().hash(_linkedWordIds),
      const DeepCollectionEquality().hash(_linkedExpressionIds));

  @override
  String toString() {
    return 'ReadingPassage(title: $title, paragraphs: $paragraphs, difficulty: $difficulty, linkedWordIds: $linkedWordIds, linkedExpressionIds: $linkedExpressionIds)';
  }
}

/// @nodoc
abstract mixin class _$ReadingPassageCopyWith<$Res>
    implements $ReadingPassageCopyWith<$Res> {
  factory _$ReadingPassageCopyWith(
          _ReadingPassage value, $Res Function(_ReadingPassage) _then) =
      __$ReadingPassageCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String title,
      List<String> paragraphs,
      int difficulty,
      List<String> linkedWordIds,
      List<String> linkedExpressionIds});
}

/// @nodoc
class __$ReadingPassageCopyWithImpl<$Res>
    implements _$ReadingPassageCopyWith<$Res> {
  __$ReadingPassageCopyWithImpl(this._self, this._then);

  final _ReadingPassage _self;
  final $Res Function(_ReadingPassage) _then;

  /// Create a copy of ReadingPassage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? title = null,
    Object? paragraphs = null,
    Object? difficulty = null,
    Object? linkedWordIds = null,
    Object? linkedExpressionIds = null,
  }) {
    return _then(_ReadingPassage(
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      paragraphs: null == paragraphs
          ? _self._paragraphs
          : paragraphs // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _self.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
      linkedWordIds: null == linkedWordIds
          ? _self._linkedWordIds
          : linkedWordIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      linkedExpressionIds: null == linkedExpressionIds
          ? _self._linkedExpressionIds
          : linkedExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

// dart format on
