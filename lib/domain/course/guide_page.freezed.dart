// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'guide_page.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GuidePage {
  String get id;
  String get title;
  String get kicker;
  String get intro;
  List<GuideBlock> get blocks;
  String? get nextLabel;
  String? get nextLessonId;
  String? get nextSubLessonId;

  /// Create a copy of GuidePage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuidePageCopyWith<GuidePage> get copyWith =>
      _$GuidePageCopyWithImpl<GuidePage>(this as GuidePage, _$identity);

  /// Serializes this GuidePage to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuidePage &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.kicker, kicker) || other.kicker == kicker) &&
            (identical(other.intro, intro) || other.intro == intro) &&
            const DeepCollectionEquality().equals(other.blocks, blocks) &&
            (identical(other.nextLabel, nextLabel) ||
                other.nextLabel == nextLabel) &&
            (identical(other.nextLessonId, nextLessonId) ||
                other.nextLessonId == nextLessonId) &&
            (identical(other.nextSubLessonId, nextSubLessonId) ||
                other.nextSubLessonId == nextSubLessonId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      kicker,
      intro,
      const DeepCollectionEquality().hash(blocks),
      nextLabel,
      nextLessonId,
      nextSubLessonId);

  @override
  String toString() {
    return 'GuidePage(id: $id, title: $title, kicker: $kicker, intro: $intro, blocks: $blocks, nextLabel: $nextLabel, nextLessonId: $nextLessonId, nextSubLessonId: $nextSubLessonId)';
  }
}

/// @nodoc
abstract mixin class $GuidePageCopyWith<$Res> {
  factory $GuidePageCopyWith(GuidePage value, $Res Function(GuidePage) _then) =
      _$GuidePageCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String title,
      String kicker,
      String intro,
      List<GuideBlock> blocks,
      String? nextLabel,
      String? nextLessonId,
      String? nextSubLessonId});
}

/// @nodoc
class _$GuidePageCopyWithImpl<$Res> implements $GuidePageCopyWith<$Res> {
  _$GuidePageCopyWithImpl(this._self, this._then);

  final GuidePage _self;
  final $Res Function(GuidePage) _then;

  /// Create a copy of GuidePage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? kicker = null,
    Object? intro = null,
    Object? blocks = null,
    Object? nextLabel = freezed,
    Object? nextLessonId = freezed,
    Object? nextSubLessonId = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      kicker: null == kicker
          ? _self.kicker
          : kicker // ignore: cast_nullable_to_non_nullable
              as String,
      intro: null == intro
          ? _self.intro
          : intro // ignore: cast_nullable_to_non_nullable
              as String,
      blocks: null == blocks
          ? _self.blocks
          : blocks // ignore: cast_nullable_to_non_nullable
              as List<GuideBlock>,
      nextLabel: freezed == nextLabel
          ? _self.nextLabel
          : nextLabel // ignore: cast_nullable_to_non_nullable
              as String?,
      nextLessonId: freezed == nextLessonId
          ? _self.nextLessonId
          : nextLessonId // ignore: cast_nullable_to_non_nullable
              as String?,
      nextSubLessonId: freezed == nextSubLessonId
          ? _self.nextSubLessonId
          : nextSubLessonId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuidePage].
extension GuidePagePatterns on GuidePage {
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
    TResult Function(_GuidePage value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuidePage() when $default != null:
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
    TResult Function(_GuidePage value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuidePage():
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
    TResult? Function(_GuidePage value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuidePage() when $default != null:
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
            String id,
            String title,
            String kicker,
            String intro,
            List<GuideBlock> blocks,
            String? nextLabel,
            String? nextLessonId,
            String? nextSubLessonId)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuidePage() when $default != null:
        return $default(
            _that.id,
            _that.title,
            _that.kicker,
            _that.intro,
            _that.blocks,
            _that.nextLabel,
            _that.nextLessonId,
            _that.nextSubLessonId);
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
            String id,
            String title,
            String kicker,
            String intro,
            List<GuideBlock> blocks,
            String? nextLabel,
            String? nextLessonId,
            String? nextSubLessonId)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuidePage():
        return $default(
            _that.id,
            _that.title,
            _that.kicker,
            _that.intro,
            _that.blocks,
            _that.nextLabel,
            _that.nextLessonId,
            _that.nextSubLessonId);
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
            String id,
            String title,
            String kicker,
            String intro,
            List<GuideBlock> blocks,
            String? nextLabel,
            String? nextLessonId,
            String? nextSubLessonId)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuidePage() when $default != null:
        return $default(
            _that.id,
            _that.title,
            _that.kicker,
            _that.intro,
            _that.blocks,
            _that.nextLabel,
            _that.nextLessonId,
            _that.nextSubLessonId);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuidePage implements GuidePage {
  const _GuidePage(
      {required this.id,
      required this.title,
      this.kicker = '',
      this.intro = '',
      final List<GuideBlock> blocks = const <GuideBlock>[],
      this.nextLabel,
      this.nextLessonId,
      this.nextSubLessonId})
      : _blocks = blocks;
  factory _GuidePage.fromJson(Map<String, dynamic> json) =>
      _$GuidePageFromJson(json);

  @override
  final String id;
  @override
  final String title;
  @override
  @JsonKey()
  final String kicker;
  @override
  @JsonKey()
  final String intro;
  final List<GuideBlock> _blocks;
  @override
  @JsonKey()
  List<GuideBlock> get blocks {
    if (_blocks is EqualUnmodifiableListView) return _blocks;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_blocks);
  }

  @override
  final String? nextLabel;
  @override
  final String? nextLessonId;
  @override
  final String? nextSubLessonId;

  /// Create a copy of GuidePage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuidePageCopyWith<_GuidePage> get copyWith =>
      __$GuidePageCopyWithImpl<_GuidePage>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuidePageToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuidePage &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.kicker, kicker) || other.kicker == kicker) &&
            (identical(other.intro, intro) || other.intro == intro) &&
            const DeepCollectionEquality().equals(other._blocks, _blocks) &&
            (identical(other.nextLabel, nextLabel) ||
                other.nextLabel == nextLabel) &&
            (identical(other.nextLessonId, nextLessonId) ||
                other.nextLessonId == nextLessonId) &&
            (identical(other.nextSubLessonId, nextSubLessonId) ||
                other.nextSubLessonId == nextSubLessonId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      kicker,
      intro,
      const DeepCollectionEquality().hash(_blocks),
      nextLabel,
      nextLessonId,
      nextSubLessonId);

  @override
  String toString() {
    return 'GuidePage(id: $id, title: $title, kicker: $kicker, intro: $intro, blocks: $blocks, nextLabel: $nextLabel, nextLessonId: $nextLessonId, nextSubLessonId: $nextSubLessonId)';
  }
}

/// @nodoc
abstract mixin class _$GuidePageCopyWith<$Res>
    implements $GuidePageCopyWith<$Res> {
  factory _$GuidePageCopyWith(
          _GuidePage value, $Res Function(_GuidePage) _then) =
      __$GuidePageCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String kicker,
      String intro,
      List<GuideBlock> blocks,
      String? nextLabel,
      String? nextLessonId,
      String? nextSubLessonId});
}

/// @nodoc
class __$GuidePageCopyWithImpl<$Res> implements _$GuidePageCopyWith<$Res> {
  __$GuidePageCopyWithImpl(this._self, this._then);

