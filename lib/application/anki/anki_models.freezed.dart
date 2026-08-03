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

  /// SHA-256 of the source `.apkg`/`.colpkg` bytes, computed once during
  /// parsing so callers (e.g. the import wizard) can detect re-imports
  /// without re-reading the whole file.
  String get sourceHash;

  /// Review log entries (rows from the Anki `revlog` table), used to
  /// backfill per-card review history so the memory-curve features have data
  /// immediately after import. Empty when the package has no revlog.
  List<AnkiRevlogEntry> get revlog;

  /// Collection creation time (`col.crt`, Unix seconds). Anki review-card
  /// due values are day offsets from this clock, not offsets from import
  /// time.
  int get collectionCreationTime;

  /// Raw deck configuration (`col.dconf`) retained for traceability and
  /// future scheduler-specific migrations.
  Map<String, dynamic> get deckConfigs;

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
                other.mediaDir == mediaDir) &&
            (identical(other.sourceHash, sourceHash) ||
                other.sourceHash == sourceHash) &&
            const DeepCollectionEquality().equals(other.revlog, revlog) &&
            (identical(other.collectionCreationTime, collectionCreationTime) ||
                other.collectionCreationTime == collectionCreationTime) &&
            const DeepCollectionEquality()
                .equals(other.deckConfigs, deckConfigs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(notetypes),
      const DeepCollectionEquality().hash(decks),
      const DeepCollectionEquality().hash(notes),
      const DeepCollectionEquality().hash(cards),
      const DeepCollectionEquality().hash(media),
      mediaDir,
      sourceHash,
      const DeepCollectionEquality().hash(revlog),
      collectionCreationTime,
      const DeepCollectionEquality().hash(deckConfigs));

  @override
  String toString() {
    return 'AnkiCollection(notetypes: $notetypes, decks: $decks, notes: $notes, cards: $cards, media: $media, mediaDir: $mediaDir, sourceHash: $sourceHash, revlog: $revlog, collectionCreationTime: $collectionCreationTime, deckConfigs: $deckConfigs)';
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
      String mediaDir,
      String sourceHash,
      List<AnkiRevlogEntry> revlog,
      int collectionCreationTime,
      Map<String, dynamic> deckConfigs});
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
    Object? sourceHash = null,
    Object? revlog = null,
    Object? collectionCreationTime = null,
    Object? deckConfigs = null,
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
      sourceHash: null == sourceHash
          ? _self.sourceHash
          : sourceHash // ignore: cast_nullable_to_non_nullable
              as String,
      revlog: null == revlog
          ? _self.revlog
          : revlog // ignore: cast_nullable_to_non_nullable
              as List<AnkiRevlogEntry>,
      collectionCreationTime: null == collectionCreationTime
          ? _self.collectionCreationTime
          : collectionCreationTime // ignore: cast_nullable_to_non_nullable
              as int,
      deckConfigs: null == deckConfigs
          ? _self.deckConfigs
          : deckConfigs // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
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
            String mediaDir,
            String sourceHash,
            List<AnkiRevlogEntry> revlog,
            int collectionCreationTime,
            Map<String, dynamic> deckConfigs)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection() when $default != null:
        return $default(
            _that.notetypes,
            _that.decks,
            _that.notes,
            _that.cards,
            _that.media,
            _that.mediaDir,
            _that.sourceHash,
            _that.revlog,
            _that.collectionCreationTime,
            _that.deckConfigs);
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
            String mediaDir,
            String sourceHash,
            List<AnkiRevlogEntry> revlog,
            int collectionCreationTime,
            Map<String, dynamic> deckConfigs)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection():
        return $default(
            _that.notetypes,
            _that.decks,
            _that.notes,
            _that.cards,
            _that.media,
            _that.mediaDir,
            _that.sourceHash,
            _that.revlog,
            _that.collectionCreationTime,
            _that.deckConfigs);
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
            String mediaDir,
            String sourceHash,
            List<AnkiRevlogEntry> revlog,
            int collectionCreationTime,
            Map<String, dynamic> deckConfigs)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiCollection() when $default != null:
        return $default(
            _that.notetypes,
            _that.decks,
            _that.notes,
            _that.cards,
            _that.media,
            _that.mediaDir,
            _that.sourceHash,
            _that.revlog,
            _that.collectionCreationTime,
            _that.deckConfigs);
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
      this.mediaDir = '',
      this.sourceHash = '',
      final List<AnkiRevlogEntry> revlog = const <AnkiRevlogEntry>[],
      this.collectionCreationTime = 0,
      final Map<String, dynamic> deckConfigs = const <String, dynamic>{}})
      : _notetypes = notetypes,
        _decks = decks,
        _notes = notes,
        _cards = cards,
        _media = media,
        _revlog = revlog,
        _deckConfigs = deckConfigs;

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

  /// SHA-256 of the source `.apkg`/`.colpkg` bytes, computed once during
  /// parsing so callers (e.g. the import wizard) can detect re-imports
  /// without re-reading the whole file.
  @override
  @JsonKey()
  final String sourceHash;

  /// Review log entries (rows from the Anki `revlog` table), used to
  /// backfill per-card review history so the memory-curve features have data
  /// immediately after import. Empty when the package has no revlog.
  final List<AnkiRevlogEntry> _revlog;

  /// Review log entries (rows from the Anki `revlog` table), used to
  /// backfill per-card review history so the memory-curve features have data
  /// immediately after import. Empty when the package has no revlog.
  @override
  @JsonKey()
  List<AnkiRevlogEntry> get revlog {
    if (_revlog is EqualUnmodifiableListView) return _revlog;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_revlog);
  }

  /// Collection creation time (`col.crt`, Unix seconds). Anki review-card
  /// due values are day offsets from this clock, not offsets from import
  /// time.
  @override
  @JsonKey()
  final int collectionCreationTime;

  /// Raw deck configuration (`col.dconf`) retained for traceability and
  /// future scheduler-specific migrations.
  final Map<String, dynamic> _deckConfigs;

  /// Raw deck configuration (`col.dconf`) retained for traceability and
  /// future scheduler-specific migrations.
  @override
  @JsonKey()
  Map<String, dynamic> get deckConfigs {
    if (_deckConfigs is EqualUnmodifiableMapView) return _deckConfigs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_deckConfigs);
  }

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
                other.mediaDir == mediaDir) &&
            (identical(other.sourceHash, sourceHash) ||
                other.sourceHash == sourceHash) &&
            const DeepCollectionEquality().equals(other._revlog, _revlog) &&
            (identical(other.collectionCreationTime, collectionCreationTime) ||
                other.collectionCreationTime == collectionCreationTime) &&
            const DeepCollectionEquality()
                .equals(other._deckConfigs, _deckConfigs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_notetypes),
      const DeepCollectionEquality().hash(_decks),
      const DeepCollectionEquality().hash(_notes),
      const DeepCollectionEquality().hash(_cards),
      const DeepCollectionEquality().hash(_media),
      mediaDir,
      sourceHash,
      const DeepCollectionEquality().hash(_revlog),
      collectionCreationTime,
      const DeepCollectionEquality().hash(_deckConfigs));

  @override
  String toString() {
    return 'AnkiCollection(notetypes: $notetypes, decks: $decks, notes: $notes, cards: $cards, media: $media, mediaDir: $mediaDir, sourceHash: $sourceHash, revlog: $revlog, collectionCreationTime: $collectionCreationTime, deckConfigs: $deckConfigs)';
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
      String mediaDir,
      String sourceHash,
      List<AnkiRevlogEntry> revlog,
      int collectionCreationTime,
      Map<String, dynamic> deckConfigs});
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
    Object? sourceHash = null,
    Object? revlog = null,
    Object? collectionCreationTime = null,
    Object? deckConfigs = null,
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
      sourceHash: null == sourceHash
          ? _self.sourceHash
          : sourceHash // ignore: cast_nullable_to_non_nullable
              as String,
      revlog: null == revlog
          ? _self._revlog
          : revlog // ignore: cast_nullable_to_non_nullable
              as List<AnkiRevlogEntry>,
      collectionCreationTime: null == collectionCreationTime
          ? _self.collectionCreationTime
          : collectionCreationTime // ignore: cast_nullable_to_non_nullable
              as int,
      deckConfigs: null == deckConfigs
          ? _self._deckConfigs
          : deckConfigs // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>,
    ));
  }
}

