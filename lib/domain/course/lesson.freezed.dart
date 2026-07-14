// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lesson.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Lesson _$LessonFromJson(Map<String, dynamic> json) {
  return _Lesson.fromJson(json);
}

/// @nodoc
mixin _$Lesson {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  LessonType get type => throw _privateConstructorUsedError;

  /// Pedagogical template. If omitted, the loader/renderer fall back to
  /// a flat stage list for backward compatibility.
  LessonTemplate get template => throw _privateConstructorUsedError;
  List<String> get prerequisiteLessonIds => throw _privateConstructorUsedError;
  LessonContent get content => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $LessonCopyWith<Lesson> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LessonCopyWith<$Res> {
  factory $LessonCopyWith(Lesson value, $Res Function(Lesson) then) =
      _$LessonCopyWithImpl<$Res, Lesson>;
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
class _$LessonCopyWithImpl<$Res, $Val extends Lesson>
    implements $LessonCopyWith<$Res> {
  _$LessonCopyWithImpl(this._value, this._then);

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
    Object? type = null,
    Object? template = null,
    Object? prerequisiteLessonIds = null,
    Object? content = null,
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
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as LessonType,
      template: null == template
          ? _value.template
          : template // ignore: cast_nullable_to_non_nullable
              as LessonTemplate,
      prerequisiteLessonIds: null == prerequisiteLessonIds
          ? _value.prerequisiteLessonIds
          : prerequisiteLessonIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as LessonContent,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $LessonContentCopyWith<$Res> get content {
    return $LessonContentCopyWith<$Res>(_value.content, (value) {
      return _then(_value.copyWith(content: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$LessonImplCopyWith<$Res> implements $LessonCopyWith<$Res> {
  factory _$$LessonImplCopyWith(
          _$LessonImpl value, $Res Function(_$LessonImpl) then) =
      __$$LessonImplCopyWithImpl<$Res>;
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
class __$$LessonImplCopyWithImpl<$Res>
    extends _$LessonCopyWithImpl<$Res, _$LessonImpl>
    implements _$$LessonImplCopyWith<$Res> {
  __$$LessonImplCopyWithImpl(
      _$LessonImpl _value, $Res Function(_$LessonImpl) _then)
      : super(_value, _then);

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
    return _then(_$LessonImpl(
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
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as LessonType,
      template: null == template
          ? _value.template
          : template // ignore: cast_nullable_to_non_nullable
              as LessonTemplate,
      prerequisiteLessonIds: null == prerequisiteLessonIds
          ? _value._prerequisiteLessonIds
          : prerequisiteLessonIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as LessonContent,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LessonImpl extends _Lesson {
  const _$LessonImpl(
      {required this.id,
      required this.name,
      this.description = '',
      this.type = LessonType.normal,
      this.template = LessonTemplate.legacy,
      final List<String> prerequisiteLessonIds = const <String>[],
      required this.content})
      : _prerequisiteLessonIds = prerequisiteLessonIds,
        super._();

  factory _$LessonImpl.fromJson(Map<String, dynamic> json) =>
      _$$LessonImplFromJson(json);

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

  @override
  String toString() {
    return 'Lesson(id: $id, name: $name, description: $description, type: $type, template: $template, prerequisiteLessonIds: $prerequisiteLessonIds, content: $content)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LessonImpl &&
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

  @JsonKey(ignore: true)
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

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LessonImplCopyWith<_$LessonImpl> get copyWith =>
      __$$LessonImplCopyWithImpl<_$LessonImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LessonImplToJson(
      this,
    );
  }
}

abstract class _Lesson extends Lesson {
  const factory _Lesson(
      {required final String id,
      required final String name,
      final String description,
      final LessonType type,
      final LessonTemplate template,
      final List<String> prerequisiteLessonIds,
      required final LessonContent content}) = _$LessonImpl;
  const _Lesson._() : super._();

  factory _Lesson.fromJson(Map<String, dynamic> json) = _$LessonImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get description;
  @override
  LessonType get type;
  @override

  /// Pedagogical template. If omitted, the loader/renderer fall back to
  /// a flat stage list for backward compatibility.
  LessonTemplate get template;
  @override
  List<String> get prerequisiteLessonIds;
  @override
  LessonContent get content;
  @override
  @JsonKey(ignore: true)
  _$$LessonImplCopyWith<_$LessonImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