  final _GuidePage _self;
  final $Res Function(_GuidePage) _then;

  /// Create a copy of GuidePage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? kicker = null,
    Object? intro = null,
    Object? blocks = null,
    Object? nextLabel = freezed,
    Object? nextLessonId = freezed,
    Object? nextSubLessonId = freezed,
  }) {
    return _then(_GuidePage(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      kicker: null == kicker
          ? _self.kicker
          : kicker // ignore: cast_nullable_to_non_nullable
              as String,
      intro: null == intro
          ? _self.intro
          : intro // ignore: cast_nullable_to_non_nullable
              as String,
      blocks: null == blocks
          ? _self._blocks
          : blocks // ignore: cast_nullable_to_non_nullable
              as List<GuideBlock>,
      nextLabel: freezed == nextLabel
          ? _self.nextLabel
          : nextLabel // ignore: cast_nullable_to_non_nullable
              as String?,
      nextLessonId: freezed == nextLessonId
          ? _self.nextLessonId
          : nextLessonId // ignore: cast_nullable_to_non_nullable
              as String?,
      nextSubLessonId: freezed == nextSubLessonId
          ? _self.nextSubLessonId
          : nextSubLessonId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$GuideTerm {
  String get text;
  String get translation;
  String get note;
  String? get speechText;
  String? get wordId;

  /// Create a copy of GuideTerm
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideTermCopyWith<GuideTerm> get copyWith =>
      _$GuideTermCopyWithImpl<GuideTerm>(this as GuideTerm, _$identity);

  /// Serializes this GuideTerm to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideTerm &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.speechText, speechText) ||
                other.speechText == speechText) &&
            (identical(other.wordId, wordId) || other.wordId == wordId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, text, translation, note, speechText, wordId);

  @override
  String toString() {
    return 'GuideTerm(text: $text, translation: $translation, note: $note, speechText: $speechText, wordId: $wordId)';
  }
}

/// @nodoc
abstract mixin class $GuideTermCopyWith<$Res> {
  factory $GuideTermCopyWith(GuideTerm value, $Res Function(GuideTerm) _then) =
      _$GuideTermCopyWithImpl;
  @useResult
  $Res call(
      {String text,
      String translation,
      String note,
      String? speechText,
      String? wordId});
}

/// @nodoc
class _$GuideTermCopyWithImpl<$Res> implements $GuideTermCopyWith<$Res> {
  _$GuideTermCopyWithImpl(this._self, this._then);

  final GuideTerm _self;
  final $Res Function(GuideTerm) _then;

  /// Create a copy of GuideTerm
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
    Object? translation = null,
    Object? note = null,
    Object? speechText = freezed,
    Object? wordId = freezed,
  }) {
    return _then(_self.copyWith(
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _self.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      speechText: freezed == speechText
          ? _self.speechText
          : speechText // ignore: cast_nullable_to_non_nullable
              as String?,
      wordId: freezed == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideTerm].
extension GuideTermPatterns on GuideTerm {
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
    TResult Function(_GuideTerm value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideTerm() when $default != null:
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
    TResult Function(_GuideTerm value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideTerm():
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
    TResult? Function(_GuideTerm value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideTerm() when $default != null:
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
    TResult Function(String text, String translation, String note,
            String? speechText, String? wordId)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideTerm() when $default != null:
        return $default(_that.text, _that.translation, _that.note,
            _that.speechText, _that.wordId);
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
    TResult Function(String text, String translation, String note,
            String? speechText, String? wordId)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideTerm():
        return $default(_that.text, _that.translation, _that.note,
            _that.speechText, _that.wordId);
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
    TResult? Function(String text, String translation, String note,
            String? speechText, String? wordId)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideTerm() when $default != null:
        return $default(_that.text, _that.translation, _that.note,
            _that.speechText, _that.wordId);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuideTerm implements GuideTerm {
  const _GuideTerm(
      {required this.text,
      this.translation = '',
      this.note = '',
      this.speechText,
      this.wordId});
  factory _GuideTerm.fromJson(Map<String, dynamic> json) =>
      _$GuideTermFromJson(json);

  @override
  final String text;
  @override
  @JsonKey()
  final String translation;
  @override
  @JsonKey()
  final String note;
  @override
  final String? speechText;
  @override
  final String? wordId;

  /// Create a copy of GuideTerm
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuideTermCopyWith<_GuideTerm> get copyWith =>
      __$GuideTermCopyWithImpl<_GuideTerm>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideTermToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuideTerm &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.speechText, speechText) ||
                other.speechText == speechText) &&
            (identical(other.wordId, wordId) || other.wordId == wordId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, text, translation, note, speechText, wordId);

  @override
  String toString() {
    return 'GuideTerm(text: $text, translation: $translation, note: $note, speechText: $speechText, wordId: $wordId)';
  }
}

/// @nodoc
abstract mixin class _$GuideTermCopyWith<$Res>
    implements $GuideTermCopyWith<$Res> {
  factory _$GuideTermCopyWith(
          _GuideTerm value, $Res Function(_GuideTerm) _then) =
      __$GuideTermCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String text,
      String translation,
      String note,
      String? speechText,
      String? wordId});
}

/// @nodoc
class __$GuideTermCopyWithImpl<$Res> implements _$GuideTermCopyWith<$Res> {
  __$GuideTermCopyWithImpl(this._self, this._then);

  final _GuideTerm _self;
  final $Res Function(_GuideTerm) _then;

  /// Create a copy of GuideTerm
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? text = null,
    Object? translation = null,
    Object? note = null,
    Object? speechText = freezed,
    Object? wordId = freezed,
  }) {
    return _then(_GuideTerm(
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _self.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      speechText: freezed == speechText
          ? _self.speechText
          : speechText // ignore: cast_nullable_to_non_nullable
              as String?,
      wordId: freezed == wordId
          ? _self.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$GuideClassificationCategory {
  String get id;
  String get label;
  String get description;

  /// Create a copy of GuideClassificationCategory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideClassificationCategoryCopyWith<GuideClassificationCategory>
      get copyWith => _$GuideClassificationCategoryCopyWithImpl<
              GuideClassificationCategory>(
          this as GuideClassificationCategory, _$identity);

  /// Serializes this GuideClassificationCategory to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideClassificationCategory &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, label, description);

  @override
  String toString() {
    return 'GuideClassificationCategory(id: $id, label: $label, description: $description)';
  }
}

/// @nodoc
abstract mixin class $GuideClassificationCategoryCopyWith<$Res> {
  factory $GuideClassificationCategoryCopyWith(
          GuideClassificationCategory value,
          $Res Function(GuideClassificationCategory) _then) =
      _$GuideClassificationCategoryCopyWithImpl;
  @useResult
  $Res call({String id, String label, String description});
}

/// @nodoc
class _$GuideClassificationCategoryCopyWithImpl<$Res>
    implements $GuideClassificationCategoryCopyWith<$Res> {
  _$GuideClassificationCategoryCopyWithImpl(this._self, this._then);

  final GuideClassificationCategory _self;
  final $Res Function(GuideClassificationCategory) _then;

  /// Create a copy of GuideClassificationCategory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? label = null,
    Object? description = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      label: null == label
          ? _self.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideClassificationCategory].
extension GuideClassificationCategoryPatterns on GuideClassificationCategory {
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
    TResult Function(_GuideClassificationCategory value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCategory() when $default != null:
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
    TResult Function(_GuideClassificationCategory value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCategory():
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
    TResult? Function(_GuideClassificationCategory value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCategory() when $default != null:
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
    TResult Function(String id, String label, String description)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCategory() when $default != null:
        return $default(_that.id, _that.label, _that.description);
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
    TResult Function(String id, String label, String description) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCategory():
        return $default(_that.id, _that.label, _that.description);
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
    TResult? Function(String id, String label, String description)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCategory() when $default != null:
        return $default(_that.id, _that.label, _that.description);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuideClassificationCategory implements GuideClassificationCategory {
  const _GuideClassificationCategory(
      {required this.id, required this.label, this.description = ''});
  factory _GuideClassificationCategory.fromJson(Map<String, dynamic> json) =>
      _$GuideClassificationCategoryFromJson(json);

  @override
  final String id;
  @override
  final String label;
  @override
  @JsonKey()
  final String description;

  /// Create a copy of GuideClassificationCategory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuideClassificationCategoryCopyWith<_GuideClassificationCategory>
      get copyWith => __$GuideClassificationCategoryCopyWithImpl<
          _GuideClassificationCategory>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideClassificationCategoryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuideClassificationCategory &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, label, description);

  @override
  String toString() {
    return 'GuideClassificationCategory(id: $id, label: $label, description: $description)';
  }
}

/// @nodoc
abstract mixin class _$GuideClassificationCategoryCopyWith<$Res>
    implements $GuideClassificationCategoryCopyWith<$Res> {
  factory _$GuideClassificationCategoryCopyWith(
          _GuideClassificationCategory value,
          $Res Function(_GuideClassificationCategory) _then) =
      __$GuideClassificationCategoryCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String label, String description});
}

/// @nodoc
class __$GuideClassificationCategoryCopyWithImpl<$Res>
    implements _$GuideClassificationCategoryCopyWith<$Res> {
  __$GuideClassificationCategoryCopyWithImpl(this._self, this._then);

  final _GuideClassificationCategory _self;
  final $Res Function(_GuideClassificationCategory) _then;

  /// Create a copy of GuideClassificationCategory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? label = null,
    Object? description = null,
  }) {
    return _then(_GuideClassificationCategory(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      label: null == label
          ? _self.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$GuideClassificationCard {
  String get id;
  String get text;
  String get categoryId;
  String get hint;
  String get highlight;

  /// Create a copy of GuideClassificationCard
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideClassificationCardCopyWith<GuideClassificationCard> get copyWith =>
      _$GuideClassificationCardCopyWithImpl<GuideClassificationCard>(
          this as GuideClassificationCard, _$identity);

  /// Serializes this GuideClassificationCard to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideClassificationCard &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.categoryId, categoryId) ||
                other.categoryId == categoryId) &&
            (identical(other.hint, hint) || other.hint == hint) &&
            (identical(other.highlight, highlight) ||
                other.highlight == highlight));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, text, categoryId, hint, highlight);

  @override
  String toString() {
    return 'GuideClassificationCard(id: $id, text: $text, categoryId: $categoryId, hint: $hint, highlight: $highlight)';
  }
}

/// @nodoc
abstract mixin class $GuideClassificationCardCopyWith<$Res> {
  factory $GuideClassificationCardCopyWith(GuideClassificationCard value,
          $Res Function(GuideClassificationCard) _then) =
      _$GuideClassificationCardCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String text,
      String categoryId,
      String hint,
      String highlight});
}

/// @nodoc
class _$GuideClassificationCardCopyWithImpl<$Res>
    implements $GuideClassificationCardCopyWith<$Res> {
  _$GuideClassificationCardCopyWithImpl(this._self, this._then);

  final GuideClassificationCard _self;
  final $Res Function(GuideClassificationCard) _then;

  /// Create a copy of GuideClassificationCard
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? categoryId = null,
    Object? hint = null,
    Object? highlight = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      categoryId: null == categoryId
          ? _self.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String,
      hint: null == hint
          ? _self.hint
          : hint // ignore: cast_nullable_to_non_nullable
              as String,
      highlight: null == highlight
          ? _self.highlight
          : highlight // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideClassificationCard].
extension GuideClassificationCardPatterns on GuideClassificationCard {
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
    TResult Function(_GuideClassificationCard value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCard() when $default != null:
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
    TResult Function(_GuideClassificationCard value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCard():
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
    TResult? Function(_GuideClassificationCard value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCard() when $default != null:
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
    TResult Function(String id, String text, String categoryId, String hint,
            String highlight)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCard() when $default != null:
        return $default(_that.id, _that.text, _that.categoryId, _that.hint,
            _that.highlight);
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
    TResult Function(String id, String text, String categoryId, String hint,
            String highlight)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCard():
        return $default(_that.id, _that.text, _that.categoryId, _that.hint,
            _that.highlight);
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
    TResult? Function(String id, String text, String categoryId, String hint,
            String highlight)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideClassificationCard() when $default != null:
        return $default(_that.id, _that.text, _that.categoryId, _that.hint,
            _that.highlight);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuideClassificationCard implements GuideClassificationCard {
  const _GuideClassificationCard(
      {required this.id,
      required this.text,
      required this.categoryId,
      this.hint = '',
      this.highlight = ''});
  factory _GuideClassificationCard.fromJson(Map<String, dynamic> json) =>
      _$GuideClassificationCardFromJson(json);

  @override
  final String id;
  @override
  final String text;
  @override
  final String categoryId;
  @override
  @JsonKey()
  final String hint;
  @override
  @JsonKey()
  final String highlight;

  /// Create a copy of GuideClassificationCard
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuideClassificationCardCopyWith<_GuideClassificationCard> get copyWith =>
      __$GuideClassificationCardCopyWithImpl<_GuideClassificationCard>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideClassificationCardToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuideClassificationCard &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.categoryId, categoryId) ||
                other.categoryId == categoryId) &&
            (identical(other.hint, hint) || other.hint == hint) &&
            (identical(other.highlight, highlight) ||
                other.highlight == highlight));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, text, categoryId, hint, highlight);

  @override
  String toString() {
    return 'GuideClassificationCard(id: $id, text: $text, categoryId: $categoryId, hint: $hint, highlight: $highlight)';
  }
}

/// @nodoc
abstract mixin class _$GuideClassificationCardCopyWith<$Res>
    implements $GuideClassificationCardCopyWith<$Res> {
  factory _$GuideClassificationCardCopyWith(_GuideClassificationCard value,
          $Res Function(_GuideClassificationCard) _then) =
      __$GuideClassificationCardCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String text,
      String categoryId,
      String hint,
      String highlight});
}

/// @nodoc
class __$GuideClassificationCardCopyWithImpl<$Res>
    implements _$GuideClassificationCardCopyWith<$Res> {
  __$GuideClassificationCardCopyWithImpl(this._self, this._then);

  final _GuideClassificationCard _self;
  final $Res Function(_GuideClassificationCard) _then;

  /// Create a copy of GuideClassificationCard
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? categoryId = null,
    Object? hint = null,
    Object? highlight = null,
  }) {
    return _then(_GuideClassificationCard(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      categoryId: null == categoryId
          ? _self.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String,
      hint: null == hint
          ? _self.hint
          : hint // ignore: cast_nullable_to_non_nullable
              as String,
      highlight: null == highlight
          ? _self.highlight
          : highlight // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$GuideSuffixStep {
  String get suffix;
  String get result;
  String get meaning;

  /// Create a copy of GuideSuffixStep
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideSuffixStepCopyWith<GuideSuffixStep> get copyWith =>
      _$GuideSuffixStepCopyWithImpl<GuideSuffixStep>(
          this as GuideSuffixStep, _$identity);

  /// Serializes this GuideSuffixStep to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideSuffixStep &&
            (identical(other.suffix, suffix) || other.suffix == suffix) &&
            (identical(other.result, result) || other.result == result) &&
            (identical(other.meaning, meaning) || other.meaning == meaning));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, suffix, result, meaning);

  @override
  String toString() {
    return 'GuideSuffixStep(suffix: $suffix, result: $result, meaning: $meaning)';
  }
}

/// @nodoc
abstract mixin class $GuideSuffixStepCopyWith<$Res> {
  factory $GuideSuffixStepCopyWith(
          GuideSuffixStep value, $Res Function(GuideSuffixStep) _then) =
      _$GuideSuffixStepCopyWithImpl;
  @useResult
  $Res call({String suffix, String result, String meaning});
}

/// @nodoc
class _$GuideSuffixStepCopyWithImpl<$Res>
    implements $GuideSuffixStepCopyWith<$Res> {
  _$GuideSuffixStepCopyWithImpl(this._self, this._then);

  final GuideSuffixStep _self;
  final $Res Function(GuideSuffixStep) _then;

  /// Create a copy of GuideSuffixStep
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? suffix = null,
    Object? result = null,
    Object? meaning = null,
  }) {
    return _then(_self.copyWith(
      suffix: null == suffix
          ? _self.suffix
          : suffix // ignore: cast_nullable_to_non_nullable
              as String,
      result: null == result
          ? _self.result
          : result // ignore: cast_nullable_to_non_nullable
              as String,
      meaning: null == meaning
          ? _self.meaning
          : meaning // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideSuffixStep].
extension GuideSuffixStepPatterns on GuideSuffixStep {
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
    TResult Function(_GuideSuffixStep value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixStep() when $default != null:
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
    TResult Function(_GuideSuffixStep value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixStep():
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
    TResult? Function(_GuideSuffixStep value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixStep() when $default != null:
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
    TResult Function(String suffix, String result, String meaning)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixStep() when $default != null:
        return $default(_that.suffix, _that.result, _that.meaning);
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
    TResult Function(String suffix, String result, String meaning) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixStep():
        return $default(_that.suffix, _that.result, _that.meaning);
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
    TResult? Function(String suffix, String result, String meaning)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixStep() when $default != null:
        return $default(_that.suffix, _that.result, _that.meaning);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuideSuffixStep implements GuideSuffixStep {
  const _GuideSuffixStep(
      {required this.suffix, required this.result, required this.meaning});
  factory _GuideSuffixStep.fromJson(Map<String, dynamic> json) =>
      _$GuideSuffixStepFromJson(json);

  @override
  final String suffix;
  @override
  final String result;
  @override
  final String meaning;

  /// Create a copy of GuideSuffixStep
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuideSuffixStepCopyWith<_GuideSuffixStep> get copyWith =>
      __$GuideSuffixStepCopyWithImpl<_GuideSuffixStep>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideSuffixStepToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuideSuffixStep &&
            (identical(other.suffix, suffix) || other.suffix == suffix) &&
            (identical(other.result, result) || other.result == result) &&
            (identical(other.meaning, meaning) || other.meaning == meaning));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, suffix, result, meaning);

  @override
  String toString() {
    return 'GuideSuffixStep(suffix: $suffix, result: $result, meaning: $meaning)';
  }
}

/// @nodoc
abstract mixin class _$GuideSuffixStepCopyWith<$Res>
    implements $GuideSuffixStepCopyWith<$Res> {
  factory _$GuideSuffixStepCopyWith(
          _GuideSuffixStep value, $Res Function(_GuideSuffixStep) _then) =
      __$GuideSuffixStepCopyWithImpl;
  @override
  @useResult
  $Res call({String suffix, String result, String meaning});
}

/// @nodoc
class __$GuideSuffixStepCopyWithImpl<$Res>
    implements _$GuideSuffixStepCopyWith<$Res> {
  __$GuideSuffixStepCopyWithImpl(this._self, this._then);

  final _GuideSuffixStep _self;
  final $Res Function(_GuideSuffixStep) _then;

  /// Create a copy of GuideSuffixStep
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? suffix = null,
    Object? result = null,
    Object? meaning = null,
  }) {
    return _then(_GuideSuffixStep(
      suffix: null == suffix
          ? _self.suffix
          : suffix // ignore: cast_nullable_to_non_nullable
              as String,
      result: null == result
          ? _self.result
          : result // ignore: cast_nullable_to_non_nullable
              as String,
      meaning: null == meaning
          ? _self.meaning
          : meaning // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$GuideSuffixExample {
  String get id;
  String get root;
  String get rootMeaning;
  String get label;
  List<GuideSuffixStep> get steps;

  /// Create a copy of GuideSuffixExample
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideSuffixExampleCopyWith<GuideSuffixExample> get copyWith =>
      _$GuideSuffixExampleCopyWithImpl<GuideSuffixExample>(
          this as GuideSuffixExample, _$identity);

  /// Serializes this GuideSuffixExample to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideSuffixExample &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.root, root) || other.root == root) &&
            (identical(other.rootMeaning, rootMeaning) ||
                other.rootMeaning == rootMeaning) &&
            (identical(other.label, label) || other.label == label) &&
            const DeepCollectionEquality().equals(other.steps, steps));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, root, rootMeaning, label,
      const DeepCollectionEquality().hash(steps));

  @override
  String toString() {
    return 'GuideSuffixExample(id: $id, root: $root, rootMeaning: $rootMeaning, label: $label, steps: $steps)';
  }
}

/// @nodoc
abstract mixin class $GuideSuffixExampleCopyWith<$Res> {
  factory $GuideSuffixExampleCopyWith(
          GuideSuffixExample value, $Res Function(GuideSuffixExample) _then) =
      _$GuideSuffixExampleCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String root,
      String rootMeaning,
      String label,
      List<GuideSuffixStep> steps});
}

/// @nodoc
class _$GuideSuffixExampleCopyWithImpl<$Res>
    implements $GuideSuffixExampleCopyWith<$Res> {
  _$GuideSuffixExampleCopyWithImpl(this._self, this._then);

  final GuideSuffixExample _self;
  final $Res Function(GuideSuffixExample) _then;

  /// Create a copy of GuideSuffixExample
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? root = null,
    Object? rootMeaning = null,
    Object? label = null,
    Object? steps = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      root: null == root
          ? _self.root
          : root // ignore: cast_nullable_to_non_nullable
              as String,
      rootMeaning: null == rootMeaning
          ? _self.rootMeaning
          : rootMeaning // ignore: cast_nullable_to_non_nullable
              as String,
      label: null == label
          ? _self.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      steps: null == steps
          ? _self.steps
          : steps // ignore: cast_nullable_to_non_nullable
              as List<GuideSuffixStep>,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideSuffixExample].
extension GuideSuffixExamplePatterns on GuideSuffixExample {
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
    TResult Function(_GuideSuffixExample value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixExample() when $default != null:
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
    TResult Function(_GuideSuffixExample value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixExample():
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
    TResult? Function(_GuideSuffixExample value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixExample() when $default != null:
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
    TResult Function(String id, String root, String rootMeaning, String label,
            List<GuideSuffixStep> steps)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixExample() when $default != null:
        return $default(
            _that.id, _that.root, _that.rootMeaning, _that.label, _that.steps);
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
    TResult Function(String id, String root, String rootMeaning, String label,
            List<GuideSuffixStep> steps)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixExample():
        return $default(
            _that.id, _that.root, _that.rootMeaning, _that.label, _that.steps);
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
    TResult? Function(String id, String root, String rootMeaning, String label,
            List<GuideSuffixStep> steps)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSuffixExample() when $default != null:
        return $default(
            _that.id, _that.root, _that.rootMeaning, _that.label, _that.steps);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuideSuffixExample implements GuideSuffixExample {
  const _GuideSuffixExample(
      {required this.id,
      required this.root,
      required this.rootMeaning,
      this.label = '',
      final List<GuideSuffixStep> steps = const <GuideSuffixStep>[]})
      : _steps = steps;
  factory _GuideSuffixExample.fromJson(Map<String, dynamic> json) =>
      _$GuideSuffixExampleFromJson(json);

  @override
  final String id;
  @override
  final String root;
  @override
  final String rootMeaning;
  @override
  @JsonKey()
  final String label;
  final List<GuideSuffixStep> _steps;
  @override
  @JsonKey()
  List<GuideSuffixStep> get steps {
    if (_steps is EqualUnmodifiableListView) return _steps;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_steps);
  }

  /// Create a copy of GuideSuffixExample
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuideSuffixExampleCopyWith<_GuideSuffixExample> get copyWith =>
      __$GuideSuffixExampleCopyWithImpl<_GuideSuffixExample>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideSuffixExampleToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuideSuffixExample &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.root, root) || other.root == root) &&
            (identical(other.rootMeaning, rootMeaning) ||
                other.rootMeaning == rootMeaning) &&
            (identical(other.label, label) || other.label == label) &&
            const DeepCollectionEquality().equals(other._steps, _steps));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, root, rootMeaning, label,
      const DeepCollectionEquality().hash(_steps));

  @override
  String toString() {
    return 'GuideSuffixExample(id: $id, root: $root, rootMeaning: $rootMeaning, label: $label, steps: $steps)';
  }
}

/// @nodoc
abstract mixin class _$GuideSuffixExampleCopyWith<$Res>
    implements $GuideSuffixExampleCopyWith<$Res> {
  factory _$GuideSuffixExampleCopyWith(
          _GuideSuffixExample value, $Res Function(_GuideSuffixExample) _then) =
      __$GuideSuffixExampleCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String root,
      String rootMeaning,
      String label,
      List<GuideSuffixStep> steps});
}

