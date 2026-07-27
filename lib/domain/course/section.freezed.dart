// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'section.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Section {
  String get id;
  String get name;
  String get description;
  String? get level;
  List<String> get prerequisiteSectionIds;
  List<Unit> get units;

  /// Create a copy of Section
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SectionCopyWith<Section> get copyWith =>
      _$SectionCopyWithImpl<Section>(this as Section, _$identity);

  /// Serializes this Section to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Section &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.level, level) || other.level == level) &&
            const DeepCollectionEquality()
                .equals(other.prerequisiteSectionIds, prerequisiteSectionIds) &&
            const DeepCollectionEquality().equals(other.units, units));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      level,
      const DeepCollectionEquality().hash(prerequisiteSectionIds),
      const DeepCollectionEquality().hash(units));

  @override
  String toString() {
    return 'Section(id: $id, name: $name, description: $description, level: $level, prerequisiteSectionIds: $prerequisiteSectionIds, units: $units)';
  }
}

/// @nodoc
abstract mixin class $SectionCopyWith<$Res> {
  factory $SectionCopyWith(Section value, $Res Function(Section) _then) =
      _$SectionCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      String? level,
      List<String> prerequisiteSectionIds,
      List<Unit> units});
}

/// @nodoc
class _$SectionCopyWithImpl<$Res> implements $SectionCopyWith<$Res> {
  _$SectionCopyWithImpl(this._self, this._then);

  final Section _self;
  final $Res Function(Section) _then;

  /// Create a copy of Section
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? level = freezed,
    Object? prerequisiteSectionIds = null,
    Object? units = null,
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
      level: freezed == level
          ? _self.level
          : level // ignore: cast_nullable_to_non_nullable
              as String?,
      prerequisiteSectionIds: null == prerequisiteSectionIds
          ? _self.prerequisiteSectionIds
          : prerequisiteSectionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      units: null == units
          ? _self.units
          : units // ignore: cast_nullable_to_non_nullable
              as List<Unit>,
    ));
  }
}

/// Adds pattern-matching-related methods to [Section].
extension SectionPatterns on Section {
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
    TResult Function(_Section value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Section() when $default != null:
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
    TResult Function(_Section value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Section():
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
    TResult? Function(_Section value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Section() when $default != null:
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
    TResult Function(String id, String name, String description, String? level,
            List<String> prerequisiteSectionIds, List<Unit> units)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Section() when $default != null:
        return $default(_that.id, _that.name, _that.description, _that.level,
            _that.prerequisiteSectionIds, _that.units);
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
    TResult Function(String id, String name, String description, String? level,
            List<String> prerequisiteSectionIds, List<Unit> units)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Section():
        return $default(_that.id, _that.name, _that.description, _that.level,
            _that.prerequisiteSectionIds, _that.units);
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
    TResult? Function(String id, String name, String description, String? level,
            List<String> prerequisiteSectionIds, List<Unit> units)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Section() when $default != null:
        return $default(_that.id, _that.name, _that.description, _that.level,
            _that.prerequisiteSectionIds, _that.units);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _Section implements Section {
  const _Section(
      {required this.id,
      required this.name,
      this.description = '',
      this.level,
      final List<String> prerequisiteSectionIds = const <String>[],
      required final List<Unit> units})
      : _prerequisiteSectionIds = prerequisiteSectionIds,
        _units = units;
  factory _Section.fromJson(Map<String, dynamic> json) =>
      _$SectionFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  @JsonKey()
  final String description;
  @override
  final String? level;
  final List<String> _prerequisiteSectionIds;
  @override
  @JsonKey()
  List<String> get prerequisiteSectionIds {
    if (_prerequisiteSectionIds is EqualUnmodifiableListView)
      return _prerequisiteSectionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_prerequisiteSectionIds);
  }

  final List<Unit> _units;
  @override
  List<Unit> get units {
    if (_units is EqualUnmodifiableListView) return _units;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_units);
  }

  /// Create a copy of Section
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SectionCopyWith<_Section> get copyWith =>
      __$SectionCopyWithImpl<_Section>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$SectionToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Section &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.level, level) || other.level == level) &&
            const DeepCollectionEquality().equals(
                other._prerequisiteSectionIds, _prerequisiteSectionIds) &&
            const DeepCollectionEquality().equals(other._units, _units));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      level,
      const DeepCollectionEquality().hash(_prerequisiteSectionIds),
      const DeepCollectionEquality().hash(_units));

  @override
  String toString() {
    return 'Section(id: $id, name: $name, description: $description, level: $level, prerequisiteSectionIds: $prerequisiteSectionIds, units: $units)';
  }
}

/// @nodoc
abstract mixin class _$SectionCopyWith<$Res> implements $SectionCopyWith<$Res> {
  factory _$SectionCopyWith(_Section value, $Res Function(_Section) _then) =
      __$SectionCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      String? level,
      List<String> prerequisiteSectionIds,
      List<Unit> units});
}

/// @nodoc
class __$SectionCopyWithImpl<$Res> implements _$SectionCopyWith<$Res> {
  __$SectionCopyWithImpl(this._self, this._then);

  final _Section _self;
  final $Res Function(_Section) _then;

  /// Create a copy of Section
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? level = freezed,
    Object? prerequisiteSectionIds = null,
    Object? units = null,
  }) {
    return _then(_Section(
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
      level: freezed == level
          ? _self.level
          : level // ignore: cast_nullable_to_non_nullable
              as String?,
      prerequisiteSectionIds: null == prerequisiteSectionIds
          ? _self._prerequisiteSectionIds
          : prerequisiteSectionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      units: null == units
          ? _self._units
          : units // ignore: cast_nullable_to_non_nullable
              as List<Unit>,
    ));
  }
}

// dart format on
