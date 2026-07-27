// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'anki_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AnkiCollection {
  /// mid → notetype definition
  Map<int, AnkiNotetype> get notetypes;

  /// did → deck definition
  Map<int, AnkiDeckInfo> get decks;
  List<AnkiNote> get notes;
  List<AnkiCardData> get cards;

  /// Numeric filename → original media filename mapping
  Map<String, String> get media;

  /// Path to the extracted media directory (temporary)
  String get mediaDir;

  /// Create a copy of AnkiCollection
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiCollectionCopyWith<AnkiCollection> get copyWith =>
      _$AnkiCollectionCopyWithImpl<AnkiCollection>(
          this as AnkiCollection, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiCollection &&
            const DeepCollectionEquality().equals(other.notetypes, notetypes) &&
            const DeepCollectionEquality().equals(other.decks, decks) &&
            const DeepCollectionEquality().equals(other.notes, notes) &&
            const DeepCollectionEquality().equals(other.cards, cards) &&
            const DeepCollectionEquality().equals(other.media, media) &&
            (identical(other.mediaDir, mediaDir) ||
                other.mediaDir == mediaDir));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(notetypes),
      const DeepCollectionEquality().hash(decks),
      const DeepCollectionEquality().hash(notes),
      const DeepCollectionEquality().hash(cards),
      const DeepCollectionEquality().hash(media),
      mediaDir);

  @override
  String toString() {
    return 'AnkiCollection(notetypes: $notetypes, decks: $decks, notes: $notes, cards: $cards, media: $media, mediaDir: $mediaDir)';
  }
}

/// @nodoc
abstract mixin class $AnkiCollectionCopyWith<$Res> {
  factory $AnkiCollectionCopyWith(
          AnkiCollection value, $Res Function(AnkiCollection) _then) =
      _$AnkiCollectionCopyWithImpl;
  @useResult
  $Res call(
      {Map<int, AnkiNotetype> notetypes,
      Map<int, AnkiDeckInfo> decks,
      List<AnkiNote> notes,
      List<AnkiCardData> cards,
      Map<String, String> media,
      String mediaDir});
}

