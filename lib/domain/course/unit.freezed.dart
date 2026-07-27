// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'unit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Unit {
  String get id;
  String get name;
  String get description;
  List<String> get prerequisiteUnitIds;
  List<Lesson> get lessons;

  /// Create a copy of Unit
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $UnitCopyWith<Unit> get copyWith =>
      _$UnitCopyWithImpl<Unit>(this as Unit, _$identity);

  /// Serializes this Unit to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Unit &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            const DeepCollectionEquality()
                .equals(other.prerequisiteUnitIds, prerequisiteUnitIds) &&
            const DeepCollectionEquality().equals(other.lessons, lessons));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      const DeepCollectionEquality().hash(prerequisiteUnitIds),
      const DeepCollectionEquality().hash(lessons));

  @override
  String toString() {
    return 'Unit(id: $id, name: $name, description: $description, prerequisiteUnitIds: $prerequisiteUnitIds, lessons: $lessons)';
  }
}

/// @nodoc
abstract mixin class $UnitCopyWith<$Res> {
  factory $UnitCopyWith(Unit value, $Res Function(Unit) _then) =
      _$UnitCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      List<String> prerequisiteUnitIds,
      List<Lesson> lessons});
}

/// @nodoc
class _$UnitCopyWithImpl<$Res> implements $UnitCopyWith<$Res> {
  _$UnitCopyWithImpl(this._self, this._then);

  final Unit _self;
  final $Res Function(Unit) _then;

  /// Create a copy of Unit
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? prerequisiteUnitIds = null,
    Object? lessons = null,
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
      prerequisiteUnitIds: null == prerequisiteUnitIds
          ? _self.prerequisiteUnitIds
          : prerequisiteUnitIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      lessons: null == lessons
          ? _self.lessons
          : lessons // ignore: cast_nullable_to_non_nullable
              as List<Lesson>,
    ));
  }
}

/// Adds pattern-matching-related methods to [Unit].
extension UnitPatterns on Unit {
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
    TResult Function(_Unit value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Unit() when $default != null:
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
    TResult Function(_Unit value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Unit():
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
    TResult? Function(_Unit value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Unit() when $default != null:
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
    TResult Function(String id, String name, String description,
            List<String> prerequisiteUnitIds, List<Lesson> lessons)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Unit() when $default != null:
        return $default(_that.id, _that.name, _that.description,
            _that.prerequisiteUnitIds, _that.lessons);
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
    TResult Function(String id, String name, String description,
            List<String> prerequisiteUnitIds, List<Lesson> lessons)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Unit():
        return $default(_that.id, _that.name, _that.description,
            _that.prerequisiteUnitIds, _that.lessons);
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
    TResult? Function(String id, String name, String description,
            List<String> prerequisiteUnitIds, List<Lesson> lessons)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Unit() when $default != null:
        return $default(_that.id, _that.name, _that.description,
            _that.prerequisiteUnitIds, _that.lessons);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _Unit implements Unit {
  const _Unit(
      {required this.id,
      required this.name,
      this.description = '',
      final List<String> prerequisiteUnitIds = const <String>[],
      required final List<Lesson> lessons})
      : _prerequisiteUnitIds = prerequisiteUnitIds,
        _lessons = lessons;
  factory _Unit.fromJson(Map<String, dynamic> json) => _$UnitFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey()
  final String description;
  final List<String> _prerequisiteUnitIds;
  @override
  @JsonKey()
  List<String> get prerequisiteUnitIds {
    if (_prerequisiteUnitIds is EqualUnmodifiableListView)
      return _prerequisiteUnitIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_prerequisiteUnitIds);
  }

  final List<Lesson> _lessons;
  @override
  List<Lesson> get lessons {
    if (_lessons is EqualUnmodifiableListView) return _lessons;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_lessons);
  }

  /// Create a copy of Unit
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$UnitCopyWith<_Unit> get copyWith =>
      __$UnitCopyWithImpl<_Unit>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$UnitToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Unit &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            const DeepCollectionEquality()
                .equals(other._prerequisiteUnitIds, _prerequisiteUnitIds) &&
            const DeepCollectionEquality().equals(other._lessons, _lessons));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      const DeepCollectionEquality().hash(_prerequisiteUnitIds),
      const DeepCollectionEquality().hash(_lessons));

  @override
  String toString() {
    return 'Unit(id: $id, name: $name, description: $description, prerequisiteUnitIds: $prerequisiteUnitIds, lessons: $lessons)';
  }
}

/// @nodoc
abstract mixin class _$UnitCopyWith<$Res> implements $UnitCopyWith<$Res> {
  factory _$UnitCopyWith(_Unit value, $Res Function(_Unit) _then) =
      __$UnitCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      List<String> prerequisiteUnitIds,
      List<Lesson> lessons});
}

/// @nodoc
class __$UnitCopyWithImpl<$Res> implements _$UnitCopyWith<$Res> {
  __$UnitCopyWithImpl(this._self, this._then);

  final _Unit _self;
  final $Res Function(_Unit) _then;

  /// Create a copy of Unit
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? prerequisiteUnitIds = null,
    Object? lessons = null,
  }) {
    return _then(_Unit(
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
      prerequisiteUnitIds: null == prerequisiteUnitIds
          ? _self._prerequisiteUnitIds
          : prerequisiteUnitIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      lessons: null == lessons
          ? _self._lessons
          : lessons // ignore: cast_nullable_to_non_nullable
              as List<Lesson>,
    ));
  }
}

// dart format on
