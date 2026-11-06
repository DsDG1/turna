// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'dialogue_scene.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DialogueCharacter {
  String get id;
  String get name;
  String? get imageAsset;

  /// Create a copy of DialogueCharacter
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DialogueCharacterCopyWith<DialogueCharacter> get copyWith =>
      _$DialogueCharacterCopyWithImpl<DialogueCharacter>(
          this as DialogueCharacter, _$identity);

  /// Serializes this DialogueCharacter to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DialogueCharacter &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.imageAsset, imageAsset) ||
                other.imageAsset == imageAsset));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, imageAsset);

  @override
  String toString() {
    return 'DialogueCharacter(id: $id, name: $name, imageAsset: $imageAsset)';
  }
}

/// @nodoc
abstract mixin class $DialogueCharacterCopyWith<$Res> {
  factory $DialogueCharacterCopyWith(
          DialogueCharacter value, $Res Function(DialogueCharacter) _then) =
      _$DialogueCharacterCopyWithImpl;
  @useResult
  $Res call({String id, String name, String? imageAsset});
}

/// @nodoc
class _$DialogueCharacterCopyWithImpl<$Res>
    implements $DialogueCharacterCopyWith<$Res> {
  _$DialogueCharacterCopyWithImpl(this._self, this._then);

  final DialogueCharacter _self;
  final $Res Function(DialogueCharacter) _then;

  /// Create a copy of DialogueCharacter
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? imageAsset = freezed,
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
      imageAsset: freezed == imageAsset
          ? _self.imageAsset
          : imageAsset // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [DialogueCharacter].
extension DialogueCharacterPatterns on DialogueCharacter {
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
    TResult Function(_DialogueCharacter value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DialogueCharacter() when $default != null:
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
    TResult Function(_DialogueCharacter value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueCharacter():
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
    TResult? Function(_DialogueCharacter value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueCharacter() when $default != null:
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
    TResult Function(String id, String name, String? imageAsset)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DialogueCharacter() when $default != null:
        return $default(_that.id, _that.name, _that.imageAsset);
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
    TResult Function(String id, String name, String? imageAsset) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueCharacter():
        return $default(_that.id, _that.name, _that.imageAsset);
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
    TResult? Function(String id, String name, String? imageAsset)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueCharacter() when $default != null:
        return $default(_that.id, _that.name, _that.imageAsset);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _DialogueCharacter implements DialogueCharacter {
  const _DialogueCharacter(
      {required this.id, required this.name, this.imageAsset});
  factory _DialogueCharacter.fromJson(Map<String, dynamic> json) =>
      _$DialogueCharacterFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? imageAsset;

  /// Create a copy of DialogueCharacter
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DialogueCharacterCopyWith<_DialogueCharacter> get copyWith =>
      __$DialogueCharacterCopyWithImpl<_DialogueCharacter>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$DialogueCharacterToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DialogueCharacter &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.imageAsset, imageAsset) ||
                other.imageAsset == imageAsset));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, imageAsset);

  @override
  String toString() {
    return 'DialogueCharacter(id: $id, name: $name, imageAsset: $imageAsset)';
  }
}

/// @nodoc
abstract mixin class _$DialogueCharacterCopyWith<$Res>
    implements $DialogueCharacterCopyWith<$Res> {
  factory _$DialogueCharacterCopyWith(
          _DialogueCharacter value, $Res Function(_DialogueCharacter) _then) =
      __$DialogueCharacterCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String name, String? imageAsset});
}

/// @nodoc
class __$DialogueCharacterCopyWithImpl<$Res>
    implements _$DialogueCharacterCopyWith<$Res> {
  __$DialogueCharacterCopyWithImpl(this._self, this._then);

  final _DialogueCharacter _self;
  final $Res Function(_DialogueCharacter) _then;

  /// Create a copy of DialogueCharacter
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? imageAsset = freezed,
  }) {
    return _then(_DialogueCharacter(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _self.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      imageAsset: freezed == imageAsset
          ? _self.imageAsset
          : imageAsset // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$DialogueTurn {
  String get id;
  String get speakerId;
  String? get text;
  String? get interactionId;

  /// Create a copy of DialogueTurn
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DialogueTurnCopyWith<DialogueTurn> get copyWith =>
      _$DialogueTurnCopyWithImpl<DialogueTurn>(
          this as DialogueTurn, _$identity);

  /// Serializes this DialogueTurn to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DialogueTurn &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.speakerId, speakerId) ||
                other.speakerId == speakerId) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.interactionId, interactionId) ||
                other.interactionId == interactionId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, speakerId, text, interactionId);

  @override
  String toString() {
    return 'DialogueTurn(id: $id, speakerId: $speakerId, text: $text, interactionId: $interactionId)';
  }
}