/// @nodoc
class _$AnkiCollectionCopyWithImpl<$Res>
    implements $AnkiCollectionCopyWith<$Res> {
  _$AnkiCollectionCopyWithImpl(this._self, this._then);

  final AnkiCollection _self;
  final $Res Function(AnkiCollection) _then;

  /// Create a copy of AnkiCollection
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notetypes = null,
    Object? decks = null,
    Object? notes = null,
    Object? cards = null,
    Object? media = null,
    Object? mediaDir = null,
  }) {
    return _then(_self.copyWith(
      notetypes: null == notetypes
          ? _self.notetypes
          : notetypes // ignore: cast_nullable_to_non_nullable
              as Map<int, AnkiNotetype>,
      decks: null == decks
          ? _self.decks
          : decks // ignore: cast_nullable_to_non_nullable
              as Map<int, AnkiDeckInfo>,
      notes: null == notes
          ? _self.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as List<AnkiNote>,
      cards: null == cards
          ? _self.cards
          : cards // ignore: cast_nullable_to_non_nullable
              as List<AnkiCardData>,
      media: null == media
          ? _self.media
          : media // ignore: cast_nullable_to_non_nullable
              as Map<String, String>,
      mediaDir: null == mediaDir
          ? _self.mediaDir
          : mediaDir // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiCollection].
extension AnkiCollectionPatterns on AnkiCollection {
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
    TResult Function(_AnkiCollection value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection() when $default != null:
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
    TResult Function(_AnkiCollection value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection():
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
    TResult? Function(_AnkiCollection value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection() when $default != null:
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
            Map<int, AnkiNotetype> notetypes,
            Map<int, AnkiDeckInfo> decks,
            List<AnkiNote> notes,
            List<AnkiCardData> cards,
            Map<String, String> media,
            String mediaDir)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection() when $default != null:
        return $default(_that.notetypes, _that.decks, _that.notes, _that.cards,
            _that.media, _that.mediaDir);
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
            Map<int, AnkiNotetype> notetypes,
            Map<int, AnkiDeckInfo> decks,
            List<AnkiNote> notes,
            List<AnkiCardData> cards,
            Map<String, String> media,
            String mediaDir)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection():
        return $default(_that.notetypes, _that.decks, _that.notes, _that.cards,
            _that.media, _that.mediaDir);
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
            Map<int, AnkiNotetype> notetypes,
            Map<int, AnkiDeckInfo> decks,
            List<AnkiNote> notes,
            List<AnkiCardData> cards,
            Map<String, String> media,
            String mediaDir)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection() when $default != null:
        return $default(_that.notetypes, _that.decks, _that.notes, _that.cards,
            _that.media, _that.mediaDir);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _AnkiCollection implements AnkiCollection {
  const _AnkiCollection(
      {required final Map<int, AnkiNotetype> notetypes,
      required final Map<int, AnkiDeckInfo> decks,
      required final List<AnkiNote> notes,
      required final List<AnkiCardData> cards,
      final Map<String, String> media = const {},
      this.mediaDir = ''})
      : _notetypes = notetypes,
        _decks = decks,
        _notes = notes,
        _cards = cards,
        _media = media;

  /// mid → notetype definition
  final Map<int, AnkiNotetype> _notetypes;

  /// mid → notetype definition
  @override
  Map<int, AnkiNotetype> get notetypes {
    if (_notetypes is EqualUnmodifiableMapView) return _notetypes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_notetypes);
  }

  /// did → deck definition
  final Map<int, AnkiDeckInfo> _decks;

  /// did → deck definition
  @override
  Map<int, AnkiDeckInfo> get decks {
    if (_decks is EqualUnmodifiableMapView) return _decks;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_decks);
  }

  final List<AnkiNote> _notes;
  @override
  List<AnkiNote> get notes {
    if (_notes is EqualUnmodifiableListView) return _notes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_notes);
  }

  final List<AnkiCardData> _cards;
  @override
  List<AnkiCardData> get cards {
    if (_cards is EqualUnmodifiableListView) return _cards;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_cards);
  }

  /// Numeric filename → original media filename mapping
  final Map<String, String> _media;

  /// Numeric filename → original media filename mapping
  @override
  @JsonKey()
  Map<String, String> get media {
    if (_media is EqualUnmodifiableMapView) return _media;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_media);
  }

  /// Path to the extracted media directory (temporary)
  @override
  @JsonKey()
  final String mediaDir;

  /// Create a copy of AnkiCollection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiCollectionCopyWith<_AnkiCollection> get copyWith =>
      __$AnkiCollectionCopyWithImpl<_AnkiCollection>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiCollection &&
            const DeepCollectionEquality()
                .equals(other._notetypes, _notetypes) &&
            const DeepCollectionEquality().equals(other._decks, _decks) &&
            const DeepCollectionEquality().equals(other._notes, _notes) &&
            const DeepCollectionEquality().equals(other._cards, _cards) &&
            const DeepCollectionEquality().equals(other._media, _media) &&
            (identical(other.mediaDir, mediaDir) ||
                other.mediaDir == mediaDir));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_notetypes),
      const DeepCollectionEquality().hash(_decks),
      const DeepCollectionEquality().hash(_notes),
      const DeepCollectionEquality().hash(_cards),
      const DeepCollectionEquality().hash(_media),
      mediaDir);

  @override
  String toString() {
    return 'AnkiCollection(notetypes: $notetypes, decks: $decks, notes: $notes, cards: $cards, media: $media, mediaDir: $mediaDir)';
  }
}

/// @nodoc
abstract mixin class _$AnkiCollectionCopyWith<$Res>
    implements $AnkiCollectionCopyWith<$Res> {
  factory _$AnkiCollectionCopyWith(
          _AnkiCollection value, $Res Function(_AnkiCollection) _then) =
      __$AnkiCollectionCopyWithImpl;
  @override
  @useResult
  $Res call(
      {Map<int, AnkiNotetype> notetypes,
      Map<int, AnkiDeckInfo> decks,
      List<AnkiNote> notes,
      List<AnkiCardData> cards,
      Map<String, String> media,
      String mediaDir});
}

/// @nodoc
class __$AnkiCollectionCopyWithImpl<$Res>
    implements _$AnkiCollectionCopyWith<$Res> {
  __$AnkiCollectionCopyWithImpl(this._self, this._then);

  final _AnkiCollection _self;
  final $Res Function(_AnkiCollection) _then;

  /// Create a copy of AnkiCollection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? notetypes = null,
    Object? decks = null,
    Object? notes = null,
    Object? cards = null,
    Object? media = null,
    Object? mediaDir = null,
  }) {
    return _then(_AnkiCollection(
      notetypes: null == notetypes
          ? _self._notetypes
          : notetypes // ignore: cast_nullable_to_non_nullable
              as Map<int, AnkiNotetype>,
      decks: null == decks
          ? _self._decks
          : decks // ignore: cast_nullable_to_non_nullable
              as Map<int, AnkiDeckInfo>,
      notes: null == notes
          ? _self._notes
          : notes // ignore: cast_nullable_to_non_nullable
              as List<AnkiNote>,
      cards: null == cards
          ? _self._cards
          : cards // ignore: cast_nullable_to_non_nullable
              as List<AnkiCardData>,
      media: null == media
          ? _self._media
          : media // ignore: cast_nullable_to_non_nullable
              as Map<String, String>,
      mediaDir: null == mediaDir
          ? _self.mediaDir
          : mediaDir // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$AnkiNotetype {
  int get id;
  String get name;

  /// Ordered field names (e.g. ["Front", "Back"])
  List<String> get fieldNames;

  /// Card template names (e.g. ["Card 1", "Card 2 (reverse)"])
  List<String> get templateNames;

  /// Whether this is a Cloze notetype
  bool get isCloze;

  /// Create a copy of AnkiNotetype
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiNotetypeCopyWith<AnkiNotetype> get copyWith =>
      _$AnkiNotetypeCopyWithImpl<AnkiNotetype>(
          this as AnkiNotetype, _$identity);

  /// Serializes this AnkiNotetype to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiNotetype &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other.fieldNames, fieldNames) &&
            const DeepCollectionEquality()
                .equals(other.templateNames, templateNames) &&
            (identical(other.isCloze, isCloze) || other.isCloze == isCloze));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      const DeepCollectionEquality().hash(fieldNames),
      const DeepCollectionEquality().hash(templateNames),
      isCloze);

  @override
  String toString() {
    return 'AnkiNotetype(id: $id, name: $name, fieldNames: $fieldNames, templateNames: $templateNames, isCloze: $isCloze)';
  }
}