/// @nodoc
mixin _$AnkiTemplate {
  String get name;

  /// Question-side HTML template (`qfmt`)
  String get qfmt;

  /// Answer-side HTML template (`afmt`)
  String get afmt;

  /// Create a copy of AnkiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiTemplateCopyWith<AnkiTemplate> get copyWith =>
      _$AnkiTemplateCopyWithImpl<AnkiTemplate>(
          this as AnkiTemplate, _$identity);

  /// Serializes this AnkiTemplate to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiTemplate &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.qfmt, qfmt) || other.qfmt == qfmt) &&
            (identical(other.afmt, afmt) || other.afmt == afmt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name, qfmt, afmt);

  @override
  String toString() {
    return 'AnkiTemplate(name: $name, qfmt: $qfmt, afmt: $afmt)';
  }
}

/// @nodoc
abstract mixin class $AnkiTemplateCopyWith<$Res> {
  factory $AnkiTemplateCopyWith(
          AnkiTemplate value, $Res Function(AnkiTemplate) _then) =
      _$AnkiTemplateCopyWithImpl;
  @useResult
  $Res call({String name, String qfmt, String afmt});
}

/// @nodoc
class _$AnkiTemplateCopyWithImpl<$Res> implements $AnkiTemplateCopyWith<$Res> {
  _$AnkiTemplateCopyWithImpl(this._self, this._then);

