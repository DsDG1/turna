// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'grammar_point.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GrammarPoint {
  String get id;

  /// Short title, e.g. "Present tense -a verb conjugation".
  String get title;

  /// Full explanation shown in lesson and review.
  String get explanation;

  /// IDs of expressions that exemplify this grammar point.
  List<String> get exampleExpressionIds;

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  List<String> get exampleSentenceIds;

  /// Short practice drills for the grammar-review screen.
  @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
  List<Interaction> get practiceItems;

  /// Create a copy of GrammarPoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GrammarPointCopyWith<GrammarPoint> get copyWith =>
      _$GrammarPointCopyWithImpl<GrammarPoint>(
          this as GrammarPoint, _$identity);

  /// Serializes this GrammarPoint to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GrammarPoint &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.explanation, explanation) ||
                other.explanation == explanation) &&
            const DeepCollectionEquality()
                .equals(other.exampleExpressionIds, exampleExpressionIds) &&
            const DeepCollectionEquality()
                .equals(other.exampleSentenceIds, exampleSentenceIds) &&
            const DeepCollectionEquality()
                .equals(other.practiceItems, practiceItems));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      explanation,
      const DeepCollectionEquality().hash(exampleExpressionIds),
      const DeepCollectionEquality().hash(exampleSentenceIds),
      const DeepCollectionEquality().hash(practiceItems));

  @override
  String toString() {
    return 'GrammarPoint(id: $id, title: $title, explanation: $explanation, exampleExpressionIds: $exampleExpressionIds, exampleSentenceIds: $exampleSentenceIds, practiceItems: $practiceItems)';
  }
}

/// @nodoc
abstract mixin class $GrammarPointCopyWith<$Res> {
  factory $GrammarPointCopyWith(
          GrammarPoint value, $Res Function(GrammarPoint) _then) =
      _$GrammarPointCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String title,
      String explanation,
      List<String> exampleExpressionIds,
      List<String> exampleSentenceIds,
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      List<Interaction> practiceItems});
}

/// @nodoc
class _$GrammarPointCopyWithImpl<$Res> implements $GrammarPointCopyWith<$Res> {
  _$GrammarPointCopyWithImpl(this._self, this._then);

  final GrammarPoint _self;
  final $Res Function(GrammarPoint) _then;

  /// Create a copy of GrammarPoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? explanation = null,
    Object? exampleExpressionIds = null,
    Object? exampleSentenceIds = null,
    Object? practiceItems = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      explanation: null == explanation
          ? _self.explanation
          : explanation // ignore: cast_nullable_to_non_nullable
              as String,
      exampleExpressionIds: null == exampleExpressionIds
          ? _self.exampleExpressionIds
          : exampleExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      exampleSentenceIds: null == exampleSentenceIds
          ? _self.exampleSentenceIds
          : exampleSentenceIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      practiceItems: null == practiceItems
          ? _self.practiceItems
          : practiceItems // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ));
  }
}