/// @nodoc
class __$GuideSuffixExampleCopyWithImpl<$Res>
    implements _$GuideSuffixExampleCopyWith<$Res> {
  __$GuideSuffixExampleCopyWithImpl(this._self, this._then);

  final _GuideSuffixExample _self;
  final $Res Function(_GuideSuffixExample) _then;

  /// Create a copy of GuideSuffixExample
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? root = null,
    Object? rootMeaning = null,
    Object? label = null,
    Object? steps = null,
  }) {
    return _then(_GuideSuffixExample(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      root: null == root
          ? _self.root
          : root // ignore: cast_nullable_to_non_nullable
              as String,
      rootMeaning: null == rootMeaning
          ? _self.rootMeaning
          : rootMeaning // ignore: cast_nullable_to_non_nullable
              as String,
      label: null == label
          ? _self.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      steps: null == steps
          ? _self._steps
          : steps // ignore: cast_nullable_to_non_nullable
              as List<GuideSuffixStep>,
    ));
  }
}

/// @nodoc
mixin _$GuideSentenceToken {
  String get id;
  String get text;
  String get role;
  String get meaning;
  bool get optional;

  /// Create a copy of GuideSentenceToken
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideSentenceTokenCopyWith<GuideSentenceToken> get copyWith =>
      _$GuideSentenceTokenCopyWithImpl<GuideSentenceToken>(
          this as GuideSentenceToken, _$identity);

  /// Serializes this GuideSentenceToken to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideSentenceToken &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.meaning, meaning) || other.meaning == meaning) &&
            (identical(other.optional, optional) ||
                other.optional == optional));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, text, role, meaning, optional);

  @override
  String toString() {
    return 'GuideSentenceToken(id: $id, text: $text, role: $role, meaning: $meaning, optional: $optional)';
  }
}

