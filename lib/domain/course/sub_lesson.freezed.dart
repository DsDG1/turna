// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sub_lesson.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SubLesson _$SubLessonFromJson(Map<String, dynamic> json) {
  return _SubLesson.fromJson(json);
}

/// @nodoc
mixin _$SubLesson {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;

  /// Ordering index within the parent lesson.
  int get sortOrder => throw _privateConstructorUsedError;

  /// The interactions that make up this sub-lesson.
  List<Stage> get stages => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $SubLessonCopyWith<SubLesson> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SubLessonCopyWith<$Res> {
  factory $SubLessonCopyWith(SubLesson value, $Res Function(SubLesson) then) =
      _$SubLessonCopyWithImpl<$Res, SubLesson>;
  @useResult
  $Res call(
      {String id,
      String name,
      String description,
      int sortOrder,
      List<Stage> stages});
}

/// @nodoc
class _$SubLessonCopyWithImpl<$Res, $Val extends SubLesson>
    implements $SubLessonCopyWith<$Res> {
  _$SubLessonCopyWithImpl(this._value, this._then);

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
    Object? sortOrder = null,
    Object? stages = null,
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
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
      stages: null == stages
          ? _value.stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SubLessonImplCopyWith<$Res>
    implements $SubLessonCopyWith<$Res> {
  factory _$$SubLessonImplCopyWith(
          _$SubLessonImpl value, $Res Function(_$SubLessonImpl) then) =
      __$$SubLessonImplCopyWithImpl<$Res>;
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
class __$$SubLessonImplCopyWithImpl<$Res>
    extends _$SubLessonCopyWithImpl<$Res, _$SubLessonImpl>
    implements _$$SubLessonImplCopyWith<$Res> {
  __$$SubLessonImplCopyWithImpl(
      _$SubLessonImpl _value, $Res Function(_$SubLessonImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = null,
    Object? sortOrder = null,
    Object? stages = null,
  }) {
    return _then(_$SubLessonImpl(
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
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
      stages: null == stages
          ? _value._stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SubLessonImpl implements _SubLesson {
  const _$SubLessonImpl(
      {required this.id,
      required this.name,
      this.description = '',
      this.sortOrder = 0,
      final List<Stage> stages = const <Stage>[]})
      : _stages = stages;

  factory _$SubLessonImpl.fromJson(Map<String, dynamic> json) =>
      _$$SubLessonImplFromJson(json);

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

  @override
  String toString() {
    return 'SubLesson(id: $id, name: $name, description: $description, sortOrder: $sortOrder, stages: $stages)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SubLessonImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder) &&
            const DeepCollectionEquality().equals(other._stages, _stages));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, description, sortOrder,
      const DeepCollectionEquality().hash(_stages));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SubLessonImplCopyWith<_$SubLessonImpl> get copyWith =>
      __$$SubLessonImplCopyWithImpl<_$SubLessonImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SubLessonImplToJson(
      this,
    );
  }
}

abstract class _SubLesson implements SubLesson {
  const factory _SubLesson(
      {required final String id,
      required final String name,
      final String description,
      final int sortOrder,
      final List<Stage> stages}) = _$SubLessonImpl;

  factory _SubLesson.fromJson(Map<String, dynamic> json) =
      _$SubLessonImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get description;
  @override

  /// Ordering index within the parent lesson.
  int get sortOrder;
  @override

  /// The interactions that make up this sub-lesson.
  List<Stage> get stages;
  @override
  @JsonKey(ignore: true)
  _$$SubLessonImplCopyWith<_$SubLessonImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