  final AnkiTemplate _self;
  final $Res Function(AnkiTemplate) _then;

  /// Create a copy of AnkiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? qfmt = null,
    Object? afmt = null,
  }) {
    return _then(_self.copyWith(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      qfmt: null == qfmt
          ? _self.qfmt
          : qfmt // ignore: cast_nullable_to_non_nullable
              as String,
      afmt: null == afmt
          ? _self.afmt
          : afmt // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiTemplate].
extension AnkiTemplatePatterns on AnkiTemplate {
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
    TResult Function(_AnkiTemplate value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiTemplate() when $default != null:
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
    TResult Function(_AnkiTemplate value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiTemplate():
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
    TResult? Function(_AnkiTemplate value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiTemplate() when $default != null:
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
    TResult Function(String name, String qfmt, String afmt)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiTemplate() when $default != null:
        return $default(_that.name, _that.qfmt, _that.afmt);
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
    TResult Function(String name, String qfmt, String afmt) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiTemplate():
        return $default(_that.name, _that.qfmt, _that.afmt);
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
    TResult? Function(String name, String qfmt, String afmt)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiTemplate() when $default != null:
        return $default(_that.name, _that.qfmt, _that.afmt);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _AnkiTemplate implements AnkiTemplate {
  const _AnkiTemplate({required this.name, this.qfmt = '', this.afmt = ''});
  factory _AnkiTemplate.fromJson(Map<String, dynamic> json) =>
      _$AnkiTemplateFromJson(json);

  @override
  final String name;

  /// Question-side HTML template (`qfmt`)
  @override
  @JsonKey()
  final String qfmt;

  /// Answer-side HTML template (`afmt`)
  @override
  @JsonKey()
  final String afmt;

  /// Create a copy of AnkiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiTemplateCopyWith<_AnkiTemplate> get copyWith =>
      __$AnkiTemplateCopyWithImpl<_AnkiTemplate>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AnkiTemplateToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiTemplate &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.qfmt, qfmt) || other.qfmt == qfmt) &&
            (identical(other.afmt, afmt) || other.afmt == afmt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, name, qfmt, afmt);

  @override
  String toString() {
    return 'AnkiTemplate(name: $name, qfmt: $qfmt, afmt: $afmt)';
  }
}

/// @nodoc
abstract mixin class _$AnkiTemplateCopyWith<$Res>
    implements $AnkiTemplateCopyWith<$Res> {
  factory _$AnkiTemplateCopyWith(
          _AnkiTemplate value, $Res Function(_AnkiTemplate) _then) =
      __$AnkiTemplateCopyWithImpl;
  @override
  @useResult
  $Res call({String name, String qfmt, String afmt});
}

/// @nodoc
class __$AnkiTemplateCopyWithImpl<$Res>
    implements _$AnkiTemplateCopyWith<$Res> {
  __$AnkiTemplateCopyWithImpl(this._self, this._then);

  final _AnkiTemplate _self;
  final $Res Function(_AnkiTemplate) _then;

  /// Create a copy of AnkiTemplate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? name = null,
    Object? qfmt = null,
    Object? afmt = null,
  }) {
    return _then(_AnkiTemplate(
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      qfmt: null == qfmt
          ? _self.qfmt
          : qfmt // ignore: cast_nullable_to_non_nullable
              as String,
      afmt: null == afmt
          ? _self.afmt
          : afmt // ignore: cast_nullable_to_non_nullable
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

  /// Full card templates (aligned with [templateNames] by index; a card's
  /// `ord` selects which template renders it). Empty for imports parsed
  /// before template bodies were captured.
  List<AnkiTemplate> get templates;

  /// Whether this is a Cloze notetype
  bool get isCloze;

  /// Notetype-level CSS (the `css` key of an Anki model), injected into the
  /// fidelity-track WebView document so rendered cards match the Anki desktop
  /// preview (deep-adaptation plan §5.1). Empty for imports parsed before css
  /// capture was added.
  String get css;

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
            const DeepCollectionEquality().equals(other.templates, templates) &&
            (identical(other.isCloze, isCloze) || other.isCloze == isCloze) &&
            (identical(other.css, css) || other.css == css));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      const DeepCollectionEquality().hash(fieldNames),
      const DeepCollectionEquality().hash(templateNames),
      const DeepCollectionEquality().hash(templates),
      isCloze,
      css);

  @override
  String toString() {
    return 'AnkiNotetype(id: $id, name: $name, fieldNames: $fieldNames, templateNames: $templateNames, templates: $templates, isCloze: $isCloze, css: $css)';
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
      List<AnkiTemplate> templates,
      bool isCloze,
      String css});
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
    Object? templates = null,
    Object? isCloze = null,
    Object? css = null,
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
      templates: null == templates
          ? _self.templates
          : templates // ignore: cast_nullable_to_non_nullable
              as List<AnkiTemplate>,
      isCloze: null == isCloze
          ? _self.isCloze
          : isCloze // ignore: cast_nullable_to_non_nullable
              as bool,
      css: null == css
          ? _self.css
          : css // ignore: cast_nullable_to_non_nullable
              as String,
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
    TResult Function(
            int id,
            String name,
            List<String> fieldNames,
            List<String> templateNames,
            List<AnkiTemplate> templates,
            bool isCloze,
            String css)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype() when $default != null:
        return $default(_that.id, _that.name, _that.fieldNames,
            _that.templateNames, _that.templates, _that.isCloze, _that.css);
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
            int id,
            String name,
            List<String> fieldNames,
            List<String> templateNames,
            List<AnkiTemplate> templates,
            bool isCloze,
            String css)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype():
        return $default(_that.id, _that.name, _that.fieldNames,
            _that.templateNames, _that.templates, _that.isCloze, _that.css);
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
            int id,
            String name,
            List<String> fieldNames,
            List<String> templateNames,
            List<AnkiTemplate> templates,
            bool isCloze,
            String css)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiNotetype() when $default != null:
        return $default(_that.id, _that.name, _that.fieldNames,
            _that.templateNames, _that.templates, _that.isCloze, _that.css);
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
      final List<AnkiTemplate> templates = const <AnkiTemplate>[],
      this.isCloze = false,
      this.css = ''})
      : _fieldNames = fieldNames,
        _templateNames = templateNames,
        _templates = templates;
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

  /// Full card templates (aligned with [templateNames] by index; a card's
  /// `ord` selects which template renders it). Empty for imports parsed
  /// before template bodies were captured.
  final List<AnkiTemplate> _templates;

  /// Full card templates (aligned with [templateNames] by index; a card's
  /// `ord` selects which template renders it). Empty for imports parsed
  /// before template bodies were captured.
  @override
  @JsonKey()
  List<AnkiTemplate> get templates {
    if (_templates is EqualUnmodifiableListView) return _templates;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_templates);
  }

  /// Whether this is a Cloze notetype
  @override
  @JsonKey()
  final bool isCloze;

  /// Notetype-level CSS (the `css` key of an Anki model), injected into the
  /// fidelity-track WebView document so rendered cards match the Anki desktop
  /// preview (deep-adaptation plan §5.1). Empty for imports parsed before css
  /// capture was added.
  @override
  @JsonKey()
  final String css;

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
            const DeepCollectionEquality()
                .equals(other._templates, _templates) &&
            (identical(other.isCloze, isCloze) || other.isCloze == isCloze) &&
            (identical(other.css, css) || other.css == css));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      const DeepCollectionEquality().hash(_fieldNames),
      const DeepCollectionEquality().hash(_templateNames),
      const DeepCollectionEquality().hash(_templates),
      isCloze,
      css);

  @override
  String toString() {
    return 'AnkiNotetype(id: $id, name: $name, fieldNames: $fieldNames, templateNames: $templateNames, templates: $templates, isCloze: $isCloze, css: $css)';
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
      List<AnkiTemplate> templates,
      bool isCloze,
      String css});
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
    Object? templates = null,
    Object? isCloze = null,
    Object? css = null,
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
      templates: null == templates
          ? _self._templates
          : templates // ignore: cast_nullable_to_non_nullable
              as List<AnkiTemplate>,
      isCloze: null == isCloze
          ? _self.isCloze
          : isCloze // ignore: cast_nullable_to_non_nullable
              as bool,
      css: null == css
          ? _self.css
          : css // ignore: cast_nullable_to_non_nullable
              as String,
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

  /// Remaining learning repetitions/steps encoded by Anki's `left` field.
  int get left;

  /// Original due value retained for filtered/suspended cards.
  int get odue;

  /// Original deck id retained when a card was temporarily moved by Anki.
  int get odid;

  /// Anki card flags (including user flag bits).
  int get flags;

  /// Scheduler-specific opaque card data.
  String get data;

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
            (identical(other.lapses, lapses) || other.lapses == lapses) &&
            (identical(other.left, left) || other.left == left) &&
            (identical(other.odue, odue) || other.odue == odue) &&
            (identical(other.odid, odid) || other.odid == odid) &&
            (identical(other.flags, flags) || other.flags == flags) &&
            (identical(other.data, data) || other.data == data));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, nid, did, ord, type, queue,
      due, ivl, factor, reps, lapses, left, odue, odid, flags, data);

  @override
  String toString() {
    return 'AnkiCardData(id: $id, nid: $nid, did: $did, ord: $ord, type: $type, queue: $queue, due: $due, ivl: $ivl, factor: $factor, reps: $reps, lapses: $lapses, left: $left, odue: $odue, odid: $odid, flags: $flags, data: $data)';
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
      int lapses,
      int left,
      int odue,
      int odid,
      int flags,
      String data});
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
    Object? left = null,
    Object? odue = null,
    Object? odid = null,
    Object? flags = null,
    Object? data = null,
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
      left: null == left
          ? _self.left
          : left // ignore: cast_nullable_to_non_nullable
              as int,
      odue: null == odue
          ? _self.odue
          : odue // ignore: cast_nullable_to_non_nullable
              as int,
      odid: null == odid
          ? _self.odid
          : odid // ignore: cast_nullable_to_non_nullable
              as int,
      flags: null == flags
          ? _self.flags
          : flags // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _self.data
          : data // ignore: cast_nullable_to_non_nullable
              as String,
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
    TResult Function(
            int id,
            int nid,
            int did,
            int ord,
            int type,
            int queue,
            int due,
            int ivl,
            int factor,
            int reps,
            int lapses,
            int left,
            int odue,
            int odid,
            int flags,
            String data)?
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
            _that.lapses,
            _that.left,
            _that.odue,
            _that.odid,
            _that.flags,
            _that.data);
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
            int id,
            int nid,
            int did,
            int ord,
            int type,
            int queue,
            int due,
            int ivl,
            int factor,
            int reps,
            int lapses,
            int left,
            int odue,
            int odid,
            int flags,
            String data)
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
            _that.lapses,
            _that.left,
            _that.odue,
            _that.odid,
            _that.flags,
            _that.data);
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
            int id,
            int nid,
            int did,
            int ord,
            int type,
            int queue,
            int due,
            int ivl,
            int factor,
            int reps,
            int lapses,
            int left,
            int odue,
            int odid,
            int flags,
            String data)?
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
            _that.lapses,
            _that.left,
            _that.odue,
            _that.odid,
            _that.flags,
            _that.data);
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
      this.lapses = 0,
      this.left = 0,
      this.odue = 0,
      this.odid = 0,
      this.flags = 0,
      this.data = ''});

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

  /// Remaining learning repetitions/steps encoded by Anki's `left` field.
  @override
  @JsonKey()
  final int left;

  /// Original due value retained for filtered/suspended cards.
  @override
  @JsonKey()
  final int odue;

  /// Original deck id retained when a card was temporarily moved by Anki.
  @override
  @JsonKey()
  final int odid;

  /// Anki card flags (including user flag bits).
  @override
  @JsonKey()
  final int flags;

  /// Scheduler-specific opaque card data.
  @override
  @JsonKey()
  final String data;

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
            (identical(other.lapses, lapses) || other.lapses == lapses) &&
            (identical(other.left, left) || other.left == left) &&
            (identical(other.odue, odue) || other.odue == odue) &&
            (identical(other.odid, odid) || other.odid == odid) &&
            (identical(other.flags, flags) || other.flags == flags) &&
            (identical(other.data, data) || other.data == data));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, nid, did, ord, type, queue,
      due, ivl, factor, reps, lapses, left, odue, odid, flags, data);

  @override
  String toString() {
    return 'AnkiCardData(id: $id, nid: $nid, did: $did, ord: $ord, type: $type, queue: $queue, due: $due, ivl: $ivl, factor: $factor, reps: $reps, lapses: $lapses, left: $left, odue: $odue, odid: $odid, flags: $flags, data: $data)';
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
      int lapses,
      int left,
      int odue,
      int odid,
      int flags,
      String data});
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
    Object? left = null,
    Object? odue = null,
    Object? odid = null,
    Object? flags = null,
    Object? data = null,
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
      left: null == left
          ? _self.left
          : left // ignore: cast_nullable_to_non_nullable
              as int,
      odue: null == odue
          ? _self.odue
          : odue // ignore: cast_nullable_to_non_nullable
              as int,
      odid: null == odid
          ? _self.odid
          : odid // ignore: cast_nullable_to_non_nullable
              as int,
      flags: null == flags
          ? _self.flags
          : flags // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _self.data
          : data // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