/// @nodoc
abstract mixin class $GuideSentenceTokenCopyWith<$Res> {
  factory $GuideSentenceTokenCopyWith(
          GuideSentenceToken value, $Res Function(GuideSentenceToken) _then) =
      _$GuideSentenceTokenCopyWithImpl;
  @useResult
  $Res call(
      {String id, String text, String role, String meaning, bool optional});
}

/// @nodoc
class _$GuideSentenceTokenCopyWithImpl<$Res>
    implements $GuideSentenceTokenCopyWith<$Res> {
  _$GuideSentenceTokenCopyWithImpl(this._self, this._then);

  final GuideSentenceToken _self;
  final $Res Function(GuideSentenceToken) _then;

  /// Create a copy of GuideSentenceToken
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? role = null,
    Object? meaning = null,
    Object? optional = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      role: null == role
          ? _self.role
          : role // ignore: cast_nullable_to_non_nullable
              as String,
      meaning: null == meaning
          ? _self.meaning
          : meaning // ignore: cast_nullable_to_non_nullable
              as String,
      optional: null == optional
          ? _self.optional
          : optional // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideSentenceToken].
extension GuideSentenceTokenPatterns on GuideSentenceToken {
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
    TResult Function(_GuideSentenceToken value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideSentenceToken() when $default != null:
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
    TResult Function(_GuideSentenceToken value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSentenceToken():
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
    TResult? Function(_GuideSentenceToken value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSentenceToken() when $default != null:
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
            String id, String text, String role, String meaning, bool optional)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _GuideSentenceToken() when $default != null:
        return $default(
            _that.id, _that.text, _that.role, _that.meaning, _that.optional);
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
            String id, String text, String role, String meaning, bool optional)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSentenceToken():
        return $default(
            _that.id, _that.text, _that.role, _that.meaning, _that.optional);
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
            String id, String text, String role, String meaning, bool optional)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _GuideSentenceToken() when $default != null:
        return $default(
            _that.id, _that.text, _that.role, _that.meaning, _that.optional);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _GuideSentenceToken implements GuideSentenceToken {
  const _GuideSentenceToken(
      {required this.id,
      required this.text,
      required this.role,
      required this.meaning,
      this.optional = false});
  factory _GuideSentenceToken.fromJson(Map<String, dynamic> json) =>
      _$GuideSentenceTokenFromJson(json);

  @override
  final String id;
  @override
  final String text;
  @override
  final String role;
  @override
  final String meaning;
  @override
  @JsonKey()
  final bool optional;

  /// Create a copy of GuideSentenceToken
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$GuideSentenceTokenCopyWith<_GuideSentenceToken> get copyWith =>
      __$GuideSentenceTokenCopyWithImpl<_GuideSentenceToken>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideSentenceTokenToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _GuideSentenceToken &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.meaning, meaning) || other.meaning == meaning) &&
            (identical(other.optional, optional) ||
                other.optional == optional));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, text, role, meaning, optional);

  @override
  String toString() {
    return 'GuideSentenceToken(id: $id, text: $text, role: $role, meaning: $meaning, optional: $optional)';
  }
}

