// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lesson_content.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

LessonContent _$LessonContentFromJson(Map<String, dynamic> json) {
  return _LessonContent.fromJson(json);
}

/// @nodoc
mixin _$LessonContent {
  /// Legacy / default flat stage list. Used by review, challenge, and
  /// reading-comprehension questions.
  List<Stage> get stages => throw _privateConstructorUsedError;

  /// Intro / practice lessons split their content into sub-lessons.
  List<SubLesson> get subLessons => throw _privateConstructorUsedError;

  /// Listening lessons divide into phases (word pairing, dialogue, summary).
  List<ListeningPhase> get listeningPhases =>
      throw _privateConstructorUsedError;

  /// Structured reading passage for reading lessons.
  ReadingPassage? get readingPassage => throw _privateConstructorUsedError;

  /// Deprecated: optional reading passage as a plain string. Kept for
  /// backward compatibility; prefer [readingPassage].
  String get passage => throw _privateConstructorUsedError;

  /// Optional audio asset for listening lessons (legacy single-audio path).
  String? get audioAsset => throw _privateConstructorUsedError;

  /// Grammar point ids this lesson teaches. Used to register grammar points
  /// into the grammar-review SRS queue when the lesson is opened.
  List<String> get linkedGrammarPointIds => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $LessonContentCopyWith<LessonContent> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $LessonContentCopyWith<$Res> {
  factory $LessonContentCopyWith(
          LessonContent value, $Res Function(LessonContent) then) =
      _$LessonContentCopyWithImpl<$Res, LessonContent>;
  @useResult
  $Res call(
      {List<Stage> stages,
      List<SubLesson> subLessons,
      List<ListeningPhase> listeningPhases,
      ReadingPassage? readingPassage,
      String passage,
      String? audioAsset,
      List<String> linkedGrammarPointIds});

  $ReadingPassageCopyWith<$Res>? get readingPassage;
}

/// @nodoc
class _$LessonContentCopyWithImpl<$Res, $Val extends LessonContent>
    implements $LessonContentCopyWith<$Res> {
  _$LessonContentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? stages = null,
    Object? subLessons = null,
    Object? listeningPhases = null,
    Object? readingPassage = freezed,
    Object? passage = null,
    Object? audioAsset = freezed,
    Object? linkedGrammarPointIds = null,
  }) {
    return _then(_value.copyWith(
      stages: null == stages
          ? _value.stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
      subLessons: null == subLessons
          ? _value.subLessons
          : subLessons // ignore: cast_nullable_to_non_nullable
              as List<SubLesson>,
      listeningPhases: null == listeningPhases
          ? _value.listeningPhases
          : listeningPhases // ignore: cast_nullable_to_non_nullable
              as List<ListeningPhase>,
      readingPassage: freezed == readingPassage
          ? _value.readingPassage
          : readingPassage // ignore: cast_nullable_to_non_nullable
              as ReadingPassage?,
      passage: null == passage
          ? _value.passage
          : passage // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      linkedGrammarPointIds: null == linkedGrammarPointIds
          ? _value.linkedGrammarPointIds
          : linkedGrammarPointIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ReadingPassageCopyWith<$Res>? get readingPassage {
    if (_value.readingPassage == null) {
      return null;
    }

    return $ReadingPassageCopyWith<$Res>(_value.readingPassage!, (value) {
      return _then(_value.copyWith(readingPassage: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$LessonContentImplCopyWith<$Res>
    implements $LessonContentCopyWith<$Res> {
  factory _$$LessonContentImplCopyWith(
          _$LessonContentImpl value, $Res Function(_$LessonContentImpl) then) =
      __$$LessonContentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<Stage> stages,
      List<SubLesson> subLessons,
      List<ListeningPhase> listeningPhases,
      ReadingPassage? readingPassage,
      String passage,
      String? audioAsset,
      List<String> linkedGrammarPointIds});

  @override
  $ReadingPassageCopyWith<$Res>? get readingPassage;
}

/// @nodoc
class __$$LessonContentImplCopyWithImpl<$Res>
    extends _$LessonContentCopyWithImpl<$Res, _$LessonContentImpl>
    implements _$$LessonContentImplCopyWith<$Res> {
  __$$LessonContentImplCopyWithImpl(
      _$LessonContentImpl _value, $Res Function(_$LessonContentImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? stages = null,
    Object? subLessons = null,
    Object? listeningPhases = null,
    Object? readingPassage = freezed,
    Object? passage = null,
    Object? audioAsset = freezed,
    Object? linkedGrammarPointIds = null,
  }) {
    return _then(_$LessonContentImpl(
      stages: null == stages
          ? _value._stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
      subLessons: null == subLessons
          ? _value._subLessons
          : subLessons // ignore: cast_nullable_to_non_nullable
              as List<SubLesson>,
      listeningPhases: null == listeningPhases
          ? _value._listeningPhases
          : listeningPhases // ignore: cast_nullable_to_non_nullable
              as List<ListeningPhase>,
      readingPassage: freezed == readingPassage
          ? _value.readingPassage
          : readingPassage // ignore: cast_nullable_to_non_nullable
              as ReadingPassage?,
      passage: null == passage
          ? _value.passage
          : passage // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      linkedGrammarPointIds: null == linkedGrammarPointIds
          ? _value._linkedGrammarPointIds
          : linkedGrammarPointIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$LessonContentImpl implements _LessonContent {
  const _$LessonContentImpl(
      {final List<Stage> stages = const <Stage>[],
      final List<SubLesson> subLessons = const <SubLesson>[],
      final List<ListeningPhase> listeningPhases = const <ListeningPhase>[],
      this.readingPassage,
      this.passage = '',
      this.audioAsset,
      final List<String> linkedGrammarPointIds = const <String>[]})
      : _stages = stages,
        _subLessons = subLessons,
        _listeningPhases = listeningPhases,
        _linkedGrammarPointIds = linkedGrammarPointIds;

  factory _$LessonContentImpl.fromJson(Map<String, dynamic> json) =>
      _$$LessonContentImplFromJson(json);

  /// Legacy / default flat stage list. Used by review, challenge, and
  /// reading-comprehension questions.
  final List<Stage> _stages;

  /// Legacy / default flat stage list. Used by review, challenge, and
  /// reading-comprehension questions.
  @override
  @JsonKey()
  List<Stage> get stages {
    if (_stages is EqualUnmodifiableListView) return _stages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_stages);
  }

  /// Intro / practice lessons split their content into sub-lessons.
  final List<SubLesson> _subLessons;

  /// Intro / practice lessons split their content into sub-lessons.
  @override
  @JsonKey()
  List<SubLesson> get subLessons {
    if (_subLessons is EqualUnmodifiableListView) return _subLessons;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_subLessons);
  }

  /// Listening lessons divide into phases (word pairing, dialogue, summary).
  final List<ListeningPhase> _listeningPhases;

  /// Listening lessons divide into phases (word pairing, dialogue, summary).
  @override
  @JsonKey()
  List<ListeningPhase> get listeningPhases {
    if (_listeningPhases is EqualUnmodifiableListView) return _listeningPhases;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_listeningPhases);
  }

  /// Structured reading passage for reading lessons.
  @override
  final ReadingPassage? readingPassage;

  /// Deprecated: optional reading passage as a plain string. Kept for
  /// backward compatibility; prefer [readingPassage].
  @override
  @JsonKey()
  final String passage;

  /// Optional audio asset for listening lessons (legacy single-audio path).
  @override
  final String? audioAsset;

  /// Grammar point ids this lesson teaches. Used to register grammar points
  /// into the grammar-review SRS queue when the lesson is opened.
  final List<String> _linkedGrammarPointIds;

  /// Grammar point ids this lesson teaches. Used to register grammar points
  /// into the grammar-review SRS queue when the lesson is opened.
  @override
  @JsonKey()
  List<String> get linkedGrammarPointIds {
    if (_linkedGrammarPointIds is EqualUnmodifiableListView)
      return _linkedGrammarPointIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_linkedGrammarPointIds);
  }

  @override
  String toString() {
    return 'LessonContent(stages: $stages, subLessons: $subLessons, listeningPhases: $listeningPhases, readingPassage: $readingPassage, passage: $passage, audioAsset: $audioAsset, linkedGrammarPointIds: $linkedGrammarPointIds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LessonContentImpl &&
            const DeepCollectionEquality().equals(other._stages, _stages) &&
            const DeepCollectionEquality()
                .equals(other._subLessons, _subLessons) &&
            const DeepCollectionEquality()
                .equals(other._listeningPhases, _listeningPhases) &&
            (identical(other.readingPassage, readingPassage) ||
                other.readingPassage == readingPassage) &&
            (identical(other.passage, passage) || other.passage == passage) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            const DeepCollectionEquality()
                .equals(other._linkedGrammarPointIds, _linkedGrammarPointIds));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_stages),
      const DeepCollectionEquality().hash(_subLessons),
      const DeepCollectionEquality().hash(_listeningPhases),
      readingPassage,
      passage,
      audioAsset,
      const DeepCollectionEquality().hash(_linkedGrammarPointIds));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$LessonContentImplCopyWith<_$LessonContentImpl> get copyWith =>
      __$$LessonContentImplCopyWithImpl<_$LessonContentImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$LessonContentImplToJson(
      this,
    );
  }
}

abstract class _LessonContent implements LessonContent {
  const factory _LessonContent(
      {final List<Stage> stages,
      final List<SubLesson> subLessons,
      final List<ListeningPhase> listeningPhases,
      final ReadingPassage? readingPassage,
      final String passage,
      final String? audioAsset,
      final List<String> linkedGrammarPointIds}) = _$LessonContentImpl;

  factory _LessonContent.fromJson(Map<String, dynamic> json) =
      _$LessonContentImpl.fromJson;

  @override

  /// Legacy / default flat stage list. Used by review, challenge, and
  /// reading-comprehension questions.
  List<Stage> get stages;
  @override

  /// Intro / practice lessons split their content into sub-lessons.
  List<SubLesson> get subLessons;
  @override

  /// Listening lessons divide into phases (word pairing, dialogue, summary).
  List<ListeningPhase> get listeningPhases;
  @override

  /// Structured reading passage for reading lessons.
  ReadingPassage? get readingPassage;
  @override

  /// Deprecated: optional reading passage as a plain string. Kept for
  /// backward compatibility; prefer [readingPassage].
  String get passage;
  @override

  /// Optional audio asset for listening lessons (legacy single-audio path).
  String? get audioAsset;
  @override

  /// Grammar point ids this lesson teaches. Used to register grammar points
  /// into the grammar-review SRS queue when the lesson is opened.
  List<String> get linkedGrammarPointIds;
  @override
  @JsonKey(ignore: true)
  _$$LessonContentImplCopyWith<_$LessonContentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