mixin _$AnkiRevlogEntry {
  /// Review id = epoch milliseconds of the review (the row's primary key).
  int get id;

  /// Card id this review belongs to (references [AnkiCardData.id]).
  int get cid;
  int get usn;

  /// Button pressed: 1=again, 2=hard, 3=good, 4=easy (0 for manual/unset).
  int get ease;

  /// New interval after this review (days for review cards; negative =
  /// seconds for learning steps).
  int get ivl;

  /// Previous interval before this review (same unit rules as [ivl]).
  int get lastIvl;

  /// New ease factor × 1000 (e.g. 2500 = 2.5).
  int get factor;

  /// Time taken to answer, in milliseconds (not the review timestamp).
  int get time;

  /// Review type: 0=learning, 1=review, 2=relearning, 3=cram.
  int get type;

  /// Create a copy of AnkiRevlogEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AnkiRevlogEntryCopyWith<AnkiRevlogEntry> get copyWith =>
      _$AnkiRevlogEntryCopyWithImpl<AnkiRevlogEntry>(
          this as AnkiRevlogEntry, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AnkiRevlogEntry &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.cid, cid) || other.cid == cid) &&
            (identical(other.usn, usn) || other.usn == usn) &&
            (identical(other.ease, ease) || other.ease == ease) &&
            (identical(other.ivl, ivl) || other.ivl == ivl) &&
            (identical(other.lastIvl, lastIvl) || other.lastIvl == lastIvl) &&
            (identical(other.factor, factor) || other.factor == factor) &&
            (identical(other.time, time) || other.time == time) &&
            (identical(other.type, type) || other.type == type));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, id, cid, usn, ease, ivl, lastIvl, factor, time, type);

  @override
  String toString() {
    return 'AnkiRevlogEntry(id: $id, cid: $cid, usn: $usn, ease: $ease, ivl: $ivl, lastIvl: $lastIvl, factor: $factor, time: $time, type: $type)';
  }
}