/// @nodoc
abstract mixin class _$GuideSentenceTokenCopyWith<$Res>
    implements $GuideSentenceTokenCopyWith<$Res> {
  factory _$GuideSentenceTokenCopyWith(
          _GuideSentenceToken value, $Res Function(_GuideSentenceToken) _then) =
      __$GuideSentenceTokenCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id, String text, String role, String meaning, bool optional});
}

/// @nodoc
class __$GuideSentenceTokenCopyWithImpl<$Res>
    implements _$GuideSentenceTokenCopyWith<$Res> {
  __$GuideSentenceTokenCopyWithImpl(this._self, this._then);

  final _GuideSentenceToken _self;
  final $Res Function(_GuideSentenceToken) _then;

  /// Create a copy of GuideSentenceToken
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? role = null,
    Object? meaning = null,
    Object? optional = null,
  }) {
    return _then(_GuideSentenceToken(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      role: null == role
          ? _self.role
          : role // ignore: cast_nullable_to_non_nullable
              as String,
      meaning: null == meaning
          ? _self.meaning
          : meaning // ignore: cast_nullable_to_non_nullable
              as String,
      optional: null == optional
          ? _self.optional
          : optional // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

GuideBlock _$GuideBlockFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'text':
      return GuideTextBlock.fromJson(json);
    case 'terms':
      return GuideTermsBlock.fromJson(json);
    case 'classification':
      return GuideClassificationBlock.fromJson(json);
    case 'suffixBuilder':
      return GuideSuffixBuilderBlock.fromJson(json);
    case 'wordOrder':
      return GuideWordOrderBlock.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'GuideBlock',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$GuideBlock {
  String get id;
  String? get title;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideBlockCopyWith<GuideBlock> get copyWith =>
      _$GuideBlockCopyWithImpl<GuideBlock>(this as GuideBlock, _$identity);

  /// Serializes this GuideBlock to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideBlock &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title);

  @override
  String toString() {
    return 'GuideBlock(id: $id, title: $title)';
  }
}

/// @nodoc
abstract mixin class $GuideBlockCopyWith<$Res> {
  factory $GuideBlockCopyWith(
          GuideBlock value, $Res Function(GuideBlock) _then) =
      _$GuideBlockCopyWithImpl;
  @useResult
  $Res call({String id, String title});
}

/// @nodoc
class _$GuideBlockCopyWithImpl<$Res> implements $GuideBlockCopyWith<$Res> {
  _$GuideBlockCopyWithImpl(this._self, this._then);

  final GuideBlock _self;
  final $Res Function(GuideBlock) _then;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title!
          : title // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [GuideBlock].
extension GuideBlockPatterns on GuideBlock {
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
  TResult maybeMap<TResult extends Object?>({
    TResult Function(GuideTextBlock value)? text,
    TResult Function(GuideTermsBlock value)? terms,
    TResult Function(GuideClassificationBlock value)? classification,
    TResult Function(GuideSuffixBuilderBlock value)? suffixBuilder,
    TResult Function(GuideWordOrderBlock value)? wordOrder,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case GuideTextBlock() when text != null:
        return text(_that);
      case GuideTermsBlock() when terms != null:
        return terms(_that);
      case GuideClassificationBlock() when classification != null:
        return classification(_that);
      case GuideSuffixBuilderBlock() when suffixBuilder != null:
        return suffixBuilder(_that);
      case GuideWordOrderBlock() when wordOrder != null:
        return wordOrder(_that);
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
  TResult map<TResult extends Object?>({
    required TResult Function(GuideTextBlock value) text,
    required TResult Function(GuideTermsBlock value) terms,
    required TResult Function(GuideClassificationBlock value) classification,
    required TResult Function(GuideSuffixBuilderBlock value) suffixBuilder,
    required TResult Function(GuideWordOrderBlock value) wordOrder,
  }) {
    final _that = this;
    switch (_that) {
      case GuideTextBlock():
        return text(_that);
      case GuideTermsBlock():
        return terms(_that);
      case GuideClassificationBlock():
        return classification(_that);
      case GuideSuffixBuilderBlock():
        return suffixBuilder(_that);
      case GuideWordOrderBlock():
        return wordOrder(_that);
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
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(GuideTextBlock value)? text,
    TResult? Function(GuideTermsBlock value)? terms,
    TResult? Function(GuideClassificationBlock value)? classification,
    TResult? Function(GuideSuffixBuilderBlock value)? suffixBuilder,
    TResult? Function(GuideWordOrderBlock value)? wordOrder,
  }) {
    final _that = this;
    switch (_that) {
      case GuideTextBlock() when text != null:
        return text(_that);
      case GuideTermsBlock() when terms != null:
        return terms(_that);
      case GuideClassificationBlock() when classification != null:
        return classification(_that);
      case GuideSuffixBuilderBlock() when suffixBuilder != null:
        return suffixBuilder(_that);
      case GuideWordOrderBlock() when wordOrder != null:
        return wordOrder(_that);
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
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, String? title, String body)? text,
    TResult Function(
            String id, String? title, bool compact, List<GuideTerm> items)?
        terms,
    TResult Function(
            String id,
            String title,
            String instruction,
            List<GuideClassificationCategory> categories,
            List<GuideClassificationCard> cards,
            String completionNote)?
        classification,
    TResult Function(String id, String title, String instruction,
            List<GuideSuffixExample> examples)?
        suffixBuilder,
    TResult Function(
            String id,
            String title,
            String translation,
            List<GuideSentenceToken> tokens,
            String optionalToggleLabel,
            String note)?
        wordOrder,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case GuideTextBlock() when text != null:
        return text(_that.id, _that.title, _that.body);
      case GuideTermsBlock() when terms != null:
        return terms(_that.id, _that.title, _that.compact, _that.items);
      case GuideClassificationBlock() when classification != null:
        return classification(_that.id, _that.title, _that.instruction,
            _that.categories, _that.cards, _that.completionNote);
      case GuideSuffixBuilderBlock() when suffixBuilder != null:
        return suffixBuilder(
            _that.id, _that.title, _that.instruction, _that.examples);
      case GuideWordOrderBlock() when wordOrder != null:
        return wordOrder(_that.id, _that.title, _that.translation, _that.tokens,
            _that.optionalToggleLabel, _that.note);
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
  TResult when<TResult extends Object?>({
    required TResult Function(String id, String? title, String body) text,
    required TResult Function(
            String id, String? title, bool compact, List<GuideTerm> items)
        terms,
    required TResult Function(
            String id,
            String title,
            String instruction,
            List<GuideClassificationCategory> categories,
            List<GuideClassificationCard> cards,
            String completionNote)
        classification,
    required TResult Function(String id, String title, String instruction,
            List<GuideSuffixExample> examples)
        suffixBuilder,
    required TResult Function(
            String id,
            String title,
            String translation,
            List<GuideSentenceToken> tokens,
            String optionalToggleLabel,
            String note)
        wordOrder,
  }) {
    final _that = this;
    switch (_that) {
      case GuideTextBlock():
        return text(_that.id, _that.title, _that.body);
      case GuideTermsBlock():
        return terms(_that.id, _that.title, _that.compact, _that.items);
      case GuideClassificationBlock():
        return classification(_that.id, _that.title, _that.instruction,
            _that.categories, _that.cards, _that.completionNote);
      case GuideSuffixBuilderBlock():
        return suffixBuilder(
            _that.id, _that.title, _that.instruction, _that.examples);
      case GuideWordOrderBlock():
        return wordOrder(_that.id, _that.title, _that.translation, _that.tokens,
            _that.optionalToggleLabel, _that.note);
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
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, String? title, String body)? text,
    TResult? Function(
            String id, String? title, bool compact, List<GuideTerm> items)?
        terms,
    TResult? Function(
            String id,
            String title,
            String instruction,
            List<GuideClassificationCategory> categories,
            List<GuideClassificationCard> cards,
            String completionNote)?
        classification,
    TResult? Function(String id, String title, String instruction,
            List<GuideSuffixExample> examples)?
        suffixBuilder,
    TResult? Function(
            String id,
            String title,
            String translation,
            List<GuideSentenceToken> tokens,
            String optionalToggleLabel,
            String note)?
        wordOrder,
  }) {
    final _that = this;
    switch (_that) {
      case GuideTextBlock() when text != null:
        return text(_that.id, _that.title, _that.body);
      case GuideTermsBlock() when terms != null:
        return terms(_that.id, _that.title, _that.compact, _that.items);
      case GuideClassificationBlock() when classification != null:
        return classification(_that.id, _that.title, _that.instruction,
            _that.categories, _that.cards, _that.completionNote);
      case GuideSuffixBuilderBlock() when suffixBuilder != null:
        return suffixBuilder(
            _that.id, _that.title, _that.instruction, _that.examples);
      case GuideWordOrderBlock() when wordOrder != null:
        return wordOrder(_that.id, _that.title, _that.translation, _that.tokens,
            _that.optionalToggleLabel, _that.note);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class GuideTextBlock implements GuideBlock {
  const GuideTextBlock(
      {this.id = '', this.title, required this.body, final String? $type})
      : $type = $type ?? 'text';
  factory GuideTextBlock.fromJson(Map<String, dynamic> json) =>
      _$GuideTextBlockFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String? title;
  final String body;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideTextBlockCopyWith<GuideTextBlock> get copyWith =>
      _$GuideTextBlockCopyWithImpl<GuideTextBlock>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideTextBlockToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideTextBlock &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.body, body) || other.body == body));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, body);

  @override
  String toString() {
    return 'GuideBlock.text(id: $id, title: $title, body: $body)';
  }
}

/// @nodoc
abstract mixin class $GuideTextBlockCopyWith<$Res>
    implements $GuideBlockCopyWith<$Res> {
  factory $GuideTextBlockCopyWith(
          GuideTextBlock value, $Res Function(GuideTextBlock) _then) =
      _$GuideTextBlockCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String? title, String body});
}

/// @nodoc
class _$GuideTextBlockCopyWithImpl<$Res>
    implements $GuideTextBlockCopyWith<$Res> {
  _$GuideTextBlockCopyWithImpl(this._self, this._then);

  final GuideTextBlock _self;
  final $Res Function(GuideTextBlock) _then;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = freezed,
    Object? body = null,
  }) {
    return _then(GuideTextBlock(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      body: null == body
          ? _self.body
          : body // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class GuideTermsBlock implements GuideBlock {
  const GuideTermsBlock(
      {this.id = '',
      this.title,
      this.compact = false,
      final List<GuideTerm> items = const <GuideTerm>[],
      final String? $type})
      : _items = items,
        $type = $type ?? 'terms';
  factory GuideTermsBlock.fromJson(Map<String, dynamic> json) =>
      _$GuideTermsBlockFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String? title;
  @JsonKey()
  final bool compact;
  final List<GuideTerm> _items;
  @JsonKey()
  List<GuideTerm> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideTermsBlockCopyWith<GuideTermsBlock> get copyWith =>
      _$GuideTermsBlockCopyWithImpl<GuideTermsBlock>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideTermsBlockToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideTermsBlock &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.compact, compact) || other.compact == compact) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, compact,
      const DeepCollectionEquality().hash(_items));

  @override
  String toString() {
    return 'GuideBlock.terms(id: $id, title: $title, compact: $compact, items: $items)';
  }
}

/// @nodoc
abstract mixin class $GuideTermsBlockCopyWith<$Res>
    implements $GuideBlockCopyWith<$Res> {
  factory $GuideTermsBlockCopyWith(
          GuideTermsBlock value, $Res Function(GuideTermsBlock) _then) =
      _$GuideTermsBlockCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String? title, bool compact, List<GuideTerm> items});
}

