// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lesson_content.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LessonContent {
  /// Legacy / default flat stage list. Used by review, challenge, and
  /// reading-comprehension questions.
  List<Stage> get stages;

  /// Intro / practice lessons split their content into sub-lessons.
  List<SubLesson> get subLessons;

  /// Listening lessons divide into phases (word pairing, dialogue, summary).
  List<ListeningPhase> get listeningPhases;

  /// Structured reading passage for reading lessons.
  ReadingPassage? get readingPassage;

  /// Deprecated: optional reading passage as a plain string. Kept for
  /// backward compatibility; prefer [readingPassage].
  String get passage;

  /// Optional audio asset for listening lessons (legacy single-audio path).
  String? get audioAsset;

  /// Grammar point ids this lesson teaches. Used to register grammar points
  /// into the grammar-review SRS queue when the lesson is opened.
  List<String> get linkedGrammarPointIds;

  /// Create a copy of LessonContent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LessonContentCopyWith<LessonContent> get copyWith =>
      _$LessonContentCopyWithImpl<LessonContent>(
          this as LessonContent, _$identity);

  /// Serializes this LessonContent to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LessonContent &&
            const DeepCollectionEquality().equals(other.stages, stages) &&
            const DeepCollectionEquality()
                .equals(other.subLessons, subLessons) &&
            const DeepCollectionEquality()
                .equals(other.listeningPhases, listeningPhases) &&
            (identical(other.readingPassage, readingPassage) ||
                other.readingPassage == readingPassage) &&
            (identical(other.passage, passage) || other.passage == passage) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            const DeepCollectionEquality()
                .equals(other.linkedGrammarPointIds, linkedGrammarPointIds));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(stages),
      const DeepCollectionEquality().hash(subLessons),
      const DeepCollectionEquality().hash(listeningPhases),
      readingPassage,
      passage,
      audioAsset,
      const DeepCollectionEquality().hash(linkedGrammarPointIds));

  @override
  String toString() {
    return 'LessonContent(stages: $stages, subLessons: $subLessons, listeningPhases: $listeningPhases, readingPassage: $readingPassage, passage: $passage, audioAsset: $audioAsset, linkedGrammarPointIds: $linkedGrammarPointIds)';
  }
}