/// @nodoc
abstract mixin class $AnkiNotetypeCopyWith<$Res> {
  factory $AnkiNotetypeCopyWith(
          AnkiNotetype value, $Res Function(AnkiNotetype) _then) =
      _$AnkiNotetypeCopyWithImpl;
  @useResult
  $Res call(
      {int id,
      String name,
      List<String> fieldNames,
      List<String> templateNames,
      bool isCloze});
}

/// @nodoc
class _$AnkiNotetypeCopyWithImpl<$Res> implements $AnkiNotetypeCopyWith<$Res> {
  _$AnkiNotetypeCopyWithImpl(this._self, this._then);

  final AnkiNotetype _self;
  final $Res Function(AnkiNotetype) _then;

  /// Create a copy of AnkiNotetype
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? fieldNames = null,
    Object? templateNames = null,
    Object? isCloze = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      fieldNames: null == fieldNames
          ? _self.fieldNames
          : fieldNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      templateNames: null == templateNames
          ? _self.templateNames
          : templateNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      isCloze: null == isCloze
          ? _self.isCloze
          : isCloze // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiNotetype].
extension AnkiNotetypePatterns on AnkiNotetype {
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
    TResult Function(_AnkiNotetype value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype() when $default != null:
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
    TResult Function(_AnkiNotetype value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype():
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
    TResult? Function(_AnkiNotetype value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype() when $default != null:
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
    TResult Function(int id, String name, List<String> fieldNames,
            List<String> templateNames, bool isCloze)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype() when $default != null:
        return $default(_that.id, _that.name, _that.fieldNames,
            _that.templateNames, _that.isCloze);
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
    TResult Function(int id, String name, List<String> fieldNames,
            List<String> templateNames, bool isCloze)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype():
        return $default(_that.id, _that.name, _that.fieldNames,
            _that.templateNames, _that.isCloze);
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
    TResult? Function(int id, String name, List<String> fieldNames,
            List<String> templateNames, bool isCloze)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype() when $default != null:
        return $default(_that.id, _that.name, _that.fieldNames,
            _that.templateNames, _that.isCloze);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _AnkiNotetype implements AnkiNotetype {
  const _AnkiNotetype(
      {required this.id,
      required this.name,
      required final List<String> fieldNames,
      final List<String> templateNames = const <String>[],
      this.isCloze = false})
      : _fieldNames = fieldNames,
        _templateNames = templateNames;
  factory _AnkiNotetype.fromJson(Map<String, dynamic> json) =>
      _$AnkiNotetypeFromJson(json);

  @override
  final int id;
  @override
  final String name;

  /// Ordered field names (e.g. ["Front", "Back"])
  final List<String> _fieldNames;

  /// Ordered field names (e.g. ["Front", "Back"])
  @override
  List<String> get fieldNames {
    if (_fieldNames is EqualUnmodifiableListView) return _fieldNames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_fieldNames);
  }

  /// Card template names (e.g. ["Card 1", "Card 2 (reverse)"])
  final List<String> _templateNames;

  /// Card template names (e.g. ["Card 1", "Card 2 (reverse)"])
  @override
  @JsonKey()
  List<String> get templateNames {
    if (_templateNames is EqualUnmodifiableListView) return _templateNames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_templateNames);
  }

  /// Whether this is a Cloze notetype
  @override
  @JsonKey()
  final bool isCloze;

  /// Create a copy of AnkiNotetype
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiNotetypeCopyWith<_AnkiNotetype> get copyWith =>
      __$AnkiNotetypeCopyWithImpl<_AnkiNotetype>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AnkiNotetypeToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiNotetype &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality()
                .equals(other._fieldNames, _fieldNames) &&
            const DeepCollectionEquality()
                .equals(other._templateNames, _templateNames) &&
            (identical(other.isCloze, isCloze) || other.isCloze == isCloze));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      const DeepCollectionEquality().hash(_fieldNames),
      const DeepCollectionEquality().hash(_templateNames),
      isCloze);