/// @nodoc
abstract mixin class $DialogueTurnCopyWith<$Res> {
  factory $DialogueTurnCopyWith(
          DialogueTurn value, $Res Function(DialogueTurn) _then) =
      _$DialogueTurnCopyWithImpl;
  @useResult
  $Res call({String id, String speakerId, String? text, String? interactionId});
}

/// @nodoc
class _$DialogueTurnCopyWithImpl<$Res> implements $DialogueTurnCopyWith<$Res> {
  _$DialogueTurnCopyWithImpl(this._self, this._then);

  final DialogueTurn _self;
  final $Res Function(DialogueTurn) _then;

  /// Create a copy of DialogueTurn
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? speakerId = null,
    Object? text = freezed,
    Object? interactionId = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      speakerId: null == speakerId
          ? _self.speakerId
          : speakerId // ignore: cast_nullable_to_non_nullable
              as String,
      text: freezed == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
      interactionId: freezed == interactionId
          ? _self.interactionId
          : interactionId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [DialogueTurn].
extension DialogueTurnPatterns on DialogueTurn {
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
    TResult Function(_DialogueTurn value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DialogueTurn() when $default != null:
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
    TResult Function(_DialogueTurn value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueTurn():
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
    TResult? Function(_DialogueTurn value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueTurn() when $default != null:
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
            String id, String speakerId, String? text, String? interactionId)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DialogueTurn() when $default != null:
        return $default(
            _that.id, _that.speakerId, _that.text, _that.interactionId);
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
            String id, String speakerId, String? text, String? interactionId)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueTurn():
        return $default(
            _that.id, _that.speakerId, _that.text, _that.interactionId);
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
            String id, String speakerId, String? text, String? interactionId)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueTurn() when $default != null:
        return $default(
            _that.id, _that.speakerId, _that.text, _that.interactionId);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _DialogueTurn implements DialogueTurn {
  const _DialogueTurn(
      {required this.id,
      required this.speakerId,
      this.text,
      this.interactionId});
  factory _DialogueTurn.fromJson(Map<String, dynamic> json) =>
      _$DialogueTurnFromJson(json);

  @override
  final String id;
  @override
  final String speakerId;
  @override
  final String? text;
  @override
  final String? interactionId;

  /// Create a copy of DialogueTurn
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DialogueTurnCopyWith<_DialogueTurn> get copyWith =>
      __$DialogueTurnCopyWithImpl<_DialogueTurn>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$DialogueTurnToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DialogueTurn &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.speakerId, speakerId) ||
                other.speakerId == speakerId) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.interactionId, interactionId) ||
                other.interactionId == interactionId));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, speakerId, text, interactionId);

  @override
  String toString() {
    return 'DialogueTurn(id: $id, speakerId: $speakerId, text: $text, interactionId: $interactionId)';
  }
}

/// @nodoc
abstract mixin class _$DialogueTurnCopyWith<$Res>
    implements $DialogueTurnCopyWith<$Res> {
  factory _$DialogueTurnCopyWith(
          _DialogueTurn value, $Res Function(_DialogueTurn) _then) =
      __$DialogueTurnCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String speakerId, String? text, String? interactionId});
}

/// @nodoc
class __$DialogueTurnCopyWithImpl<$Res>
    implements _$DialogueTurnCopyWith<$Res> {
  __$DialogueTurnCopyWithImpl(this._self, this._then);

  final _DialogueTurn _self;
  final $Res Function(_DialogueTurn) _then;

  /// Create a copy of DialogueTurn
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? speakerId = null,
    Object? text = freezed,
    Object? interactionId = freezed,
  }) {
    return _then(_DialogueTurn(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      speakerId: null == speakerId
          ? _self.speakerId
          : speakerId // ignore: cast_nullable_to_non_nullable
              as String,
      text: freezed == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
      interactionId: freezed == interactionId
          ? _self.interactionId
          : interactionId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$DialogueScene {
  String get id;
  String get title;
  List<DialogueCharacter> get characters;
  List<DialogueTurn> get turns;

  /// Create a copy of DialogueScene
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $DialogueSceneCopyWith<DialogueScene> get copyWith =>
      _$DialogueSceneCopyWithImpl<DialogueScene>(
          this as DialogueScene, _$identity);

  /// Serializes this DialogueScene to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is DialogueScene &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality()
                .equals(other.characters, characters) &&
            const DeepCollectionEquality().equals(other.turns, turns));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      const DeepCollectionEquality().hash(characters),
      const DeepCollectionEquality().hash(turns));

  @override
  String toString() {
    return 'DialogueScene(id: $id, title: $title, characters: $characters, turns: $turns)';
  }
}

/// @nodoc
abstract mixin class $DialogueSceneCopyWith<$Res> {
  factory $DialogueSceneCopyWith(
          DialogueScene value, $Res Function(DialogueScene) _then) =
      _$DialogueSceneCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String title,
      List<DialogueCharacter> characters,
      List<DialogueTurn> turns});
}