/// @nodoc
abstract mixin class $LessonContentCopyWith<$Res> {
  factory $LessonContentCopyWith(
          LessonContent value, $Res Function(LessonContent) _then) =
      _$LessonContentCopyWithImpl;
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
class _$LessonContentCopyWithImpl<$Res>
    implements $LessonContentCopyWith<$Res> {
  _$LessonContentCopyWithImpl(this._self, this._then);

  final LessonContent _self;
  final $Res Function(LessonContent) _then;

  /// Create a copy of LessonContent
  /// with the given fields replaced by the non-null parameter values.
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
    return _then(_self.copyWith(
      stages: null == stages
          ? _self.stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
      subLessons: null == subLessons
          ? _self.subLessons
          : subLessons // ignore: cast_nullable_to_non_nullable
              as List<SubLesson>,
      listeningPhases: null == listeningPhases
          ? _self.listeningPhases
          : listeningPhases // ignore: cast_nullable_to_non_nullable
              as List<ListeningPhase>,
      readingPassage: freezed == readingPassage
          ? _self.readingPassage
          : readingPassage // ignore: cast_nullable_to_non_nullable
              as ReadingPassage?,
      passage: null == passage
          ? _self.passage
          : passage // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      linkedGrammarPointIds: null == linkedGrammarPointIds
          ? _self.linkedGrammarPointIds
          : linkedGrammarPointIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }

  /// Create a copy of LessonContent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ReadingPassageCopyWith<$Res>? get readingPassage {
    if (_self.readingPassage == null) {
      return null;
    }

    return $ReadingPassageCopyWith<$Res>(_self.readingPassage!, (value) {
      return _then(_self.copyWith(readingPassage: value));
    });
  }
}

/// Adds pattern-matching-related methods to [LessonContent].
extension LessonContentPatterns on LessonContent {
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
    TResult Function(_LessonContent value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _LessonContent() when $default != null:
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
    TResult Function(_LessonContent value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonContent():
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
    TResult? Function(_LessonContent value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonContent() when $default != null:
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
            List<Stage> stages,
            List<SubLesson> subLessons,
            List<ListeningPhase> listeningPhases,
            ReadingPassage? readingPassage,
            String passage,
            String? audioAsset,
            List<String> linkedGrammarPointIds)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _LessonContent() when $default != null:
        return $default(
            _that.stages,
            _that.subLessons,
            _that.listeningPhases,
            _that.readingPassage,
            _that.passage,
            _that.audioAsset,
            _that.linkedGrammarPointIds);
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
            List<Stage> stages,
            List<SubLesson> subLessons,
            List<ListeningPhase> listeningPhases,
            ReadingPassage? readingPassage,
            String passage,
            String? audioAsset,
            List<String> linkedGrammarPointIds)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonContent():
        return $default(
            _that.stages,
            _that.subLessons,
            _that.listeningPhases,
            _that.readingPassage,
            _that.passage,
            _that.audioAsset,
            _that.linkedGrammarPointIds);
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
            List<Stage> stages,
            List<SubLesson> subLessons,
            List<ListeningPhase> listeningPhases,
            ReadingPassage? readingPassage,
            String passage,
            String? audioAsset,
            List<String> linkedGrammarPointIds)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonContent() when $default != null:
        return $default(
            _that.stages,
            _that.subLessons,
            _that.listeningPhases,
            _that.readingPassage,
            _that.passage,
            _that.audioAsset,
            _that.linkedGrammarPointIds);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _LessonContent implements LessonContent {
  const _LessonContent(
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
  factory _LessonContent.fromJson(Map<String, dynamic> json) =>
      _$LessonContentFromJson(json);

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

  /// Create a copy of LessonContent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$LessonContentCopyWith<_LessonContent> get copyWith =>
      __$LessonContentCopyWithImpl<_LessonContent>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$LessonContentToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _LessonContent &&
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

  @JsonKey(includeFromJson: false, includeToJson: false)
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

  @override
  String toString() {
    return 'LessonContent(stages: $stages, subLessons: $subLessons, listeningPhases: $listeningPhases, readingPassage: $readingPassage, passage: $passage, audioAsset: $audioAsset, linkedGrammarPointIds: $linkedGrammarPointIds)';
  }
}

/// @nodoc
abstract mixin class _$LessonContentCopyWith<$Res>
    implements $LessonContentCopyWith<$Res> {
  factory _$LessonContentCopyWith(
          _LessonContent value, $Res Function(_LessonContent) _then) =
      __$LessonContentCopyWithImpl;
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
class __$LessonContentCopyWithImpl<$Res>
    implements _$LessonContentCopyWith<$Res> {
  __$LessonContentCopyWithImpl(this._self, this._then);

  final _LessonContent _self;
  final $Res Function(_LessonContent) _then;

  /// Create a copy of LessonContent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? stages = null,
    Object? subLessons = null,
    Object? listeningPhases = null,
    Object? readingPassage = freezed,
    Object? passage = null,
    Object? audioAsset = freezed,
    Object? linkedGrammarPointIds = null,
  }) {
    return _then(_LessonContent(
      stages: null == stages
          ? _self._stages
          : stages // ignore: cast_nullable_to_non_nullable
              as List<Stage>,
      subLessons: null == subLessons
          ? _self._subLessons
          : subLessons // ignore: cast_nullable_to_non_nullable
              as List<SubLesson>,
      listeningPhases: null == listeningPhases
          ? _self._listeningPhases
          : listeningPhases // ignore: cast_nullable_to_non_nullable
              as List<ListeningPhase>,
      readingPassage: freezed == readingPassage
          ? _self.readingPassage
          : readingPassage // ignore: cast_nullable_to_non_nullable
              as ReadingPassage?,
      passage: null == passage
          ? _self.passage
          : passage // ignore: cast_nullable_to_non_nullable
              as String,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      linkedGrammarPointIds: null == linkedGrammarPointIds
          ? _self._linkedGrammarPointIds
          : linkedGrammarPointIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }

  /// Create a copy of LessonContent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ReadingPassageCopyWith<$Res>? get readingPassage {
    if (_self.readingPassage == null) {
      return null;
    }

    return $ReadingPassageCopyWith<$Res>(_self.readingPassage!, (value) {
      return _then(_self.copyWith(readingPassage: value));
    });
  }
}

// dart format on