/// Adds pattern-matching-related methods to [GrammarPoint].
extension GrammarPointPatterns on GrammarPoint {
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
    TResult Function(_GrammarPoint value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GrammarPoint() when $default != null:
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
    TResult Function(_GrammarPoint value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GrammarPoint():
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
    TResult? Function(_GrammarPoint value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GrammarPoint() when $default != null:
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
            String title,
            String explanation,
            List<String> exampleExpressionIds,
            List<String> exampleSentenceIds,
            @JsonKey(
                fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
            List<Interaction> practiceItems)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GrammarPoint() when $default != null:
        return $default(
            _that.id,
            _that.title,
            _that.explanation,
            _that.exampleExpressionIds,
            _that.exampleSentenceIds,
            _that.practiceItems);
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
            String title,
            String explanation,
            List<String> exampleExpressionIds,
            List<String> exampleSentenceIds,
            @JsonKey(
                fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
            List<Interaction> practiceItems)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GrammarPoint():
        return $default(
            _that.id,
            _that.title,
            _that.explanation,
            _that.exampleExpressionIds,
            _that.exampleSentenceIds,
            _that.practiceItems);
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
            String title,
            String explanation,
            List<String> exampleExpressionIds,
            List<String> exampleSentenceIds,
            @JsonKey(
                fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
            List<Interaction> practiceItems)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GrammarPoint() when $default != null:
        return $default(
            _that.id,
            _that.title,
            _that.explanation,
            _that.exampleExpressionIds,
            _that.exampleSentenceIds,
            _that.practiceItems);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GrammarPoint implements GrammarPoint {
  const _GrammarPoint(
      {required this.id,
      required this.title,
      this.explanation = '',
      final List<String> exampleExpressionIds = const <String>[],
      final List<String> exampleSentenceIds = const <String>[],
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      final List<Interaction> practiceItems = const <Interaction>[]})
      : _exampleExpressionIds = exampleExpressionIds,
        _exampleSentenceIds = exampleSentenceIds,
        _practiceItems = practiceItems;
  factory _GrammarPoint.fromJson(Map<String, dynamic> json) =>
      _$GrammarPointFromJson(json);

  @override
  final String id;

  /// Short title, e.g. "Present tense -a verb conjugation".
  @override
  final String title;

  /// Full explanation shown in lesson and review.
  @override
  @JsonKey()
  final String explanation;

  /// IDs of expressions that exemplify this grammar point.
  final List<String> _exampleExpressionIds;

  /// IDs of expressions that exemplify this grammar point.
  @override
  @JsonKey()
  List<String> get exampleExpressionIds {
    if (_exampleExpressionIds is EqualUnmodifiableListView)
      return _exampleExpressionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exampleExpressionIds);
  }

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  final List<String> _exampleSentenceIds;

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  @override
  @JsonKey()
  List<String> get exampleSentenceIds {
    if (_exampleSentenceIds is EqualUnmodifiableListView)
      return _exampleSentenceIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exampleSentenceIds);
  }

  /// Short practice drills for the grammar-review screen.
  final List<Interaction> _practiceItems;

  /// Short practice drills for the grammar-review screen.
  @override
  @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
  List<Interaction> get practiceItems {
    if (_practiceItems is EqualUnmodifiableListView) return _practiceItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_practiceItems);
  }

  /// Create a copy of GrammarPoint
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GrammarPointCopyWith<_GrammarPoint> get copyWith =>
      __$GrammarPointCopyWithImpl<_GrammarPoint>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GrammarPointToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GrammarPoint &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.explanation, explanation) ||
                other.explanation == explanation) &&
            const DeepCollectionEquality()
                .equals(other._exampleExpressionIds, _exampleExpressionIds) &&
            const DeepCollectionEquality()
                .equals(other._exampleSentenceIds, _exampleSentenceIds) &&
            const DeepCollectionEquality()
                .equals(other._practiceItems, _practiceItems));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      explanation,
      const DeepCollectionEquality().hash(_exampleExpressionIds),
      const DeepCollectionEquality().hash(_exampleSentenceIds),
      const DeepCollectionEquality().hash(_practiceItems));

  @override
  String toString() {
    return 'GrammarPoint(id: $id, title: $title, explanation: $explanation, exampleExpressionIds: $exampleExpressionIds, exampleSentenceIds: $exampleSentenceIds, practiceItems: $practiceItems)';
  }
}

/// @nodoc
abstract mixin class _$GrammarPointCopyWith<$Res>
    implements $GrammarPointCopyWith<$Res> {
  factory _$GrammarPointCopyWith(
          _GrammarPoint value, $Res Function(_GrammarPoint) _then) =
      __$GrammarPointCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String explanation,
      List<String> exampleExpressionIds,
      List<String> exampleSentenceIds,
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      List<Interaction> practiceItems});
}

/// @nodoc
class __$GrammarPointCopyWithImpl<$Res>
    implements _$GrammarPointCopyWith<$Res> {
  __$GrammarPointCopyWithImpl(this._self, this._then);

  final _GrammarPoint _self;
  final $Res Function(_GrammarPoint) _then;

  /// Create a copy of GrammarPoint
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? explanation = null,
    Object? exampleExpressionIds = null,
    Object? exampleSentenceIds = null,
    Object? practiceItems = null,
  }) {
    return _then(_GrammarPoint(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      explanation: null == explanation
          ? _self.explanation
          : explanation // ignore: cast_nullable_to_non_nullable
              as String,
      exampleExpressionIds: null == exampleExpressionIds
          ? _self._exampleExpressionIds
          : exampleExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      exampleSentenceIds: null == exampleSentenceIds
          ? _self._exampleSentenceIds
          : exampleSentenceIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      practiceItems: null == practiceItems
          ? _self._practiceItems
          : practiceItems // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ));
  }
}

// dart format on