/// @nodoc
class _$GuideTermsBlockCopyWithImpl<$Res>
    implements $GuideTermsBlockCopyWith<$Res> {
  _$GuideTermsBlockCopyWithImpl(this._self, this._then);

  final GuideTermsBlock _self;
  final $Res Function(GuideTermsBlock) _then;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = freezed,
    Object? compact = null,
    Object? items = null,
  }) {
    return _then(GuideTermsBlock(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: freezed == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String?,
      compact: null == compact
          ? _self.compact
          : compact // ignore: cast_nullable_to_non_nullable
              as bool,
      items: null == items
          ? _self._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<GuideTerm>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class GuideClassificationBlock implements GuideBlock {
  const GuideClassificationBlock(
      {this.id = '',
      required this.title,
      this.instruction = '',
      final List<GuideClassificationCategory> categories =
          const <GuideClassificationCategory>[],
      final List<GuideClassificationCard> cards =
          const <GuideClassificationCard>[],
      this.completionNote = '',
      final String? $type})
      : _categories = categories,
        _cards = cards,
        $type = $type ?? 'classification';
  factory GuideClassificationBlock.fromJson(Map<String, dynamic> json) =>
      _$GuideClassificationBlockFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String title;
  @JsonKey()
  final String instruction;
  final List<GuideClassificationCategory> _categories;
  @JsonKey()
  List<GuideClassificationCategory> get categories {
    if (_categories is EqualUnmodifiableListView) return _categories;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_categories);
  }

  final List<GuideClassificationCard> _cards;
  @JsonKey()
  List<GuideClassificationCard> get cards {
    if (_cards is EqualUnmodifiableListView) return _cards;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_cards);
  }

  @JsonKey()
  final String completionNote;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideClassificationBlockCopyWith<GuideClassificationBlock> get copyWith =>
      _$GuideClassificationBlockCopyWithImpl<GuideClassificationBlock>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideClassificationBlockToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideClassificationBlock &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.instruction, instruction) ||
                other.instruction == instruction) &&
            const DeepCollectionEquality()
                .equals(other._categories, _categories) &&
            const DeepCollectionEquality().equals(other._cards, _cards) &&
            (identical(other.completionNote, completionNote) ||
                other.completionNote == completionNote));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      instruction,
      const DeepCollectionEquality().hash(_categories),
      const DeepCollectionEquality().hash(_cards),
      completionNote);

  @override
  String toString() {
    return 'GuideBlock.classification(id: $id, title: $title, instruction: $instruction, categories: $categories, cards: $cards, completionNote: $completionNote)';
  }
}

