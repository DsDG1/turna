// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'section.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Section _$SectionFromJson(Map<String, dynamic> json) {
  return _Section.fromJson(json);
}

/// @nodoc
mixin _$Section {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String? get level => throw _privateConstructorUsedError;
  List<String> get prerequisiteSectionIds => throw _privateConstructorUsedError;
  List<Unit> get units => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $SectionCopyWith<Section> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SectionCopyWith<$Res> {
  factory $SectionCopyWith(Section value, $Res Function(Section) then) =
      _$SectionCopyWithImpl<$Res, Section>;
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
class _$SectionCopyWithImpl<$Res, $Val extends Section>
    implements $SectionCopyWith<$Res> {
  _$SectionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

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
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      level: freezed == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as String?,
      prerequisiteSectionIds: null == prerequisiteSectionIds
          ? _value.prerequisiteSectionIds
          : prerequisiteSectionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      units: null == units
          ? _value.units
          : units // ignore: cast_nullable_to_non_nullable
              as List<Unit>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SectionImplCopyWith<$Res> implements $SectionCopyWith<$Res> {
  factory _$$SectionImplCopyWith(
          _$SectionImpl value, $Res Function(_$SectionImpl) then) =
      __$$SectionImplCopyWithImpl<$Res>;
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
class __$$SectionImplCopyWithImpl<$Res>
    extends _$SectionCopyWithImpl<$Res, _$SectionImpl>
    implements _$$SectionImplCopyWith<$Res> {
  __$$SectionImplCopyWithImpl(
      _$SectionImpl _value, $Res Function(_$SectionImpl) _then)
      : super(_value, _then);

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
    return _then(_$SectionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      level: freezed == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as String?,
      prerequisiteSectionIds: null == prerequisiteSectionIds
          ? _value._prerequisiteSectionIds
          : prerequisiteSectionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      units: null == units
          ? _value._units
          : units // ignore: cast_nullable_to_non_nullable
              as List<Unit>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SectionImpl implements _Section {
  const _$SectionImpl(
      {required this.id,
      required this.name,
      this.description = '',
      this.level,
      final List<String> prerequisiteSectionIds = const <String>[],
      required final List<Unit> units})
      : _prerequisiteSectionIds = prerequisiteSectionIds,
        _units = units;

  factory _$SectionImpl.fromJson(Map<String, dynamic> json) =>
      _$$SectionImplFromJson(json);

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

  @override
  String toString() {
    return 'Section(id: $id, name: $name, description: $description, level: $level, prerequisiteSectionIds: $prerequisiteSectionIds, units: $units)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SectionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.level, level) || other.level == level) &&
            const DeepCollectionEquality().equals(
                other._prerequisiteSectionIds, _prerequisiteSectionIds) &&
            const DeepCollectionEquality().equals(other._units, _units));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      level,
      const DeepCollectionEquality().hash(_prerequisiteSectionIds),
      const DeepCollectionEquality().hash(_units));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SectionImplCopyWith<_$SectionImpl> get copyWith =>
      __$$SectionImplCopyWithImpl<_$SectionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SectionImplToJson(
      this,
    );
  }
}

abstract class _Section implements Section {
  const factory _Section(
      {required final String id,
      required final String name,
      final String description,
      final String? level,
      final List<String> prerequisiteSectionIds,
      required final List<Unit> units}) = _$SectionImpl;

  factory _Section.fromJson(Map<String, dynamic> json) = _$SectionImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get description;
  @override
  String? get level;
  @override
  List<String> get prerequisiteSectionIds;
  @override
  List<Unit> get units;
  @override
  @JsonKey(ignore: true)
  _$$SectionImplCopyWith<_$SectionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