/// @nodoc
abstract mixin class $AnkiRevlogEntryCopyWith<$Res> {
  factory $AnkiRevlogEntryCopyWith(
          AnkiRevlogEntry value, $Res Function(AnkiRevlogEntry) _then) =
      _$AnkiRevlogEntryCopyWithImpl;
  @useResult
  $Res call(
      {int id,
      int cid,
      int usn,
      int ease,
      int ivl,
      int lastIvl,
      int factor,
      int time,
      int type});
}

/// @nodoc
class _$AnkiRevlogEntryCopyWithImpl<$Res>
    implements $AnkiRevlogEntryCopyWith<$Res> {
  _$AnkiRevlogEntryCopyWithImpl(this._self, this._then);

  final AnkiRevlogEntry _self;
  final $Res Function(AnkiRevlogEntry) _then;

  /// Create a copy of AnkiRevlogEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? cid = null,
    Object? usn = null,
    Object? ease = null,
    Object? ivl = null,
    Object? lastIvl = null,
    Object? factor = null,
    Object? time = null,
    Object? type = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      cid: null == cid
          ? _self.cid
          : cid // ignore: cast_nullable_to_non_nullable
              as int,
      usn: null == usn
          ? _self.usn
          : usn // ignore: cast_nullable_to_non_nullable
              as int,
      ease: null == ease
          ? _self.ease
          : ease // ignore: cast_nullable_to_non_nullable
              as int,
      ivl: null == ivl
          ? _self.ivl
          : ivl // ignore: cast_nullable_to_non_nullable
              as int,
      lastIvl: null == lastIvl
          ? _self.lastIvl
          : lastIvl // ignore: cast_nullable_to_non_nullable
              as int,
      factor: null == factor
          ? _self.factor
          : factor // ignore: cast_nullable_to_non_nullable
              as int,
      time: null == time
          ? _self.time
          : time // ignore: cast_nullable_to_non_nullable
              as int,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// Adds pattern-matching-related methods to [AnkiRevlogEntry].
extension AnkiRevlogEntryPatterns on AnkiRevlogEntry {
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
    TResult Function(_AnkiRevlogEntry value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiRevlogEntry() when $default != null:
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
    TResult Function(_AnkiRevlogEntry value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiRevlogEntry():
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
    TResult? Function(_AnkiRevlogEntry value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiRevlogEntry() when $default != null:
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
    TResult Function(int id, int cid, int usn, int ease, int ivl, int lastIvl,
            int factor, int time, int type)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AnkiRevlogEntry() when $default != null:
        return $default(_that.id, _that.cid, _that.usn, _that.ease, _that.ivl,
            _that.lastIvl, _that.factor, _that.time, _that.type);
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
    TResult Function(int id, int cid, int usn, int ease, int ivl, int lastIvl,
            int factor, int time, int type)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiRevlogEntry():
        return $default(_that.id, _that.cid, _that.usn, _that.ease, _that.ivl,
            _that.lastIvl, _that.factor, _that.time, _that.type);
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
    TResult? Function(int id, int cid, int usn, int ease, int ivl, int lastIvl,
            int factor, int time, int type)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AnkiRevlogEntry() when $default != null:
        return $default(_that.id, _that.cid, _that.usn, _that.ease, _that.ivl,
            _that.lastIvl, _that.factor, _that.time, _that.type);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _AnkiRevlogEntry implements AnkiRevlogEntry {
  const _AnkiRevlogEntry(
      {required this.id,
      required this.cid,
      this.usn = 0,
      this.ease = 0,
      this.ivl = 0,
      this.lastIvl = 0,
      this.factor = 0,
      this.time = 0,
      this.type = 0});

  /// Review id = epoch milliseconds of the review (the row's primary key).
  @override
  final int id;

  /// Card id this review belongs to (references [AnkiCardData.id]).
  @override
  final int cid;
  @override
  @JsonKey()
  final int usn;

  /// Button pressed: 1=again, 2=hard, 3=good, 4=easy (0 for manual/unset).
  @override
  @JsonKey()
  final int ease;

  /// New interval after this review (days for review cards; negative =
  /// seconds for learning steps).
  @override
  @JsonKey()
  final int ivl;

  /// Previous interval before this review (same unit rules as [ivl]).
  @override
  @JsonKey()
  final int lastIvl;

  /// New ease factor × 1000 (e.g. 2500 = 2.5).
  @override
  @JsonKey()
  final int factor;

  /// Time taken to answer, in milliseconds (not the review timestamp).
  @override
  @JsonKey()
  final int time;

  /// Review type: 0=learning, 1=review, 2=relearning, 3=cram.
  @override
  @JsonKey()
  final int type;

  /// Create a copy of AnkiRevlogEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AnkiRevlogEntryCopyWith<_AnkiRevlogEntry> get copyWith =>
      __$AnkiRevlogEntryCopyWithImpl<_AnkiRevlogEntry>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AnkiRevlogEntry &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.cid, cid) || other.cid == cid) &&
            (identical(other.usn, usn) || other.usn == usn) &&
            (identical(other.ease, ease) || other.ease == ease) &&
            (identical(other.ivl, ivl) || other.ivl == ivl) &&
            (identical(other.lastIvl, lastIvl) || other.lastIvl == lastIvl) &&
            (identical(other.factor, factor) || other.factor == factor) &&
            (identical(other.time, time) || other.time == time) &&
            (identical(other.type, type) || other.type == type));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, id, cid, usn, ease, ivl, lastIvl, factor, time, type);

  @override
  String toString() {
    return 'AnkiRevlogEntry(id: $id, cid: $cid, usn: $usn, ease: $ease, ivl: $ivl, lastIvl: $lastIvl, factor: $factor, time: $time, type: $type)';
  }
}

/// @nodoc
abstract mixin class _$AnkiRevlogEntryCopyWith<$Res>
    implements $AnkiRevlogEntryCopyWith<$Res> {
  factory _$AnkiRevlogEntryCopyWith(
          _AnkiRevlogEntry value, $Res Function(_AnkiRevlogEntry) _then) =
      __$AnkiRevlogEntryCopyWithImpl;
  @override
  @useResult
  $Res call(
      {int id,
      int cid,
      int usn,
      int ease,
      int ivl,
      int lastIvl,
      int factor,
      int time,
      int type});
}

/// @nodoc
class __$AnkiRevlogEntryCopyWithImpl<$Res>
    implements _$AnkiRevlogEntryCopyWith<$Res> {
  __$AnkiRevlogEntryCopyWithImpl(this._self, this._then);

  final _AnkiRevlogEntry _self;
  final $Res Function(_AnkiRevlogEntry) _then;

  /// Create a copy of AnkiRevlogEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? cid = null,
    Object? usn = null,
    Object? ease = null,
    Object? ivl = null,
    Object? lastIvl = null,
    Object? factor = null,
    Object? time = null,
    Object? type = null,
  }) {
    return _then(_AnkiRevlogEntry(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as int,
      cid: null == cid
          ? _self.cid
          : cid // ignore: cast_nullable_to_non_nullable
              as int,
      usn: null == usn
          ? _self.usn
          : usn // ignore: cast_nullable_to_non_nullable
              as int,
      ease: null == ease
          ? _self.ease
          : ease // ignore: cast_nullable_to_non_nullable
              as int,
      ivl: null == ivl
          ? _self.ivl
          : ivl // ignore: cast_nullable_to_non_nullable
              as int,
      lastIvl: null == lastIvl
          ? _self.lastIvl
          : lastIvl // ignore: cast_nullable_to_non_nullable
              as int,
      factor: null == factor
          ? _self.factor
          : factor // ignore: cast_nullable_to_non_nullable
              as int,
      time: null == time
          ? _self.time
          : time // ignore: cast_nullable_to_non_nullable
              as int,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

// dart format on