  @override
  String toString() {
    return 'AnkiNotetype(id: $id, name: $name, fieldNames: $fieldNames, templateNames: $templateNames, isCloze: $isCloze)';
  }
}

/// @nodoc
abstract mixin class _$AnkiNotetypeCopyWith<$Res>
    implements $AnkiNotetypeCopyWith<$Res> {
  factory _$AnkiNotetypeCopyWith(
          _AnkiNotetype value, $Res Function(_AnkiNotetype) _then) =
      __$AnkiNotetypeCopyWithImpl;
  @override
  @useResult
  $Res call(
      {int id,
      String name,
      List<String> fieldNames,
      List<String> templateNames,
      bool isCloze});
}

/// @nodoc
class __$AnkiNotetypeCopyWithImpl<$Res>
    implements _$AnkiNotetypeCopyWith<$Res> {
  __$AnkiNotetypeCopyWithImpl(this._self, this._then);

  final _AnkiNotetype _self;
  final $Res Function(_AnkiNotetype) _then;

  /// Create a copy of AnkiNotetype
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? fieldNames = null,
    Object? templateNames = null,
    Object? isCloze = null,
  }) {
    return _then(_AnkiNotetype(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      fieldNames: null == fieldNames
          ? _self._fieldNames
          : fieldNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      templateNames: null == templateNames
          ? _self._templateNames
          : templateNames // ignore: cast_nullable_to_non_nullable
              as List<String>,
      isCloze: null == isCloze
          ? _self.isCloze
          : isCloze // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
mixin _$AnkiDeckInfo {
  int get id;
  String get name;

  /// Parent deck id (0 or absent for top-level)
  int get parentId;

  /// Number of cards in this deck (computed)
  int get cardCount;

  /// Create a copy of AnkiDeckInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiDeckInfoCopyWith<AnkiDeckInfo> get copyWith =>
      _$AnkiDeckInfoCopyWithImpl<AnkiDeckInfo>(
          this as AnkiDeckInfo, _$identity);

  /// Serializes this AnkiDeckInfo to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiDeckInfo &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.parentId, parentId) ||
                other.parentId == parentId) &&
            (identical(other.cardCount, cardCount) ||
                other.cardCount == cardCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, parentId, cardCount);

  @override
  String toString() {
    return 'AnkiDeckInfo(id: $id, name: $name, parentId: $parentId, cardCount: $cardCount)';
  }
}

/// @nodoc
abstract mixin class $AnkiDeckInfoCopyWith<$Res> {
  factory $AnkiDeckInfoCopyWith(
          AnkiDeckInfo value, $Res Function(AnkiDeckInfo) _then) =
      _$AnkiDeckInfoCopyWithImpl;
  @useResult
  $Res call({int id, String name, int parentId, int cardCount});
}

/// @nodoc
class _$AnkiDeckInfoCopyWithImpl<$Res> implements $AnkiDeckInfoCopyWith<$Res> {
  _$AnkiDeckInfoCopyWithImpl(this._self, this._then);

  final AnkiDeckInfo _self;
  final $Res Function(AnkiDeckInfo) _then;

  /// Create a copy of AnkiDeckInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? parentId = null,
    Object? cardCount = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      parentId: null == parentId
          ? _self.parentId
          : parentId // ignore: cast_nullable_to_non_nullable
              as int,
      cardCount: null == cardCount
          ? _self.cardCount
          : cardCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiDeckInfo].
extension AnkiDeckInfoPatterns on AnkiDeckInfo {
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
    TResult Function(_AnkiDeckInfo value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiDeckInfo() when $default != null:
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
    TResult Function(_AnkiDeckInfo value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiDeckInfo():
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
    TResult? Function(_AnkiDeckInfo value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiDeckInfo() when $default != null:
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
    TResult Function(int id, String name, int parentId, int cardCount)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiDeckInfo() when $default != null:
        return $default(_that.id, _that.name, _that.parentId, _that.cardCount);
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
    TResult Function(int id, String name, int parentId, int cardCount) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiDeckInfo():
        return $default(_that.id, _that.name, _that.parentId, _that.cardCount);
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
    TResult? Function(int id, String name, int parentId, int cardCount)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiDeckInfo() when $default != null:
        return $default(_that.id, _that.name, _that.parentId, _that.cardCount);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _AnkiDeckInfo implements AnkiDeckInfo {
  const _AnkiDeckInfo(
      {required this.id,
      required this.name,
      this.parentId = 0,
      this.cardCount = 0});
  factory _AnkiDeckInfo.fromJson(Map<String, dynamic> json) =>
      _$AnkiDeckInfoFromJson(json);

  @override
  final int id;
  @override
  final String name;

  /// Parent deck id (0 or absent for top-level)
  @override
  @JsonKey()
  final int parentId;

  /// Number of cards in this deck (computed)
  @override
  @JsonKey()
  final int cardCount;

  /// Create a copy of AnkiDeckInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiDeckInfoCopyWith<_AnkiDeckInfo> get copyWith =>
      __$AnkiDeckInfoCopyWithImpl<_AnkiDeckInfo>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AnkiDeckInfoToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiDeckInfo &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.parentId, parentId) ||
                other.parentId == parentId) &&
            (identical(other.cardCount, cardCount) ||
                other.cardCount == cardCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, parentId, cardCount);

  @override
  String toString() {
    return 'AnkiDeckInfo(id: $id, name: $name, parentId: $parentId, cardCount: $cardCount)';
  }
}

/// @nodoc
abstract mixin class _$AnkiDeckInfoCopyWith<$Res>
    implements $AnkiDeckInfoCopyWith<$Res> {
  factory _$AnkiDeckInfoCopyWith(
          _AnkiDeckInfo value, $Res Function(_AnkiDeckInfo) _then) =
      __$AnkiDeckInfoCopyWithImpl;
  @override
  @useResult
  $Res call({int id, String name, int parentId, int cardCount});
}

/// @nodoc
class __$AnkiDeckInfoCopyWithImpl<$Res>
    implements _$AnkiDeckInfoCopyWith<$Res> {
  __$AnkiDeckInfoCopyWithImpl(this._self, this._then);

  final _AnkiDeckInfo _self;
  final $Res Function(_AnkiDeckInfo) _then;

  /// Create a copy of AnkiDeckInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? parentId = null,
    Object? cardCount = null,
  }) {
    return _then(_AnkiDeckInfo(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      parentId: null == parentId
          ? _self.parentId
          : parentId // ignore: cast_nullable_to_non_nullable
              as int,
      cardCount: null == cardCount
          ? _self.cardCount
          : cardCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
mixin _$AnkiNote {
  /// Anki note id (millisecond timestamp, globally unique)
  int get id;

  /// Global unique id string
  String get guid;

  /// Notetype model id (references AnkiNotetype.id)
  int get mid;

  /// Modification timestamp (seconds)
  int get mod;

  /// Space-separated tags
  String get tags;

  /// Field values split by \x1f — aligned with notetype fieldNames
  List<String> get fields;

  /// Sort field (first field content, used for duplicate detection)
  String get sortField;

  /// Create a copy of AnkiNote
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiNoteCopyWith<AnkiNote> get copyWith =>
      _$AnkiNoteCopyWithImpl<AnkiNote>(this as AnkiNote, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiNote &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.guid, guid) || other.guid == guid) &&
            (identical(other.mid, mid) || other.mid == mid) &&
            (identical(other.mod, mod) || other.mod == mod) &&
            (identical(other.tags, tags) || other.tags == tags) &&
            const DeepCollectionEquality().equals(other.fields, fields) &&
            (identical(other.sortField, sortField) ||
                other.sortField == sortField));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, guid, mid, mod, tags,
      const DeepCollectionEquality().hash(fields), sortField);

  @override
  String toString() {
    return 'AnkiNote(id: $id, guid: $guid, mid: $mid, mod: $mod, tags: $tags, fields: $fields, sortField: $sortField)';
  }
}

/// @nodoc
abstract mixin class $AnkiNoteCopyWith<$Res> {
  factory $AnkiNoteCopyWith(AnkiNote value, $Res Function(AnkiNote) _then) =
      _$AnkiNoteCopyWithImpl;
  @useResult
  $Res call(
      {int id,
      String guid,
      int mid,
      int mod,
      String tags,
      List<String> fields,
      String sortField});
}

/// @nodoc
class _$AnkiNoteCopyWithImpl<$Res> implements $AnkiNoteCopyWith<$Res> {
  _$AnkiNoteCopyWithImpl(this._self, this._then);

  final AnkiNote _self;
  final $Res Function(AnkiNote) _then;

  /// Create a copy of AnkiNote
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? guid = null,
    Object? mid = null,
    Object? mod = null,
    Object? tags = null,
    Object? fields = null,
    Object? sortField = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      guid: null == guid
          ? _self.guid
          : guid // ignore: cast_nullable_to_non_nullable
              as String,
      mid: null == mid
          ? _self.mid
          : mid // ignore: cast_nullable_to_non_nullable
              as int,
      mod: null == mod
          ? _self.mod
          : mod // ignore: cast_nullable_to_non_nullable
              as int,
      tags: null == tags
          ? _self.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as String,
      fields: null == fields
          ? _self.fields
          : fields // ignore: cast_nullable_to_non_nullable
              as List<String>,
      sortField: null == sortField
          ? _self.sortField
          : sortField // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiNote].
extension AnkiNotePatterns on AnkiNote {
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
    TResult Function(_AnkiNote value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiNote() when $default != null:
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
    TResult Function(_AnkiNote value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNote():
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
    TResult? Function(_AnkiNote value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNote() when $default != null:
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
    TResult Function(int id, String guid, int mid, int mod, String tags,
            List<String> fields, String sortField)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiNote() when $default != null:
        return $default(_that.id, _that.guid, _that.mid, _that.mod, _that.tags,
            _that.fields, _that.sortField);
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
    TResult Function(int id, String guid, int mid, int mod, String tags,
            List<String> fields, String sortField)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNote():
        return $default(_that.id, _that.guid, _that.mid, _that.mod, _that.tags,
            _that.fields, _that.sortField);
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
    TResult? Function(int id, String guid, int mid, int mod, String tags,
            List<String> fields, String sortField)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNote() when $default != null:
        return $default(_that.id, _that.guid, _that.mid, _that.mod, _that.tags,
            _that.fields, _that.sortField);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _AnkiNote implements AnkiNote {
  const _AnkiNote(
      {required this.id,
      this.guid = '',
      required this.mid,
      this.mod = 0,
      this.tags = '',
      required final List<String> fields,
      this.sortField = ''})
      : _fields = fields;

  /// Anki note id (millisecond timestamp, globally unique)
  @override
  final int id;

  /// Global unique id string
  @override
  @JsonKey()
  final String guid;

  /// Notetype model id (references AnkiNotetype.id)
  @override
  final int mid;

  /// Modification timestamp (seconds)
  @override
  @JsonKey()
  final int mod;

  /// Space-separated tags
  @override
  @JsonKey()
  final String tags;

  /// Field values split by \x1f — aligned with notetype fieldNames
  final List<String> _fields;

  /// Field values split by \x1f — aligned with notetype fieldNames
  @override
  List<String> get fields {
    if (_fields is EqualUnmodifiableListView) return _fields;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_fields);
  }

  /// Sort field (first field content, used for duplicate detection)
  @override
  @JsonKey()
  final String sortField;

  /// Create a copy of AnkiNote
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiNoteCopyWith<_AnkiNote> get copyWith =>
      __$AnkiNoteCopyWithImpl<_AnkiNote>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiNote &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.guid, guid) || other.guid == guid) &&
            (identical(other.mid, mid) || other.mid == mid) &&
            (identical(other.mod, mod) || other.mod == mod) &&
            (identical(other.tags, tags) || other.tags == tags) &&
            const DeepCollectionEquality().equals(other._fields, _fields) &&
            (identical(other.sortField, sortField) ||
                other.sortField == sortField));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, guid, mid, mod, tags,
      const DeepCollectionEquality().hash(_fields), sortField);

  @override
  String toString() {
    return 'AnkiNote(id: $id, guid: $guid, mid: $mid, mod: $mod, tags: $tags, fields: $fields, sortField: $sortField)';
  }
}

/// @nodoc
abstract mixin class _$AnkiNoteCopyWith<$Res>
    implements $AnkiNoteCopyWith<$Res> {
  factory _$AnkiNoteCopyWith(_AnkiNote value, $Res Function(_AnkiNote) _then) =
      __$AnkiNoteCopyWithImpl;
  @override
  @useResult
  $Res call(
      {int id,
      String guid,
      int mid,
      int mod,
      String tags,
      List<String> fields,
      String sortField});
}

/// @nodoc
class __$AnkiNoteCopyWithImpl<$Res> implements _$AnkiNoteCopyWith<$Res> {
  __$AnkiNoteCopyWithImpl(this._self, this._then);

  final _AnkiNote _self;
  final $Res Function(_AnkiNote) _then;

  /// Create a copy of AnkiNote
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? guid = null,
    Object? mid = null,
    Object? mod = null,
    Object? tags = null,
    Object? fields = null,
    Object? sortField = null,
  }) {
    return _then(_AnkiNote(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      guid: null == guid
          ? _self.guid
          : guid // ignore: cast_nullable_to_non_nullable
              as String,
      mid: null == mid
          ? _self.mid
          : mid // ignore: cast_nullable_to_non_nullable
              as int,
      mod: null == mod
          ? _self.mod
          : mod // ignore: cast_nullable_to_non_nullable
              as int,
      tags: null == tags
          ? _self.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as String,
      fields: null == fields
          ? _self._fields
          : fields // ignore: cast_nullable_to_non_nullable
              as List<String>,
      sortField: null == sortField
          ? _self.sortField
          : sortField // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$AnkiCardData {
  int get id;

  /// Note id this card belongs to
  int get nid;

  /// Deck id
  int get did;

  /// Card template ordinal (which template generated this card)
  int get ord;

  /// Card type: 0=new, 1=learning, 2=review, 3=relearning
  int get type;

  /// Queue: -2=buried, -1=suspended, 0=new, 1=learning, 2=review, 3=day-learn
  int get queue;

  /// Due value — semantics depend on [queue]:
  /// queue=0: position among new cards
  /// queue=1/3: minutes since collection creation
  /// queue=2: days since collection creation
  int get due;

  /// Current interval in days
  int get ivl;

  /// Ease factor × 1000 (e.g. 2500 = 2.5)
  int get factor;

  /// Number of successful reviews
  int get reps;

  /// Number of times forgotten
  int get lapses;

  /// Create a copy of AnkiCardData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiCardDataCopyWith<AnkiCardData> get copyWith =>
      _$AnkiCardDataCopyWithImpl<AnkiCardData>(
          this as AnkiCardData, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiCardData &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.nid, nid) || other.nid == nid) &&
            (identical(other.did, did) || other.did == did) &&
            (identical(other.ord, ord) || other.ord == ord) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.queue, queue) || other.queue == queue) &&
            (identical(other.due, due) || other.due == due) &&
            (identical(other.ivl, ivl) || other.ivl == ivl) &&
            (identical(other.factor, factor) || other.factor == factor) &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.lapses, lapses) || other.lapses == lapses));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, nid, did, ord, type, queue,
      due, ivl, factor, reps, lapses);

  @override
  String toString() {
    return 'AnkiCardData(id: $id, nid: $nid, did: $did, ord: $ord, type: $type, queue: $queue, due: $due, ivl: $ivl, factor: $factor, reps: $reps, lapses: $lapses)';
  }
}

