// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'word_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WordEntry {
  String get id;
  String get term;
  String get translation;
  String? get pronunciation;
  String? get audioAsset;
  List<String> get tags;

  /// Create a copy of WordEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $WordEntryCopyWith<WordEntry> get copyWith =>
      _$WordEntryCopyWithImpl<WordEntry>(this as WordEntry, _$identity);

  /// Serializes this WordEntry to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is WordEntry &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.term, term) || other.term == term) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.pronunciation, pronunciation) ||
                other.pronunciation == pronunciation) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            const DeepCollectionEquality().equals(other.tags, tags));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, term, translation,
      pronunciation, audioAsset, const DeepCollectionEquality().hash(tags));

  @override
  String toString() {
    return 'WordEntry(id: $id, term: $term, translation: $translation, pronunciation: $pronunciation, audioAsset: $audioAsset, tags: $tags)';
  }
}

/// @nodoc
abstract mixin class $WordEntryCopyWith<$Res> {
  factory $WordEntryCopyWith(WordEntry value, $Res Function(WordEntry) _then) =
      _$WordEntryCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String term,
      String translation,
      String? pronunciation,
      String? audioAsset,
      List<String> tags});
}

/// @nodoc
class _$WordEntryCopyWithImpl<$Res> implements $WordEntryCopyWith<$Res> {
  _$WordEntryCopyWithImpl(this._self, this._then);

  final WordEntry _self;
  final $Res Function(WordEntry) _then;

  /// Create a copy of WordEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? term = null,
    Object? translation = null,
    Object? pronunciation = freezed,
    Object? audioAsset = freezed,
    Object? tags = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      term: null == term
          ? _self.term
          : term // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      pronunciation: freezed == pronunciation
          ? _self.pronunciation
          : pronunciation // ignore: cast_nullable_to_non_nullable
              as String?,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: null == tags
          ? _self.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// Adds pattern-matching-related methods to [WordEntry].
extension WordEntryPatterns on WordEntry {
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
    TResult Function(_WordEntry value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _WordEntry() when $default != null:
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
    TResult Function(_WordEntry value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordEntry():
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
    TResult? Function(_WordEntry value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordEntry() when $default != null:
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
    TResult Function(String id, String term, String translation,
            String? pronunciation, String? audioAsset, List<String> tags)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _WordEntry() when $default != null:
        return $default(_that.id, _that.term, _that.translation,
            _that.pronunciation, _that.audioAsset, _that.tags);
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
    TResult Function(String id, String term, String translation,
            String? pronunciation, String? audioAsset, List<String> tags)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordEntry():
        return $default(_that.id, _that.term, _that.translation,
            _that.pronunciation, _that.audioAsset, _that.tags);
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
    TResult? Function(String id, String term, String translation,
            String? pronunciation, String? audioAsset, List<String> tags)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _WordEntry() when $default != null:
        return $default(_that.id, _that.term, _that.translation,
            _that.pronunciation, _that.audioAsset, _that.tags);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _WordEntry implements WordEntry {
  const _WordEntry(
      {required this.id,
      required this.term,
      required this.translation,
      this.pronunciation,
      this.audioAsset,
      final List<String> tags = const <String>[]})
      : _tags = tags;
  factory _WordEntry.fromJson(Map<String, dynamic> json) =>
      _$WordEntryFromJson(json);

  @override
  final String id;
  @override
  final String term;
  @override
  final String translation;
  @override
  final String? pronunciation;
  @override
  final String? audioAsset;
  final List<String> _tags;
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  /// Create a copy of WordEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$WordEntryCopyWith<_WordEntry> get copyWith =>
      __$WordEntryCopyWithImpl<_WordEntry>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$WordEntryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _WordEntry &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.term, term) || other.term == term) &&
            (identical(other.translation, translation) ||
                other.translation == translation) &&
            (identical(other.pronunciation, pronunciation) ||
                other.pronunciation == pronunciation) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            const DeepCollectionEquality().equals(other._tags, _tags));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, term, translation,
      pronunciation, audioAsset, const DeepCollectionEquality().hash(_tags));

  @override
  String toString() {
    return 'WordEntry(id: $id, term: $term, translation: $translation, pronunciation: $pronunciation, audioAsset: $audioAsset, tags: $tags)';
  }
}

/// @nodoc
abstract mixin class _$WordEntryCopyWith<$Res>
    implements $WordEntryCopyWith<$Res> {
  factory _$WordEntryCopyWith(
          _WordEntry value, $Res Function(_WordEntry) _then) =
      __$WordEntryCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String term,
      String translation,
      String? pronunciation,
      String? audioAsset,
      List<String> tags});
}

/// @nodoc
class __$WordEntryCopyWithImpl<$Res> implements _$WordEntryCopyWith<$Res> {
  __$WordEntryCopyWithImpl(this._self, this._then);

  final _WordEntry _self;
  final $Res Function(_WordEntry) _then;

  /// Create a copy of WordEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? term = null,
    Object? translation = null,
    Object? pronunciation = freezed,
    Object? audioAsset = freezed,
    Object? tags = null,
  }) {
    return _then(_WordEntry(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      term: null == term
          ? _self.term
          : term // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _self.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      pronunciation: freezed == pronunciation
          ? _self.pronunciation
          : pronunciation // ignore: cast_nullable_to_non_nullable
              as String?,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: null == tags
          ? _self._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

// dart format on
