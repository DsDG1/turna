// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lesson_word_link.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

LessonWordLink _$LessonWordLinkFromJson(Map<String, dynamic> json) {
  return _LessonWordLink.fromJson(json);
}

/// @nodoc
mixin _$LessonWordLink {
  String get wordId => throw _privateConstructorUsedError;
  String get lessonId => throw _privateConstructorUsedError;
  String get lessonName => throw _privateConstructorUsedError;
  LinkType get type => throw _privateConstructorUsedError;
  DateTime get firstSeenAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $LessonWordLinkCopyWith<LessonWordLink> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LessonWordLinkCopyWith<$Res> {
  factory $LessonWordLinkCopyWith(
          LessonWordLink value, $Res Function(LessonWordLink) then) =
      _$LessonWordLinkCopyWithImpl<$Res, LessonWordLink>;
  @useResult
  $Res call(
      {String wordId,
      String lessonId,
      String lessonName,
      LinkType type,
      DateTime firstSeenAt});
}

/// @nodoc
class _$LessonWordLinkCopyWithImpl<$Res, $Val extends LessonWordLink>
    implements $LessonWordLinkCopyWith<$Res> {
  _$LessonWordLinkCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? wordId = null,
    Object? lessonId = null,
    Object? lessonName = null,
    Object? type = null,
    Object? firstSeenAt = null,
  }) {
    return _then(_value.copyWith(
      wordId: null == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _value.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonName: null == lessonName
          ? _value.lessonName
          : lessonName // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as LinkType,
      firstSeenAt: null == firstSeenAt
          ? _value.firstSeenAt
          : firstSeenAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$LessonWordLinkImplCopyWith<$Res>
    implements $LessonWordLinkCopyWith<$Res> {
  factory _$$LessonWordLinkImplCopyWith(_$LessonWordLinkImpl value,
          $Res Function(_$LessonWordLinkImpl) then) =
      __$$LessonWordLinkImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String wordId,
      String lessonId,
      String lessonName,
      LinkType type,
      DateTime firstSeenAt});
}

/// @nodoc
class __$$LessonWordLinkImplCopyWithImpl<$Res>
    extends _$LessonWordLinkCopyWithImpl<$Res, _$LessonWordLinkImpl>
    implements _$$LessonWordLinkImplCopyWith<$Res> {
  __$$LessonWordLinkImplCopyWithImpl(
      _$LessonWordLinkImpl _value, $Res Function(_$LessonWordLinkImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? wordId = null,
    Object? lessonId = null,
    Object? lessonName = null,
    Object? type = null,
    Object? firstSeenAt = null,
  }) {
    return _then(_$LessonWordLinkImpl(
      wordId: null == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _value.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonName: null == lessonName
          ? _value.lessonName
          : lessonName // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as LinkType,
      firstSeenAt: null == firstSeenAt
          ? _value.firstSeenAt
          : firstSeenAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LessonWordLinkImpl implements _LessonWordLink {
  const _$LessonWordLinkImpl(
      {required this.wordId,
      required this.lessonId,
      required this.lessonName,
      this.type = LinkType.word,
      required this.firstSeenAt});

  factory _$LessonWordLinkImpl.fromJson(Map<String, dynamic> json) =>
      _$$LessonWordLinkImplFromJson(json);

  @override
  final String wordId;
  @override
  final String lessonId;
  @override
  final String lessonName;
  @override
  @JsonKey()
  final LinkType type;
  @override
  final DateTime firstSeenAt;

  @override
  String toString() {
    return 'LessonWordLink(wordId: $wordId, lessonId: $lessonId, lessonName: $lessonName, type: $type, firstSeenAt: $firstSeenAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LessonWordLinkImpl &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.lessonId, lessonId) ||
                other.lessonId == lessonId) &&
            (identical(other.lessonName, lessonName) ||
                other.lessonName == lessonName) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.firstSeenAt, firstSeenAt) ||
                other.firstSeenAt == firstSeenAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, wordId, lessonId, lessonName, type, firstSeenAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LessonWordLinkImplCopyWith<_$LessonWordLinkImpl> get copyWith =>
      __$$LessonWordLinkImplCopyWithImpl<_$LessonWordLinkImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LessonWordLinkImplToJson(
      this,
    );
  }
}

abstract class _LessonWordLink implements LessonWordLink {
  const factory _LessonWordLink(
      {required final String wordId,
      required final String lessonId,
      required final String lessonName,
      final LinkType type,
      required final DateTime firstSeenAt}) = _$LessonWordLinkImpl;

  factory _LessonWordLink.fromJson(Map<String, dynamic> json) =
      _$LessonWordLinkImpl.fromJson;

  @override
  String get wordId;
  @override
  String get lessonId;
  @override
  String get lessonName;
  @override
  LinkType get type;
  @override
  DateTime get firstSeenAt;
  @override
  @JsonKey(ignore: true)
  _$$LessonWordLinkImplCopyWith<_$LessonWordLinkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
