// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'listening_phase.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ListeningPhase {
  String get id;
  String get name;

  /// Which part of the listening lesson this phase represents.
  ListeningPhaseType get type;

  /// Audio asset to play for this phase.
  String? get audioAsset;

  /// Optional transcript shown after the audio has played.
  String get transcript;

  /// Interactions for this phase. Word-pairing and dialogue phases use these;
  /// summary phases leave it empty.
  List<Interaction> get items;

  /// Create a copy of ListeningPhase
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ListeningPhaseCopyWith<ListeningPhase> get copyWith =>
      _$ListeningPhaseCopyWithImpl<ListeningPhase>(
          this as ListeningPhase, _$identity);

  /// Serializes this ListeningPhase to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ListeningPhase &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.transcript, transcript) ||
                other.transcript == transcript) &&
            const DeepCollectionEquality().equals(other.items, items));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, type, audioAsset,
      transcript, const DeepCollectionEquality().hash(items));

  @override
  String toString() {
    return 'ListeningPhase(id: $id, name: $name, type: $type, audioAsset: $audioAsset, transcript: $transcript, items: $items)';
  }
}

/// @nodoc
abstract mixin class $ListeningPhaseCopyWith<$Res> {
  factory $ListeningPhaseCopyWith(
          ListeningPhase value, $Res Function(ListeningPhase) _then) =
      _$ListeningPhaseCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String name,
      ListeningPhaseType type,
      String? audioAsset,
      String transcript,
      List<Interaction> items});
}

/// @nodoc
class _$ListeningPhaseCopyWithImpl<$Res>
    implements $ListeningPhaseCopyWith<$Res> {
  _$ListeningPhaseCopyWithImpl(this._self, this._then);

  final ListeningPhase _self;
  final $Res Function(ListeningPhase) _then;

  /// Create a copy of ListeningPhase
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? audioAsset = freezed,
    Object? transcript = null,
    Object? items = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as ListeningPhaseType,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: null == transcript
          ? _self.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _self.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ));
  }
}

/// Adds pattern-matching-related methods to [ListeningPhase].
extension ListeningPhasePatterns on ListeningPhase {
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
    TResult Function(_ListeningPhase value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ListeningPhase() when $default != null:
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
    TResult Function(_ListeningPhase value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ListeningPhase():
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
    TResult? Function(_ListeningPhase value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ListeningPhase() when $default != null:
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
    TResult Function(String id, String name, ListeningPhaseType type,
            String? audioAsset, String transcript, List<Interaction> items)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _ListeningPhase() when $default != null:
        return $default(_that.id, _that.name, _that.type, _that.audioAsset,
            _that.transcript, _that.items);
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
    TResult Function(String id, String name, ListeningPhaseType type,
            String? audioAsset, String transcript, List<Interaction> items)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ListeningPhase():
        return $default(_that.id, _that.name, _that.type, _that.audioAsset,
            _that.transcript, _that.items);
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
    TResult? Function(String id, String name, ListeningPhaseType type,
            String? audioAsset, String transcript, List<Interaction> items)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _ListeningPhase() when $default != null:
        return $default(_that.id, _that.name, _that.type, _that.audioAsset,
            _that.transcript, _that.items);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _ListeningPhase implements ListeningPhase {
  const _ListeningPhase(
      {required this.id,
      required this.name,
      this.type = ListeningPhaseType.dialogue,
      this.audioAsset,
      this.transcript = '',
      final List<Interaction> items = const <Interaction>[]})
      : _items = items;
  factory _ListeningPhase.fromJson(Map<String, dynamic> json) =>
      _$ListeningPhaseFromJson(json);

  @override
  final String id;
  @override
  final String name;

  /// Which part of the listening lesson this phase represents.
  @override
  @JsonKey()
  final ListeningPhaseType type;

  /// Audio asset to play for this phase.
  @override
  final String? audioAsset;

  /// Optional transcript shown after the audio has played.
  @override
  @JsonKey()
  final String transcript;

  /// Interactions for this phase. Word-pairing and dialogue phases use these;
  /// summary phases leave it empty.
  final List<Interaction> _items;

  /// Interactions for this phase. Word-pairing and dialogue phases use these;
  /// summary phases leave it empty.
  @override
  @JsonKey()
  List<Interaction> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  /// Create a copy of ListeningPhase
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ListeningPhaseCopyWith<_ListeningPhase> get copyWith =>
      __$ListeningPhaseCopyWithImpl<_ListeningPhase>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ListeningPhaseToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ListeningPhase &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.transcript, transcript) ||
                other.transcript == transcript) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, type, audioAsset,
      transcript, const DeepCollectionEquality().hash(_items));

  @override
  String toString() {
    return 'ListeningPhase(id: $id, name: $name, type: $type, audioAsset: $audioAsset, transcript: $transcript, items: $items)';
  }
}

/// @nodoc
abstract mixin class _$ListeningPhaseCopyWith<$Res>
    implements $ListeningPhaseCopyWith<$Res> {
  factory _$ListeningPhaseCopyWith(
          _ListeningPhase value, $Res Function(_ListeningPhase) _then) =
      __$ListeningPhaseCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      ListeningPhaseType type,
      String? audioAsset,
      String transcript,
      List<Interaction> items});
}

/// @nodoc
class __$ListeningPhaseCopyWithImpl<$Res>
    implements _$ListeningPhaseCopyWith<$Res> {
  __$ListeningPhaseCopyWithImpl(this._self, this._then);

  final _ListeningPhase _self;
  final $Res Function(_ListeningPhase) _then;

  /// Create a copy of ListeningPhase
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? type = null,
    Object? audioAsset = freezed,
    Object? transcript = null,
    Object? items = null,
  }) {
    return _then(_ListeningPhase(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as ListeningPhaseType,
      audioAsset: freezed == audioAsset
          ? _self.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: null == transcript
          ? _self.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _self._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ));
  }
}

// dart format on