/// @nodoc
abstract mixin class $AnkiCardDataCopyWith<$Res> {
  factory $AnkiCardDataCopyWith(
          AnkiCardData value, $Res Function(AnkiCardData) _then) =
      _$AnkiCardDataCopyWithImpl;
  @useResult
  $Res call(
      {int id,
      int nid,
      int did,
      int ord,
      int type,
      int queue,
      int due,
      int ivl,
      int factor,
      int reps,
      int lapses});
}

/// @nodoc
class _$AnkiCardDataCopyWithImpl<$Res> implements $AnkiCardDataCopyWith<$Res> {
  _$AnkiCardDataCopyWithImpl(this._self, this._then);

  final AnkiCardData _self;
  final $Res Function(AnkiCardData) _then;

  /// Create a copy of AnkiCardData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? nid = null,
    Object? did = null,
    Object? ord = null,
    Object? type = null,
    Object? queue = null,
    Object? due = null,
    Object? ivl = null,
    Object? factor = null,
    Object? reps = null,
    Object? lapses = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      nid: null == nid
          ? _self.nid
          : nid // ignore: cast_nullable_to_non_nullable
              as int,
      did: null == did
          ? _self.did
          : did // ignore: cast_nullable_to_non_nullable
              as int,
      ord: null == ord
          ? _self.ord
          : ord // ignore: cast_nullable_to_non_nullable
              as int,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as int,
      queue: null == queue
          ? _self.queue
          : queue // ignore: cast_nullable_to_non_nullable
              as int,
      due: null == due
          ? _self.due
          : due // ignore: cast_nullable_to_non_nullable
              as int,
      ivl: null == ivl
          ? _self.ivl
          : ivl // ignore: cast_nullable_to_non_nullable
              as int,
      factor: null == factor
          ? _self.factor
          : factor // ignore: cast_nullable_to_non_nullable
              as int,
      reps: null == reps
          ? _self.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      lapses: null == lapses
          ? _self.lapses
          : lapses // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiCardData].
extension AnkiCardDataPatterns on AnkiCardData {
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
    TResult Function(_AnkiCardData value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiCardData() when $default != null:
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
    TResult Function(_AnkiCardData value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCardData():
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
    TResult? Function(_AnkiCardData value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCardData() when $default != null:
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
    TResult Function(int id, int nid, int did, int ord, int type, int queue,
            int due, int ivl, int factor, int reps, int lapses)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiCardData() when $default != null:
        return $default(
            _that.id,
            _that.nid,
            _that.did,
            _that.ord,
            _that.type,
            _that.queue,
            _that.due,
            _that.ivl,
            _that.factor,
            _that.reps,
            _that.lapses);
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
    TResult Function(int id, int nid, int did, int ord, int type, int queue,
            int due, int ivl, int factor, int reps, int lapses)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCardData():
        return $default(
            _that.id,
            _that.nid,
            _that.did,
            _that.ord,
            _that.type,
            _that.queue,
            _that.due,
            _that.ivl,
            _that.factor,
            _that.reps,
            _that.lapses);
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
    TResult? Function(int id, int nid, int did, int ord, int type, int queue,
            int due, int ivl, int factor, int reps, int lapses)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCardData() when $default != null:
        return $default(
            _that.id,
            _that.nid,
            _that.did,
            _that.ord,
            _that.type,
            _that.queue,
            _that.due,
            _that.ivl,
            _that.factor,
            _that.reps,
            _that.lapses);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _AnkiCardData implements AnkiCardData {
  const _AnkiCardData(
      {required this.id,
      required this.nid,
      required this.did,
      this.ord = 0,
      this.type = 0,
      this.queue = 0,
      this.due = 0,
      this.ivl = 0,
      this.factor = 2500,
      this.reps = 0,
      this.lapses = 0});

  @override
  final int id;

  /// Note id this card belongs to
  @override
  final int nid;

  /// Deck id
  @override
  final int did;

  /// Card template ordinal (which template generated this card)
  @override
  @JsonKey()
  final int ord;

  /// Card type: 0=new, 1=learning, 2=review, 3=relearning
  @override
  @JsonKey()
  final int type;

  /// Queue: -2=buried, -1=suspended, 0=new, 1=learning, 2=review, 3=day-learn
  @override
  @JsonKey()
  final int queue;

  /// Due value — semantics depend on [queue]:
  /// queue=0: position among new cards
  /// queue=1/3: minutes since collection creation
  /// queue=2: days since collection creation
  @override
  @JsonKey()
  final int due;

  /// Current interval in days
  @override
  @JsonKey()
  final int ivl;

  /// Ease factor × 1000 (e.g. 2500 = 2.5)
  @override
  @JsonKey()
  final int factor;

  /// Number of successful reviews
  @override
  @JsonKey()
  final int reps;

  /// Number of times forgotten
  @override
  @JsonKey()
  final int lapses;

  /// Create a copy of AnkiCardData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiCardDataCopyWith<_AnkiCardData> get copyWith =>
      __$AnkiCardDataCopyWithImpl<_AnkiCardData>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiCardData &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.nid, nid) || other.nid == nid) &&
            (identical(other.did, did) || other.did == did) &&
            (identical(other.ord, ord) || other.ord == ord) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.queue, queue) || other.queue == queue) &&
            (identical(other.due, due) || other.due == due) &&
            (identical(other.ivl, ivl) || other.ivl == ivl) &&
            (identical(other.factor, factor) || other.factor == factor) &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.lapses, lapses) || other.lapses == lapses));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, nid, did, ord, type, queue,
      due, ivl, factor, reps, lapses);

  @override
  String toString() {
    return 'AnkiCardData(id: $id, nid: $nid, did: $did, ord: $ord, type: $type, queue: $queue, due: $due, ivl: $ivl, factor: $factor, reps: $reps, lapses: $lapses)';
  }
}