/// @nodoc
abstract mixin class $GuideClassificationBlockCopyWith<$Res>
    implements $GuideBlockCopyWith<$Res> {
  factory $GuideClassificationBlockCopyWith(GuideClassificationBlock value,
          $Res Function(GuideClassificationBlock) _then) =
      _$GuideClassificationBlockCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String instruction,
      List<GuideClassificationCategory> categories,
      List<GuideClassificationCard> cards,
      String completionNote});
}

/// @nodoc
class _$GuideClassificationBlockCopyWithImpl<$Res>
    implements $GuideClassificationBlockCopyWith<$Res> {
  _$GuideClassificationBlockCopyWithImpl(this._self, this._then);

  final GuideClassificationBlock _self;
  final $Res Function(GuideClassificationBlock) _then;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? instruction = null,
    Object? categories = null,
    Object? cards = null,
    Object? completionNote = null,
  }) {
    return _then(GuideClassificationBlock(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      instruction: null == instruction
          ? _self.instruction
          : instruction // ignore: cast_nullable_to_non_nullable
              as String,
      categories: null == categories
          ? _self._categories
          : categories // ignore: cast_nullable_to_non_nullable
              as List<GuideClassificationCategory>,
      cards: null == cards
          ? _self._cards
          : cards // ignore: cast_nullable_to_non_nullable
              as List<GuideClassificationCard>,
      completionNote: null == completionNote
          ? _self.completionNote
          : completionNote // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class GuideSuffixBuilderBlock implements GuideBlock {
  const GuideSuffixBuilderBlock(
      {this.id = '',
      required this.title,
      this.instruction = '',
      final List<GuideSuffixExample> examples = const <GuideSuffixExample>[],
      final String? $type})
      : _examples = examples,
        $type = $type ?? 'suffixBuilder';
  factory GuideSuffixBuilderBlock.fromJson(Map<String, dynamic> json) =>
      _$GuideSuffixBuilderBlockFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String title;
  @JsonKey()
  final String instruction;
  final List<GuideSuffixExample> _examples;
  @JsonKey()
  List<GuideSuffixExample> get examples {
    if (_examples is EqualUnmodifiableListView) return _examples;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_examples);
  }

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideSuffixBuilderBlockCopyWith<GuideSuffixBuilderBlock> get copyWith =>
      _$GuideSuffixBuilderBlockCopyWithImpl<GuideSuffixBuilderBlock>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideSuffixBuilderBlockToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideSuffixBuilderBlock &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.instruction, instruction) ||
                other.instruction == instruction) &&
            const DeepCollectionEquality().equals(other._examples, _examples));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, instruction,
      const DeepCollectionEquality().hash(_examples));

  @override
  String toString() {
    return 'GuideBlock.suffixBuilder(id: $id, title: $title, instruction: $instruction, examples: $examples)';
  }
}

