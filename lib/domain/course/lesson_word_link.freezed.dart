// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lesson_word_link.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LessonWordLink {
  String get wordId;
  String get lessonId;
  String get lessonName;
  LinkType get type;
  DateTime get firstSeenAt;

  /// Create a copy of LessonWordLink
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LessonWordLinkCopyWith<LessonWordLink> get copyWith =>
      _$LessonWordLinkCopyWithImpl<LessonWordLink>(
          this as LessonWordLink, _$identity);

  /// Serializes this LessonWordLink to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LessonWordLink &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.lessonId, lessonId) ||
                other.lessonId == lessonId) &&
            (identical(other.lessonName, lessonName) ||
                other.lessonName == lessonName) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.firstSeenAt, firstSeenAt) ||
                other.firstSeenAt == firstSeenAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, wordId, lessonId, lessonName, type, firstSeenAt);

  @override
  String toString() {
    return 'LessonWordLink(wordId: $wordId, lessonId: $lessonId, lessonName: $lessonName, type: $type, firstSeenAt: $firstSeenAt)';
  }
}

/// @nodoc
abstract mixin class $LessonWordLinkCopyWith<$Res> {
  factory $LessonWordLinkCopyWith(
          LessonWordLink value, $Res Function(LessonWordLink) _then) =
      _$LessonWordLinkCopyWithImpl;
  @useResult
  $Res call(
      {String wordId,
      String lessonId,
      String lessonName,
      LinkType type,
      DateTime firstSeenAt});
}

/// @nodoc
class _$LessonWordLinkCopyWithImpl<$Res>
    implements $LessonWordLinkCopyWith<$Res> {
  _$LessonWordLinkCopyWithImpl(this._self, this._then);

  final LessonWordLink _self;
  final $Res Function(LessonWordLink) _then;

  /// Create a copy of LessonWordLink
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? wordId = null,
    Object? lessonId = null,
    Object? lessonName = null,
    Object? type = null,
    Object? firstSeenAt = null,
  }) {
    return _then(_self.copyWith(
      wordId: null == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _self.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonName: null == lessonName
          ? _self.lessonName
          : lessonName // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as LinkType,
      firstSeenAt: null == firstSeenAt
          ? _self.firstSeenAt
          : firstSeenAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// Adds pattern-matching-related methods to [LessonWordLink].
extension LessonWordLinkPatterns on LessonWordLink {
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
    TResult Function(_LessonWordLink value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _LessonWordLink() when $default != null:
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
    TResult Function(_LessonWordLink value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonWordLink():
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
    TResult? Function(_LessonWordLink value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonWordLink() when $default != null:
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
    TResult Function(String wordId, String lessonId, String lessonName,
            LinkType type, DateTime firstSeenAt)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _LessonWordLink() when $default != null:
        return $default(_that.wordId, _that.lessonId, _that.lessonName,
            _that.type, _that.firstSeenAt);
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
    TResult Function(String wordId, String lessonId, String lessonName,
            LinkType type, DateTime firstSeenAt)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonWordLink():
        return $default(_that.wordId, _that.lessonId, _that.lessonName,
            _that.type, _that.firstSeenAt);
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
    TResult? Function(String wordId, String lessonId, String lessonName,
            LinkType type, DateTime firstSeenAt)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _LessonWordLink() when $default != null:
        return $default(_that.wordId, _that.lessonId, _that.lessonName,
            _that.type, _that.firstSeenAt);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _LessonWordLink implements LessonWordLink {
  const _LessonWordLink(
      {required this.wordId,
      required this.lessonId,
      required this.lessonName,
      this.type = LinkType.word,
      required this.firstSeenAt});
  factory _LessonWordLink.fromJson(Map<String, dynamic> json) =>
      _$LessonWordLinkFromJson(json);

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

  /// Create a copy of LessonWordLink
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$LessonWordLinkCopyWith<_LessonWordLink> get copyWith =>
      __$LessonWordLinkCopyWithImpl<_LessonWordLink>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$LessonWordLinkToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _LessonWordLink &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.lessonId, lessonId) ||
                other.lessonId == lessonId) &&
            (identical(other.lessonName, lessonName) ||
                other.lessonName == lessonName) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.firstSeenAt, firstSeenAt) ||
                other.firstSeenAt == firstSeenAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, wordId, lessonId, lessonName, type, firstSeenAt);

  @override
  String toString() {
    return 'LessonWordLink(wordId: $wordId, lessonId: $lessonId, lessonName: $lessonName, type: $type, firstSeenAt: $firstSeenAt)';
  }
}

/// @nodoc
abstract mixin class _$LessonWordLinkCopyWith<$Res>
    implements $LessonWordLinkCopyWith<$Res> {
  factory _$LessonWordLinkCopyWith(
          _LessonWordLink value, $Res Function(_LessonWordLink) _then) =
      __$LessonWordLinkCopyWithImpl;
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
class __$LessonWordLinkCopyWithImpl<$Res>
    implements _$LessonWordLinkCopyWith<$Res> {
  __$LessonWordLinkCopyWithImpl(this._self, this._then);

  final _LessonWordLink _self;
  final $Res Function(_LessonWordLink) _then;

  /// Create a copy of LessonWordLink
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? wordId = null,
    Object? lessonId = null,
    Object? lessonName = null,
    Object? type = null,
    Object? firstSeenAt = null,
  }) {
    return _then(_LessonWordLink(
      wordId: null == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonId: null == lessonId
          ? _self.lessonId
          : lessonId // ignore: cast_nullable_to_non_nullable
              as String,
      lessonName: null == lessonName
          ? _self.lessonName
          : lessonName // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as LinkType,
      firstSeenAt: null == firstSeenAt
          ? _self.firstSeenAt
          : firstSeenAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

// dart format on
