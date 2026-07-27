// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'expression.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Expression {
  String get id;

  /// The expression in the target language, e.g. "habari za asubuhi".
  String get term;

  /// English translation, e.g. "good morning".
  String get translation;

  /// Optional pronunciation hint.
  String? get pronunciation;

  /// Optional pre-recorded audio asset; falls back to TTS if absent.
  String? get audioAsset;

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  List<String> get tags;

  /// Create a copy of Expression
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ExpressionCopyWith<Expression> get copyWith =>
      _$ExpressionCopyWithImpl<Expression>(this as Expression, _$identity);

  /// Serializes this Expression to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Expression &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.term, term) || other.term == term) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.pronunciation, pronunciation) ||
                other.pronunciation == pronunciation) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            const DeepCollectionEquality().equals(other.tags, tags));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, term, translation,
      pronunciation, audioAsset, const DeepCollectionEquality().hash(tags));

  @override
  String toString() {
    return 'Expression(id: $id, term: $term, translation: $translation, pronunciation: $pronunciation, audioAsset: $audioAsset, tags: $tags)';
  }
}

/// @nodoc
abstract mixin class $ExpressionCopyWith<$Res> {
  factory $ExpressionCopyWith(
          Expression value, $Res Function(Expression) _then) =
      _$ExpressionCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String term,
      String translation,
      String? pronunciation,
      String? audioAsset,
      List<String> tags});
}

/// @nodoc
class _$ExpressionCopyWithImpl<$Res> implements $ExpressionCopyWith<$Res> {
  _$ExpressionCopyWithImpl(this._self, this._then);

  final Expression _self;
  final $Res Function(Expression) _then;

  /// Create a copy of Expression
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? term = null,
    Object? translation = null,
    Object? pronunciation = freezed,
    Object? audioAsset = freezed,
    Object? tags = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      term: null == term
          ? _self.term
          : term // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      pronunciation: freezed == pronunciation
          ? _self.pronunciation
          : pronunciation // ignore: cast_nullable_to_non_nullable
              as String?,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: null == tags
          ? _self.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// Adds pattern-matching-related methods to [Expression].
extension ExpressionPatterns on Expression {
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
    TResult Function(_Expression value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Expression() when $default != null:
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
    TResult Function(_Expression value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Expression():
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
    TResult? Function(_Expression value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Expression() when $default != null:
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
    TResult Function(String id, String term, String translation,
            String? pronunciation, String? audioAsset, List<String> tags)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Expression() when $default != null:
        return $default(_that.id, _that.term, _that.translation,
            _that.pronunciation, _that.audioAsset, _that.tags);
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
    TResult Function(String id, String term, String translation,
            String? pronunciation, String? audioAsset, List<String> tags)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Expression():
        return $default(_that.id, _that.term, _that.translation,
            _that.pronunciation, _that.audioAsset, _that.tags);
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
    TResult? Function(String id, String term, String translation,
            String? pronunciation, String? audioAsset, List<String> tags)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Expression() when $default != null:
        return $default(_that.id, _that.term, _that.translation,
            _that.pronunciation, _that.audioAsset, _that.tags);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _Expression implements Expression {
  const _Expression(
      {required this.id,
      required this.term,
      required this.translation,
      this.pronunciation,
      this.audioAsset,
      final List<String> tags = const <String>[]})
      : _tags = tags;
  factory _Expression.fromJson(Map<String, dynamic> json) =>
      _$ExpressionFromJson(json);

  @override
  final String id;

  /// The expression in the target language, e.g. "habari za asubuhi".
  @override
  final String term;

  /// English translation, e.g. "good morning".
  @override
  final String translation;

  /// Optional pronunciation hint.
  @override
  final String? pronunciation;

  /// Optional pre-recorded audio asset; falls back to TTS if absent.
  @override
  final String? audioAsset;

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  final List<String> _tags;

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  /// Create a copy of Expression
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ExpressionCopyWith<_Expression> get copyWith =>
      __$ExpressionCopyWithImpl<_Expression>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ExpressionToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Expression &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.term, term) || other.term == term) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.pronunciation, pronunciation) ||
                other.pronunciation == pronunciation) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            const DeepCollectionEquality().equals(other._tags, _tags));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, term, translation,
      pronunciation, audioAsset, const DeepCollectionEquality().hash(_tags));

  @override
  String toString() {
    return 'Expression(id: $id, term: $term, translation: $translation, pronunciation: $pronunciation, audioAsset: $audioAsset, tags: $tags)';
  }
}

/// @nodoc
abstract mixin class _$ExpressionCopyWith<$Res>
    implements $ExpressionCopyWith<$Res> {
  factory _$ExpressionCopyWith(
          _Expression value, $Res Function(_Expression) _then) =
      __$ExpressionCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String term,
      String translation,
      String? pronunciation,
      String? audioAsset,
      List<String> tags});
}

/// @nodoc
class __$ExpressionCopyWithImpl<$Res> implements _$ExpressionCopyWith<$Res> {
  __$ExpressionCopyWithImpl(this._self, this._then);

  final _Expression _self;
  final $Res Function(_Expression) _then;

  /// Create a copy of Expression
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? term = null,
    Object? translation = null,
    Object? pronunciation = freezed,
    Object? audioAsset = freezed,
    Object? tags = null,
  }) {
    return _then(_Expression(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      term: null == term
          ? _self.term
          : term // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      pronunciation: freezed == pronunciation
          ? _self.pronunciation
          : pronunciation // ignore: cast_nullable_to_non_nullable
              as String?,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: null == tags
          ? _self._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

// dart format on
