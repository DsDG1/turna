// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'anki_card_adapter.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NotetypeMapping {
  NotetypeMappingType get type;

  /// Index of the field used as front/prompt
  int get frontFieldIndex;

  /// Index of the field used as back/answer
  int get backFieldIndex;

  /// Optional reason (from AI identification)
  String get reason;

  /// Create a copy of NotetypeMapping
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $NotetypeMappingCopyWith<NotetypeMapping> get copyWith =>
      _$NotetypeMappingCopyWithImpl<NotetypeMapping>(
          this as NotetypeMapping, _$identity);

  /// Serializes this NotetypeMapping to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is NotetypeMapping &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.frontFieldIndex, frontFieldIndex) ||
                other.frontFieldIndex == frontFieldIndex) &&
            (identical(other.backFieldIndex, backFieldIndex) ||
                other.backFieldIndex == backFieldIndex) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, type, frontFieldIndex, backFieldIndex, reason);

  @override
  String toString() {
    return 'NotetypeMapping(type: $type, frontFieldIndex: $frontFieldIndex, backFieldIndex: $backFieldIndex, reason: $reason)';
  }
}

/// @nodoc
abstract mixin class $NotetypeMappingCopyWith<$Res> {
  factory $NotetypeMappingCopyWith(
          NotetypeMapping value, $Res Function(NotetypeMapping) _then) =
      _$NotetypeMappingCopyWithImpl;
  @useResult
  $Res call(
      {NotetypeMappingType type,
      int frontFieldIndex,
      int backFieldIndex,
      String reason});
}

/// @nodoc
class _$NotetypeMappingCopyWithImpl<$Res>
    implements $NotetypeMappingCopyWith<$Res> {
  _$NotetypeMappingCopyWithImpl(this._self, this._then);

  final NotetypeMapping _self;
  final $Res Function(NotetypeMapping) _then;

  /// Create a copy of NotetypeMapping
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? frontFieldIndex = null,
    Object? backFieldIndex = null,
    Object? reason = null,
  }) {
    return _then(_self.copyWith(
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as NotetypeMappingType,
      frontFieldIndex: null == frontFieldIndex
          ? _self.frontFieldIndex
          : frontFieldIndex // ignore: cast_nullable_to_non_nullable
              as int,
      backFieldIndex: null == backFieldIndex
          ? _self.backFieldIndex
          : backFieldIndex // ignore: cast_nullable_to_non_nullable
              as int,
      reason: null == reason
          ? _self.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [NotetypeMapping].
extension NotetypeMappingPatterns on NotetypeMapping {
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
    TResult Function(_NotetypeMapping value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NotetypeMapping() when $default != null:
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
    TResult Function(_NotetypeMapping value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotetypeMapping():
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
    TResult? Function(_NotetypeMapping value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotetypeMapping() when $default != null:
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
    TResult Function(NotetypeMappingType type, int frontFieldIndex,
            int backFieldIndex, String reason)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _NotetypeMapping() when $default != null:
        return $default(_that.type, _that.frontFieldIndex, _that.backFieldIndex,
            _that.reason);
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
    TResult Function(NotetypeMappingType type, int frontFieldIndex,
            int backFieldIndex, String reason)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotetypeMapping():
        return $default(_that.type, _that.frontFieldIndex, _that.backFieldIndex,
            _that.reason);
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
    TResult? Function(NotetypeMappingType type, int frontFieldIndex,
            int backFieldIndex, String reason)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _NotetypeMapping() when $default != null:
        return $default(_that.type, _that.frontFieldIndex, _that.backFieldIndex,
            _that.reason);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _NotetypeMapping implements NotetypeMapping {
  const _NotetypeMapping(
      {required this.type,
      this.frontFieldIndex = 0,
      this.backFieldIndex = 1,
      this.reason = ''});
  factory _NotetypeMapping.fromJson(Map<String, dynamic> json) =>
      _$NotetypeMappingFromJson(json);

  @override
  final NotetypeMappingType type;

  /// Index of the field used as front/prompt
  @override
  @JsonKey()
  final int frontFieldIndex;

  /// Index of the field used as back/answer
  @override
  @JsonKey()
  final int backFieldIndex;

  /// Optional reason (from AI identification)
  @override
  @JsonKey()
  final String reason;

  /// Create a copy of NotetypeMapping
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$NotetypeMappingCopyWith<_NotetypeMapping> get copyWith =>
      __$NotetypeMappingCopyWithImpl<_NotetypeMapping>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$NotetypeMappingToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _NotetypeMapping &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.frontFieldIndex, frontFieldIndex) ||
                other.frontFieldIndex == frontFieldIndex) &&
            (identical(other.backFieldIndex, backFieldIndex) ||
                other.backFieldIndex == backFieldIndex) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, type, frontFieldIndex, backFieldIndex, reason);

  @override
  String toString() {
    return 'NotetypeMapping(type: $type, frontFieldIndex: $frontFieldIndex, backFieldIndex: $backFieldIndex, reason: $reason)';
  }
}

/// @nodoc
abstract mixin class _$NotetypeMappingCopyWith<$Res>
    implements $NotetypeMappingCopyWith<$Res> {
  factory _$NotetypeMappingCopyWith(
          _NotetypeMapping value, $Res Function(_NotetypeMapping) _then) =
      __$NotetypeMappingCopyWithImpl;
  @override
  @useResult
  $Res call(
      {NotetypeMappingType type,
      int frontFieldIndex,
      int backFieldIndex,
      String reason});
}

/// @nodoc
class __$NotetypeMappingCopyWithImpl<$Res>
    implements _$NotetypeMappingCopyWith<$Res> {
  __$NotetypeMappingCopyWithImpl(this._self, this._then);

  final _NotetypeMapping _self;
  final $Res Function(_NotetypeMapping) _then;

  /// Create a copy of NotetypeMapping
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? type = null,
    Object? frontFieldIndex = null,
    Object? backFieldIndex = null,
    Object? reason = null,
  }) {
    return _then(_NotetypeMapping(
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as NotetypeMappingType,
      frontFieldIndex: null == frontFieldIndex
          ? _self.frontFieldIndex
          : frontFieldIndex // ignore: cast_nullable_to_non_nullable
              as int,
      backFieldIndex: null == backFieldIndex
          ? _self.backFieldIndex
          : backFieldIndex // ignore: cast_nullable_to_non_nullable
              as int,
      reason: null == reason
          ? _self.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
