// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lesson.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Lesson {
  String get id;
  String get name;
  String get description;
  LessonType get type;

  /// Pedagogical template. If omitted, the loader/renderer fall back to
  /// a flat stage list for backward compatibility.
  LessonTemplate get template;
  List<String> get prerequisiteLessonIds;
  LessonContent get content;

  /// Create a copy of Lesson
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LessonCopyWith<Lesson> get copyWith =>
      _$LessonCopyWithImpl<Lesson>(this as Lesson, _$identity);

  /// Serializes this Lesson to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Lesson &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.template, template) ||
                other.template == template) &&
            const DeepCollectionEquality()
                .equals(other.prerequisiteLessonIds, prerequisiteLessonIds) &&
            (identical(other.content, content) || other.content == content));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      type,
      template,
      const DeepCollectionEquality().hash(prerequisiteLessonIds),
      content);

  @override
  String toString() {
    return 'Lesson(id: $id, name: $name, description: $description, type: $type, template: $template, prerequisiteLessonIds: $prerequisiteLessonIds, content: $content)';
  }
}

/// @nodoc
abstract mixin class $LessonCopyWith<$Res> {
  factory $LessonCopyWith(Lesson value, $Res Function(Lesson) _then) =
      _$LessonCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      LessonType type,
      LessonTemplate template,
      List<String> prerequisiteLessonIds,
      LessonContent content});

  $LessonContentCopyWith<$Res> get content;
}

/// @nodoc
class _$LessonCopyWithImpl<$Res> implements $LessonCopyWith<$Res> {
  _$LessonCopyWithImpl(this._self, this._then);

  final Lesson _self;
  final $Res Function(Lesson) _then;

  /// Create a copy of Lesson
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? type = null,
    Object? template = null,
    Object? prerequisiteLessonIds = null,
    Object? content = null,
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
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as LessonType,
      template: null == template
          ? _self.template
          : template // ignore: cast_nullable_to_non_nullable
              as LessonTemplate,
      prerequisiteLessonIds: null == prerequisiteLessonIds
          ? _self.prerequisiteLessonIds
          : prerequisiteLessonIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as LessonContent,
    ));
  }

  /// Create a copy of Lesson
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $LessonContentCopyWith<$Res> get content {
    return $LessonContentCopyWith<$Res>(_self.content, (value) {
      return _then(_self.copyWith(content: value));
    });
  }
}

/// Adds pattern-matching-related methods to [Lesson].
extension LessonPatterns on Lesson {
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
    TResult Function(_Lesson value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Lesson() when $default != null:
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
    TResult Function(_Lesson value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Lesson():
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
    TResult? Function(_Lesson value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Lesson() when $default != null:
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
            String name,
            String description,
            LessonType type,
            LessonTemplate template,
            List<String> prerequisiteLessonIds,
            LessonContent content)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Lesson() when $default != null:
        return $default(_that.id, _that.name, _that.description, _that.type,
            _that.template, _that.prerequisiteLessonIds, _that.content);
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
            String name,
            String description,
            LessonType type,
            LessonTemplate template,
            List<String> prerequisiteLessonIds,
            LessonContent content)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Lesson():
        return $default(_that.id, _that.name, _that.description, _that.type,
            _that.template, _that.prerequisiteLessonIds, _that.content);
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
            String name,
            String description,
            LessonType type,
            LessonTemplate template,
            List<String> prerequisiteLessonIds,
            LessonContent content)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Lesson() when $default != null:
        return $default(_that.id, _that.name, _that.description, _that.type,
            _that.template, _that.prerequisiteLessonIds, _that.content);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _Lesson extends Lesson {
  const _Lesson(
      {required this.id,
      required this.name,
      this.description = '',
      this.type = LessonType.normal,
      this.template = LessonTemplate.legacy,
      final List<String> prerequisiteLessonIds = const <String>[],
      required this.content})
      : _prerequisiteLessonIds = prerequisiteLessonIds,
        super._();
  factory _Lesson.fromJson(Map<String, dynamic> json) => _$LessonFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey()
  final String description;
  @override
  @JsonKey()
  final LessonType type;

  /// Pedagogical template. If omitted, the loader/renderer fall back to
  /// a flat stage list for backward compatibility.
  @override
  @JsonKey()
  final LessonTemplate template;
  final List<String> _prerequisiteLessonIds;
  @override
  @JsonKey()
  List<String> get prerequisiteLessonIds {
    if (_prerequisiteLessonIds is EqualUnmodifiableListView)
      return _prerequisiteLessonIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_prerequisiteLessonIds);
  }

  @override
  final LessonContent content;

  /// Create a copy of Lesson
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$LessonCopyWith<_Lesson> get copyWith =>
      __$LessonCopyWithImpl<_Lesson>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$LessonToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Lesson &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.template, template) ||
                other.template == template) &&
            const DeepCollectionEquality()
                .equals(other._prerequisiteLessonIds, _prerequisiteLessonIds) &&
            (identical(other.content, content) || other.content == content));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      type,
      template,
      const DeepCollectionEquality().hash(_prerequisiteLessonIds),
      content);

  @override
  String toString() {
    return 'Lesson(id: $id, name: $name, description: $description, type: $type, template: $template, prerequisiteLessonIds: $prerequisiteLessonIds, content: $content)';
  }
}

/// @nodoc
abstract mixin class _$LessonCopyWith<$Res> implements $LessonCopyWith<$Res> {
  factory _$LessonCopyWith(_Lesson value, $Res Function(_Lesson) _then) =
      __$LessonCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      LessonType type,
      LessonTemplate template,
      List<String> prerequisiteLessonIds,
      LessonContent content});

  @override
  $LessonContentCopyWith<$Res> get content;
}

/// @nodoc
class __$LessonCopyWithImpl<$Res> implements _$LessonCopyWith<$Res> {
  __$LessonCopyWithImpl(this._self, this._then);

  final _Lesson _self;
  final $Res Function(_Lesson) _then;

  /// Create a copy of Lesson
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? type = null,
    Object? template = null,
    Object? prerequisiteLessonIds = null,
    Object? content = null,
  }) {
    return _then(_Lesson(
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
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as LessonType,
      template: null == template
          ? _self.template
          : template // ignore: cast_nullable_to_non_nullable
              as LessonTemplate,
      prerequisiteLessonIds: null == prerequisiteLessonIds
          ? _self._prerequisiteLessonIds
          : prerequisiteLessonIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as LessonContent,
    ));
  }

  /// Create a copy of Lesson
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $LessonContentCopyWith<$Res> get content {
    return $LessonContentCopyWith<$Res>(_self.content, (value) {
      return _then(_self.copyWith(content: value));
    });
  }
}

// dart format on
