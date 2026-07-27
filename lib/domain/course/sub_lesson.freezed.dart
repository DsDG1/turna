// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sub_lesson.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SubLesson {
  String get id;
  String get name;
  String get description;

  /// Ordering index within the parent lesson.
  int get sortOrder;

  /// The interactions that make up this sub-lesson.
  List<Stage> get stages;

  /// Create a copy of SubLesson
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SubLessonCopyWith<SubLesson> get copyWith =>
      _$SubLessonCopyWithImpl<SubLesson>(this as SubLesson, _$identity);

  /// Serializes this SubLesson to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SubLesson &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder) &&
            const DeepCollectionEquality().equals(other.stages, stages));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, description, sortOrder,
      const DeepCollectionEquality().hash(stages));

  @override
  String toString() {
    return 'SubLesson(id: $id, name: $name, description: $description, sortOrder: $sortOrder, stages: $stages)';
  }
}

/// @nodoc
abstract mixin class $SubLessonCopyWith<$Res> {
  factory $SubLessonCopyWith(SubLesson value, $Res Function(SubLesson) _then) =
      _$SubLessonCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      int sortOrder,
      List<Stage> stages});
}

/// @nodoc
class _$SubLessonCopyWithImpl<$Res> implements $SubLessonCopyWith<$Res> {
  _$SubLessonCopyWithImpl(this._self, this._then);

  final SubLesson _self;
  final $Res Function(SubLesson) _then;

  /// Create a copy of SubLesson
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? sortOrder = null,
    Object? stages = null,
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
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _self.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
      stages: null == stages
          ? _self.stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
    ));
  }
}

/// Adds pattern-matching-related methods to [SubLesson].
extension SubLessonPatterns on SubLesson {
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
    TResult Function(_SubLesson value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SubLesson() when $default != null:
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
    TResult Function(_SubLesson value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLesson():
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
    TResult? Function(_SubLesson value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLesson() when $default != null:
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
    TResult Function(String id, String name, String description, int sortOrder,
            List<Stage> stages)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _SubLesson() when $default != null:
        return $default(_that.id, _that.name, _that.description,
            _that.sortOrder, _that.stages);
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
    TResult Function(String id, String name, String description, int sortOrder,
            List<Stage> stages)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLesson():
        return $default(_that.id, _that.name, _that.description,
            _that.sortOrder, _that.stages);
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
    TResult? Function(String id, String name, String description, int sortOrder,
            List<Stage> stages)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _SubLesson() when $default != null:
        return $default(_that.id, _that.name, _that.description,
            _that.sortOrder, _that.stages);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _SubLesson implements SubLesson {
  const _SubLesson(
      {required this.id,
      required this.name,
      this.description = '',
      this.sortOrder = 0,
      final List<Stage> stages = const <Stage>[]})
      : _stages = stages;
  factory _SubLesson.fromJson(Map<String, dynamic> json) =>
      _$SubLessonFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey()
  final String description;

  /// Ordering index within the parent lesson.
  @override
  @JsonKey()
  final int sortOrder;

  /// The interactions that make up this sub-lesson.
  final List<Stage> _stages;

  /// The interactions that make up this sub-lesson.
  @override
  @JsonKey()
  List<Stage> get stages {
    if (_stages is EqualUnmodifiableListView) return _stages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_stages);
  }

  /// Create a copy of SubLesson
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SubLessonCopyWith<_SubLesson> get copyWith =>
      __$SubLessonCopyWithImpl<_SubLesson>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$SubLessonToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SubLesson &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder) &&
            const DeepCollectionEquality().equals(other._stages, _stages));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, description, sortOrder,
      const DeepCollectionEquality().hash(_stages));

  @override
  String toString() {
    return 'SubLesson(id: $id, name: $name, description: $description, sortOrder: $sortOrder, stages: $stages)';
  }
}

/// @nodoc
abstract mixin class _$SubLessonCopyWith<$Res>
    implements $SubLessonCopyWith<$Res> {
  factory _$SubLessonCopyWith(
          _SubLesson value, $Res Function(_SubLesson) _then) =
      __$SubLessonCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      int sortOrder,
      List<Stage> stages});
}

/// @nodoc
class __$SubLessonCopyWithImpl<$Res> implements _$SubLessonCopyWith<$Res> {
  __$SubLessonCopyWithImpl(this._self, this._then);

  final _SubLesson _self;
  final $Res Function(_SubLesson) _then;

  /// Create a copy of SubLesson
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? sortOrder = null,
    Object? stages = null,
  }) {
    return _then(_SubLesson(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _self.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
      stages: null == stages
          ? _self._stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
    ));
  }
}

// dart format on
