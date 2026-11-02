// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sub_lesson_summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SubLessonSummary {
  String get id;

  /// Display title of the sub-lesson; becomes the tree node's label.
  String get name;

  /// Ordering index inside the parent lesson (list position at seed time).
  int get sortOrder;

  /// Create a copy of SubLessonSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SubLessonSummaryCopyWith<SubLessonSummary> get copyWith =>
      _$SubLessonSummaryCopyWithImpl<SubLessonSummary>(
          this as SubLessonSummary, _$identity);

  /// Serializes this SubLessonSummary to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SubLessonSummary &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, sortOrder);

  @override
  String toString() {
    return 'SubLessonSummary(id: $id, name: $name, sortOrder: $sortOrder)';
  }
}

/// @nodoc
abstract mixin class $SubLessonSummaryCopyWith<$Res> {
  factory $SubLessonSummaryCopyWith(
          SubLessonSummary value, $Res Function(SubLessonSummary) _then) =
      _$SubLessonSummaryCopyWithImpl;
  @useResult
  $Res call({String id, String name, int sortOrder});
}

/// @nodoc
class _$SubLessonSummaryCopyWithImpl<$Res>
    implements $SubLessonSummaryCopyWith<$Res> {
  _$SubLessonSummaryCopyWithImpl(this._self, this._then);

  final SubLessonSummary _self;
  final $Res Function(SubLessonSummary) _then;

  /// Create a copy of SubLessonSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? sortOrder = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _self.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [SubLessonSummary].
extension SubLessonSummaryPatterns on SubLessonSummary {
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
    TResult Function(_SubLessonSummary value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SubLessonSummary() when $default != null:
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
    TResult Function(_SubLessonSummary value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLessonSummary():
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
    TResult? Function(_SubLessonSummary value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLessonSummary() when $default != null:
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
    TResult Function(String id, String name, int sortOrder)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SubLessonSummary() when $default != null:
        return $default(_that.id, _that.name, _that.sortOrder);
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
    TResult Function(String id, String name, int sortOrder) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLessonSummary():
        return $default(_that.id, _that.name, _that.sortOrder);
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
    TResult? Function(String id, String name, int sortOrder)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLessonSummary() when $default != null:
        return $default(_that.id, _that.name, _that.sortOrder);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _SubLessonSummary implements SubLessonSummary {
  const _SubLessonSummary(
      {required this.id, required this.name, this.sortOrder = 0});
  factory _SubLessonSummary.fromJson(Map<String, dynamic> json) =>
      _$SubLessonSummaryFromJson(json);

  @override
  final String id;

  /// Display title of the sub-lesson; becomes the tree node's label.
  @override
  final String name;

  /// Ordering index inside the parent lesson (list position at seed time).
  @override
  @JsonKey()
  final int sortOrder;

  /// Create a copy of SubLessonSummary
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SubLessonSummaryCopyWith<_SubLessonSummary> get copyWith =>
      __$SubLessonSummaryCopyWithImpl<_SubLessonSummary>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$SubLessonSummaryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SubLessonSummary &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, sortOrder);

  @override
  String toString() {
    return 'SubLessonSummary(id: $id, name: $name, sortOrder: $sortOrder)';
  }
}

/// @nodoc
abstract mixin class _$SubLessonSummaryCopyWith<$Res>
    implements $SubLessonSummaryCopyWith<$Res> {
  factory _$SubLessonSummaryCopyWith(
          _SubLessonSummary value, $Res Function(_SubLessonSummary) _then) =
      __$SubLessonSummaryCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String name, int sortOrder});
}

/// @nodoc
class __$SubLessonSummaryCopyWithImpl<$Res>
    implements _$SubLessonSummaryCopyWith<$Res> {
  __$SubLessonSummaryCopyWithImpl(this._self, this._then);

  final _SubLessonSummary _self;
  final $Res Function(_SubLessonSummary) _then;

  /// Create a copy of SubLessonSummary
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? sortOrder = null,
  }) {
    return _then(_SubLessonSummary(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _self.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