/// @nodoc
abstract mixin class $GuideSuffixBuilderBlockCopyWith<$Res>
    implements $GuideBlockCopyWith<$Res> {
  factory $GuideSuffixBuilderBlockCopyWith(GuideSuffixBuilderBlock value,
          $Res Function(GuideSuffixBuilderBlock) _then) =
      _$GuideSuffixBuilderBlockCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String instruction,
      List<GuideSuffixExample> examples});
}

/// @nodoc
class _$GuideSuffixBuilderBlockCopyWithImpl<$Res>
    implements $GuideSuffixBuilderBlockCopyWith<$Res> {
  _$GuideSuffixBuilderBlockCopyWithImpl(this._self, this._then);

  final GuideSuffixBuilderBlock _self;
  final $Res Function(GuideSuffixBuilderBlock) _then;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? instruction = null,
    Object? examples = null,
  }) {
    return _then(GuideSuffixBuilderBlock(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      instruction: null == instruction
          ? _self.instruction
          : instruction // ignore: cast_nullable_to_non_nullable
              as String,
      examples: null == examples
          ? _self._examples
          : examples // ignore: cast_nullable_to_non_nullable
              as List<GuideSuffixExample>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class GuideWordOrderBlock implements GuideBlock {
  const GuideWordOrderBlock(
      {this.id = '',
      required this.title,
      this.translation = '',
      final List<GuideSentenceToken> tokens = const <GuideSentenceToken>[],
      this.optionalToggleLabel = '',
      this.note = '',
      final String? $type})
      : _tokens = tokens,
        $type = $type ?? 'wordOrder';
  factory GuideWordOrderBlock.fromJson(Map<String, dynamic> json) =>
      _$GuideWordOrderBlockFromJson(json);

  @override
  @JsonKey()
  final String id;
  @override
  final String title;
  @JsonKey()
  final String translation;
  final List<GuideSentenceToken> _tokens;
  @JsonKey()
  List<GuideSentenceToken> get tokens {
    if (_tokens is EqualUnmodifiableListView) return _tokens;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tokens);
  }

  @JsonKey()
  final String optionalToggleLabel;
  @JsonKey()
  final String note;

  @JsonKey(name: 'runtimeType')
  final String $type;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $GuideWordOrderBlockCopyWith<GuideWordOrderBlock> get copyWith =>
      _$GuideWordOrderBlockCopyWithImpl<GuideWordOrderBlock>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$GuideWordOrderBlockToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is GuideWordOrderBlock &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            const DeepCollectionEquality().equals(other._tokens, _tokens) &&
            (identical(other.optionalToggleLabel, optionalToggleLabel) ||
                other.optionalToggleLabel == optionalToggleLabel) &&
            (identical(other.note, note) || other.note == note));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, translation,
      const DeepCollectionEquality().hash(_tokens), optionalToggleLabel, note);

  @override
  String toString() {
    return 'GuideBlock.wordOrder(id: $id, title: $title, translation: $translation, tokens: $tokens, optionalToggleLabel: $optionalToggleLabel, note: $note)';
  }
}

/// @nodoc
abstract mixin class $GuideWordOrderBlockCopyWith<$Res>
    implements $GuideBlockCopyWith<$Res> {
  factory $GuideWordOrderBlockCopyWith(
          GuideWordOrderBlock value, $Res Function(GuideWordOrderBlock) _then) =
      _$GuideWordOrderBlockCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String translation,
      List<GuideSentenceToken> tokens,
      String optionalToggleLabel,
      String note});
}

/// @nodoc
class _$GuideWordOrderBlockCopyWithImpl<$Res>
    implements $GuideWordOrderBlockCopyWith<$Res> {
  _$GuideWordOrderBlockCopyWithImpl(this._self, this._then);

  final GuideWordOrderBlock _self;
  final $Res Function(GuideWordOrderBlock) _then;

  /// Create a copy of GuideBlock
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? translation = null,
    Object? tokens = null,
    Object? optionalToggleLabel = null,
    Object? note = null,
  }) {
    return _then(GuideWordOrderBlock(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      tokens: null == tokens
          ? _self._tokens
          : tokens // ignore: cast_nullable_to_non_nullable
              as List<GuideSentenceToken>,
      optionalToggleLabel: null == optionalToggleLabel
          ? _self.optionalToggleLabel
          : optionalToggleLabel // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _self.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