/// @nodoc
abstract mixin class _$AnkiCardDataCopyWith<$Res>
    implements $AnkiCardDataCopyWith<$Res> {
  factory _$AnkiCardDataCopyWith(
          _AnkiCardData value, $Res Function(_AnkiCardData) _then) =
      __$AnkiCardDataCopyWithImpl;
  @override
  @useResult
  $Res call(
      {int id,
      int nid,
      int did,
      int ord,
      int type,
      int queue,
      int due,
      int ivl,
      int factor,
      int reps,
      int lapses});
}

/// @nodoc
class __$AnkiCardDataCopyWithImpl<$Res>
    implements _$AnkiCardDataCopyWith<$Res> {
  __$AnkiCardDataCopyWithImpl(this._self, this._then);

  final _AnkiCardData _self;
  final $Res Function(_AnkiCardData) _then;

  /// Create a copy of AnkiCardData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? nid = null,
    Object? did = null,
    Object? ord = null,
    Object? type = null,
    Object? queue = null,
    Object? due = null,
    Object? ivl = null,
    Object? factor = null,
    Object? reps = null,
    Object? lapses = null,
  }) {
    return _then(_AnkiCardData(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      nid: null == nid
          ? _self.nid
          : nid // ignore: cast_nullable_to_non_nullable
              as int,
      did: null == did
          ? _self.did
          : did // ignore: cast_nullable_to_non_nullable
              as int,
      ord: null == ord
          ? _self.ord
          : ord // ignore: cast_nullable_to_non_nullable
              as int,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as int,
      queue: null == queue
          ? _self.queue
          : queue // ignore: cast_nullable_to_non_nullable
              as int,
      due: null == due
          ? _self.due
          : due // ignore: cast_nullable_to_non_nullable
              as int,
      ivl: null == ivl
          ? _self.ivl
          : ivl // ignore: cast_nullable_to_non_nullable
              as int,
      factor: null == factor
          ? _self.factor
          : factor // ignore: cast_nullable_to_non_nullable
              as int,
      reps: null == reps
          ? _self.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      lapses: null == lapses
          ? _self.lapses
          : lapses // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
