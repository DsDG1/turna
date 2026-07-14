// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'unit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Unit _$UnitFromJson(Map<String, dynamic> json) {
  return _Unit.fromJson(json);
}

/// @nodoc
mixin _$Unit {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  List<String> get prerequisiteUnitIds => throw _privateConstructorUsedError;
  List<Lesson> get lessons => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $UnitCopyWith<Unit> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UnitCopyWith<$Res> {
  factory $UnitCopyWith(Unit value, $Res Function(Unit) then) =
      _$UnitCopyWithImpl<$Res, Unit>;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      List<String> prerequisiteUnitIds,
      List<Lesson> lessons});
}

/// @nodoc
class _$UnitCopyWithImpl<$Res, $Val extends Unit>
    implements $UnitCopyWith<$Res> {
  _$UnitCopyWithImpl(this._value, this._then);

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
    Object? prerequisiteUnitIds = null,
    Object? lessons = null,
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
      prerequisiteUnitIds: null == prerequisiteUnitIds
          ? _value.prerequisiteUnitIds
          : prerequisiteUnitIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      lessons: null == lessons
          ? _value.lessons
          : lessons // ignore: cast_nullable_to_non_nullable
              as List<Lesson>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$UnitImplCopyWith<$Res> implements $UnitCopyWith<$Res> {
  factory _$$UnitImplCopyWith(
          _$UnitImpl value, $Res Function(_$UnitImpl) then) =
      __$$UnitImplCopyWithImpl<$Res>;
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
class __$$UnitImplCopyWithImpl<$Res>
    extends _$UnitCopyWithImpl<$Res, _$UnitImpl>
    implements _$$UnitImplCopyWith<$Res> {
  __$$UnitImplCopyWithImpl(_$UnitImpl _value, $Res Function(_$UnitImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? prerequisiteUnitIds = null,
    Object? lessons = null,
  }) {
    return _then(_$UnitImpl(
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
      prerequisiteUnitIds: null == prerequisiteUnitIds
          ? _value._prerequisiteUnitIds
          : prerequisiteUnitIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      lessons: null == lessons
          ? _value._lessons
          : lessons // ignore: cast_nullable_to_non_nullable
              as List<Lesson>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$UnitImpl implements _Unit {
  const _$UnitImpl(
      {required this.id,
      required this.name,
      this.description = '',
      final List<String> prerequisiteUnitIds = const <String>[],
      required final List<Lesson> lessons})
      : _prerequisiteUnitIds = prerequisiteUnitIds,
        _lessons = lessons;

  factory _$UnitImpl.fromJson(Map<String, dynamic> json) =>
      _$$UnitImplFromJson(json);

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

  @override
  String toString() {
    return 'Unit(id: $id, name: $name, description: $description, prerequisiteUnitIds: $prerequisiteUnitIds, lessons: $lessons)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UnitImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            const DeepCollectionEquality()
                .equals(other._prerequisiteUnitIds, _prerequisiteUnitIds) &&
            const DeepCollectionEquality().equals(other._lessons, _lessons));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      description,
      const DeepCollectionEquality().hash(_prerequisiteUnitIds),
      const DeepCollectionEquality().hash(_lessons));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$UnitImplCopyWith<_$UnitImpl> get copyWith =>
      __$$UnitImplCopyWithImpl<_$UnitImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UnitImplToJson(
      this,
    );
  }
}

abstract class _Unit implements Unit {
  const factory _Unit(
      {required final String id,
      required final String name,
      final String description,
      final List<String> prerequisiteUnitIds,
      required final List<Lesson> lessons}) = _$UnitImpl;

  factory _Unit.fromJson(Map<String, dynamic> json) = _$UnitImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get description;
  @override
  List<String> get prerequisiteUnitIds;
  @override
  List<Lesson> get lessons;
  @override
  @JsonKey(ignore: true)
  _$$UnitImplCopyWith<_$UnitImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
