// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reading_passage.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ReadingPassage _$ReadingPassageFromJson(Map<String, dynamic> json) {
  return _ReadingPassage.fromJson(json);
}

/// @nodoc
mixin _$ReadingPassage {
  /// Passage title.
  String get title => throw _privateConstructorUsedError;

  /// Paragraphs of the passage.
  List<String> get paragraphs => throw _privateConstructorUsedError;

  /// Approximate CEFR difficulty: 1=A1, 2=A2, 3=B1, 4=B2, etc.
  int get difficulty => throw _privateConstructorUsedError;

  /// IDs of words introduced or highlighted in this passage.
  List<String> get linkedWordIds => throw _privateConstructorUsedError;

  /// IDs of expressions highlighted in this passage.
  List<String> get linkedExpressionIds => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ReadingPassageCopyWith<ReadingPassage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ReadingPassageCopyWith<$Res> {
  factory $ReadingPassageCopyWith(
          ReadingPassage value, $Res Function(ReadingPassage) then) =
      _$ReadingPassageCopyWithImpl<$Res, ReadingPassage>;
  @useResult
  $Res call(
      {String title,
      List<String> paragraphs,
      int difficulty,
      List<String> linkedWordIds,
      List<String> linkedExpressionIds});
}

/// @nodoc
class _$ReadingPassageCopyWithImpl<$Res, $Val extends ReadingPassage>
    implements $ReadingPassageCopyWith<$Res> {
  _$ReadingPassageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? paragraphs = null,
    Object? difficulty = null,
    Object? linkedWordIds = null,
    Object? linkedExpressionIds = null,
  }) {
    return _then(_value.copyWith(
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      paragraphs: null == paragraphs
          ? _value.paragraphs
          : paragraphs // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
      linkedWordIds: null == linkedWordIds
          ? _value.linkedWordIds
          : linkedWordIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      linkedExpressionIds: null == linkedExpressionIds
          ? _value.linkedExpressionIds
          : linkedExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ReadingPassageImplCopyWith<$Res>
    implements $ReadingPassageCopyWith<$Res> {
  factory _$$ReadingPassageImplCopyWith(_$ReadingPassageImpl value,
          $Res Function(_$ReadingPassageImpl) then) =
      __$$ReadingPassageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String title,
      List<String> paragraphs,
      int difficulty,
      List<String> linkedWordIds,
      List<String> linkedExpressionIds});
}

/// @nodoc
class __$$ReadingPassageImplCopyWithImpl<$Res>
    extends _$ReadingPassageCopyWithImpl<$Res, _$ReadingPassageImpl>
    implements _$$ReadingPassageImplCopyWith<$Res> {
  __$$ReadingPassageImplCopyWithImpl(
      _$ReadingPassageImpl _value, $Res Function(_$ReadingPassageImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? title = null,
    Object? paragraphs = null,
    Object? difficulty = null,
    Object? linkedWordIds = null,
    Object? linkedExpressionIds = null,
  }) {
    return _then(_$ReadingPassageImpl(
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      paragraphs: null == paragraphs
          ? _value._paragraphs
          : paragraphs // ignore: cast_nullable_to_non_nullable
              as List<String>,
      difficulty: null == difficulty
          ? _value.difficulty
          : difficulty // ignore: cast_nullable_to_non_nullable
              as int,
      linkedWordIds: null == linkedWordIds
          ? _value._linkedWordIds
          : linkedWordIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      linkedExpressionIds: null == linkedExpressionIds
          ? _value._linkedExpressionIds
          : linkedExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ReadingPassageImpl implements _ReadingPassage {
  const _$ReadingPassageImpl(
      {required this.title,
      final List<String> paragraphs = const <String>[],
      this.difficulty = 1,
      final List<String> linkedWordIds = const <String>[],
      final List<String> linkedExpressionIds = const <String>[]})
      : _paragraphs = paragraphs,
        _linkedWordIds = linkedWordIds,
        _linkedExpressionIds = linkedExpressionIds;

  factory _$ReadingPassageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ReadingPassageImplFromJson(json);

  /// Passage title.
  @override
  final String title;

  /// Paragraphs of the passage.
  final List<String> _paragraphs;

  /// Paragraphs of the passage.
  @override
  @JsonKey()
  List<String> get paragraphs {
    if (_paragraphs is EqualUnmodifiableListView) return _paragraphs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_paragraphs);
  }

  /// Approximate CEFR difficulty: 1=A1, 2=A2, 3=B1, 4=B2, etc.
  @override
  @JsonKey()
  final int difficulty;

  /// IDs of words introduced or highlighted in this passage.
  final List<String> _linkedWordIds;

  /// IDs of words introduced or highlighted in this passage.
  @override
  @JsonKey()
  List<String> get linkedWordIds {
    if (_linkedWordIds is EqualUnmodifiableListView) return _linkedWordIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedWordIds);
  }

  /// IDs of expressions highlighted in this passage.
  final List<String> _linkedExpressionIds;

  /// IDs of expressions highlighted in this passage.
  @override
  @JsonKey()
  List<String> get linkedExpressionIds {
    if (_linkedExpressionIds is EqualUnmodifiableListView)
      return _linkedExpressionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedExpressionIds);
  }

  @override
  String toString() {
    return 'ReadingPassage(title: $title, paragraphs: $paragraphs, difficulty: $difficulty, linkedWordIds: $linkedWordIds, linkedExpressionIds: $linkedExpressionIds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReadingPassageImpl &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality()
                .equals(other._paragraphs, _paragraphs) &&
            (identical(other.difficulty, difficulty) ||
                other.difficulty == difficulty) &&
            const DeepCollectionEquality()
                .equals(other._linkedWordIds, _linkedWordIds) &&
            const DeepCollectionEquality()
                .equals(other._linkedExpressionIds, _linkedExpressionIds));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      title,
      const DeepCollectionEquality().hash(_paragraphs),
      difficulty,
      const DeepCollectionEquality().hash(_linkedWordIds),
      const DeepCollectionEquality().hash(_linkedExpressionIds));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ReadingPassageImplCopyWith<_$ReadingPassageImpl> get copyWith =>
      __$$ReadingPassageImplCopyWithImpl<_$ReadingPassageImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ReadingPassageImplToJson(
      this,
    );
  }
}

abstract class _ReadingPassage implements ReadingPassage {
  const factory _ReadingPassage(
      {required final String title,
      final List<String> paragraphs,
      final int difficulty,
      final List<String> linkedWordIds,
      final List<String> linkedExpressionIds}) = _$ReadingPassageImpl;

  factory _ReadingPassage.fromJson(Map<String, dynamic> json) =
      _$ReadingPassageImpl.fromJson;

  @override

  /// Passage title.
  String get title;
  @override

  /// Paragraphs of the passage.
  List<String> get paragraphs;
  @override

  /// Approximate CEFR difficulty: 1=A1, 2=A2, 3=B1, 4=B2, etc.
  int get difficulty;
  @override

  /// IDs of words introduced or highlighted in this passage.
  List<String> get linkedWordIds;
  @override

  /// IDs of expressions highlighted in this passage.
  List<String> get linkedExpressionIds;
  @override
  @JsonKey(ignore: true)
  _$$ReadingPassageImplCopyWith<_$ReadingPassageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
