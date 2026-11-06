// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'review_policy.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ReviewPolicy {
  int get minItems;
  int get maxItems;
  Map<String, double> get typeWeights;

  /// Create a copy of ReviewPolicy
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ReviewPolicyCopyWith<ReviewPolicy> get copyWith =>
      _$ReviewPolicyCopyWithImpl<ReviewPolicy>(
          this as ReviewPolicy, _$identity);

  /// Serializes this ReviewPolicy to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ReviewPolicy &&
            (identical(other.minItems, minItems) ||
                other.minItems == minItems) &&
            (identical(other.maxItems, maxItems) ||
                other.maxItems == maxItems) &&
            const DeepCollectionEquality()
                .equals(other.typeWeights, typeWeights));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, minItems, maxItems,
      const DeepCollectionEquality().hash(typeWeights));

  @override
  String toString() {
    return 'ReviewPolicy(minItems: $minItems, maxItems: $maxItems, typeWeights: $typeWeights)';
  }
}

/// @nodoc
abstract mixin class $ReviewPolicyCopyWith<$Res> {
  factory $ReviewPolicyCopyWith(
          ReviewPolicy value, $Res Function(ReviewPolicy) _then) =
      _$ReviewPolicyCopyWithImpl;
  @useResult
  $Res call({int minItems, int maxItems, Map<String, double> typeWeights});
}

/// @nodoc
class _$ReviewPolicyCopyWithImpl<$Res> implements $ReviewPolicyCopyWith<$Res> {
  _$ReviewPolicyCopyWithImpl(this._self, this._then);

  final ReviewPolicy _self;
  final $Res Function(ReviewPolicy) _then;

  /// Create a copy of ReviewPolicy
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minItems = null,
    Object? maxItems = null,
    Object? typeWeights = null,
  }) {
    return _then(_self.copyWith(
      minItems: null == minItems
          ? _self.minItems
          : minItems // ignore: cast_nullable_to_non_nullable
              as int,
      maxItems: null == maxItems
          ? _self.maxItems
          : maxItems // ignore: cast_nullable_to_non_nullable
              as int,
      typeWeights: null == typeWeights
          ? _self.typeWeights
          : typeWeights // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
    ));
  }
}

/// Adds pattern-matching-related methods to [ReviewPolicy].
extension ReviewPolicyPatterns on ReviewPolicy {
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
    TResult Function(_ReviewPolicy value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ReviewPolicy() when $default != null:
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
    TResult Function(_ReviewPolicy value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReviewPolicy():
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
    TResult? Function(_ReviewPolicy value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReviewPolicy() when $default != null:
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
            int minItems, int maxItems, Map<String, double> typeWeights)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ReviewPolicy() when $default != null:
        return $default(_that.minItems, _that.maxItems, _that.typeWeights);
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
            int minItems, int maxItems, Map<String, double> typeWeights)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReviewPolicy():
        return $default(_that.minItems, _that.maxItems, _that.typeWeights);
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
            int minItems, int maxItems, Map<String, double> typeWeights)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ReviewPolicy() when $default != null:
        return $default(_that.minItems, _that.maxItems, _that.typeWeights);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _ReviewPolicy extends ReviewPolicy {
  const _ReviewPolicy(
      {required this.minItems,
      required this.maxItems,
      final Map<String, double> typeWeights = const <String, double>{}})
      : _typeWeights = typeWeights,
        super._();
  factory _ReviewPolicy.fromJson(Map<String, dynamic> json) =>
      _$ReviewPolicyFromJson(json);

  @override
  final int minItems;
  @override
  final int maxItems;
  final Map<String, double> _typeWeights;
  @override
  @JsonKey()
  Map<String, double> get typeWeights {
    if (_typeWeights is EqualUnmodifiableMapView) return _typeWeights;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_typeWeights);
  }

  /// Create a copy of ReviewPolicy
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ReviewPolicyCopyWith<_ReviewPolicy> get copyWith =>
      __$ReviewPolicyCopyWithImpl<_ReviewPolicy>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ReviewPolicyToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ReviewPolicy &&
            (identical(other.minItems, minItems) ||
                other.minItems == minItems) &&
            (identical(other.maxItems, maxItems) ||
                other.maxItems == maxItems) &&
            const DeepCollectionEquality()
                .equals(other._typeWeights, _typeWeights));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, minItems, maxItems,
      const DeepCollectionEquality().hash(_typeWeights));

  @override
  String toString() {
    return 'ReviewPolicy(minItems: $minItems, maxItems: $maxItems, typeWeights: $typeWeights)';
  }
}

/// @nodoc
abstract mixin class _$ReviewPolicyCopyWith<$Res>
    implements $ReviewPolicyCopyWith<$Res> {
  factory _$ReviewPolicyCopyWith(
          _ReviewPolicy value, $Res Function(_ReviewPolicy) _then) =
      __$ReviewPolicyCopyWithImpl;
  @override
  @useResult
  $Res call({int minItems, int maxItems, Map<String, double> typeWeights});
}

/// @nodoc
class __$ReviewPolicyCopyWithImpl<$Res>
    implements _$ReviewPolicyCopyWith<$Res> {
  __$ReviewPolicyCopyWithImpl(this._self, this._then);

  final _ReviewPolicy _self;
  final $Res Function(_ReviewPolicy) _then;

  /// Create a copy of ReviewPolicy
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? minItems = null,
    Object? maxItems = null,
    Object? typeWeights = null,
  }) {
    return _then(_ReviewPolicy(
      minItems: null == minItems
          ? _self.minItems
          : minItems // ignore: cast_nullable_to_non_nullable
              as int,
      maxItems: null == maxItems
          ? _self.maxItems
          : maxItems // ignore: cast_nullable_to_non_nullable
              as int,
      typeWeights: null == typeWeights
          ? _self._typeWeights
          : typeWeights // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
    ));
  }
}

// dart format on