/// @nodoc
class _$DialogueSceneCopyWithImpl<$Res>
    implements $DialogueSceneCopyWith<$Res> {
  _$DialogueSceneCopyWithImpl(this._self, this._then);

  final DialogueScene _self;
  final $Res Function(DialogueScene) _then;

  /// Create a copy of DialogueScene
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? characters = null,
    Object? turns = null,
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
      characters: null == characters
          ? _self.characters
          : characters // ignore: cast_nullable_to_non_nullable
              as List<DialogueCharacter>,
      turns: null == turns
          ? _self.turns
          : turns // ignore: cast_nullable_to_non_nullable
              as List<DialogueTurn>,
    ));
  }
}

/// Adds pattern-matching-related methods to [DialogueScene].
extension DialogueScenePatterns on DialogueScene {
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
    TResult Function(_DialogueScene value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DialogueScene() when $default != null:
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
    TResult Function(_DialogueScene value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueScene():
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
    TResult? Function(_DialogueScene value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueScene() when $default != null:
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
    TResult Function(String id, String title,
            List<DialogueCharacter> characters, List<DialogueTurn> turns)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _DialogueScene() when $default != null:
        return $default(_that.id, _that.title, _that.characters, _that.turns);
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
    TResult Function(String id, String title,
            List<DialogueCharacter> characters, List<DialogueTurn> turns)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueScene():
        return $default(_that.id, _that.title, _that.characters, _that.turns);
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
    TResult? Function(String id, String title,
            List<DialogueCharacter> characters, List<DialogueTurn> turns)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _DialogueScene() when $default != null:
        return $default(_that.id, _that.title, _that.characters, _that.turns);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _DialogueScene implements DialogueScene {
  const _DialogueScene(
      {required this.id,
      this.title = '',
      final List<DialogueCharacter> characters = const <DialogueCharacter>[],
      final List<DialogueTurn> turns = const <DialogueTurn>[]})
      : _characters = characters,
        _turns = turns;
  factory _DialogueScene.fromJson(Map<String, dynamic> json) =>
      _$DialogueSceneFromJson(json);

  @override
  final String id;
  @override
  @JsonKey()
  final String title;
  final List<DialogueCharacter> _characters;
  @override
  @JsonKey()
  List<DialogueCharacter> get characters {
    if (_characters is EqualUnmodifiableListView) return _characters;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_characters);
  }

  final List<DialogueTurn> _turns;
  @override
  @JsonKey()
  List<DialogueTurn> get turns {
    if (_turns is EqualUnmodifiableListView) return _turns;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_turns);
  }

  /// Create a copy of DialogueScene
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$DialogueSceneCopyWith<_DialogueScene> get copyWith =>
      __$DialogueSceneCopyWithImpl<_DialogueScene>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$DialogueSceneToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _DialogueScene &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality()
                .equals(other._characters, _characters) &&
            const DeepCollectionEquality().equals(other._turns, _turns));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      const DeepCollectionEquality().hash(_characters),
      const DeepCollectionEquality().hash(_turns));

  @override
  String toString() {
    return 'DialogueScene(id: $id, title: $title, characters: $characters, turns: $turns)';
  }
}

/// @nodoc
abstract mixin class _$DialogueSceneCopyWith<$Res>
    implements $DialogueSceneCopyWith<$Res> {
  factory _$DialogueSceneCopyWith(
          _DialogueScene value, $Res Function(_DialogueScene) _then) =
      __$DialogueSceneCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      List<DialogueCharacter> characters,
      List<DialogueTurn> turns});
}

/// @nodoc
class __$DialogueSceneCopyWithImpl<$Res>
    implements _$DialogueSceneCopyWith<$Res> {
  __$DialogueSceneCopyWithImpl(this._self, this._then);

  final _DialogueScene _self;
  final $Res Function(_DialogueScene) _then;

  /// Create a copy of DialogueScene
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? characters = null,
    Object? turns = null,
  }) {
    return _then(_DialogueScene(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      characters: null == characters
          ? _self._characters
          : characters // ignore: cast_nullable_to_non_nullable
              as List<DialogueCharacter>,
      turns: null == turns
          ? _self._turns
          : turns // ignore: cast_nullable_to_non_nullable
              as List<DialogueTurn>,
    ));
  }
}

// dart format on
