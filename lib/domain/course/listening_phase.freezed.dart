// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'listening_phase.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ListeningPhase _$ListeningPhaseFromJson(Map<String, dynamic> json) {
  return _ListeningPhase.fromJson(json);
}

/// @nodoc
mixin _$ListeningPhase {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  /// Which part of the listening lesson this phase represents.
  ListeningPhaseType get type => throw _privateConstructorUsedError;

  /// Audio asset to play for this phase.
  String? get audioAsset => throw _privateConstructorUsedError;

  /// Optional transcript shown after the audio has played.
  String get transcript => throw _privateConstructorUsedError;

  /// Interactions for this phase. Word-pairing and dialogue phases use these;
  /// summary phases leave it empty.
  List<Interaction> get items => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ListeningPhaseCopyWith<ListeningPhase> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ListeningPhaseCopyWith<$Res> {
  factory $ListeningPhaseCopyWith(
          ListeningPhase value, $Res Function(ListeningPhase) then) =
      _$ListeningPhaseCopyWithImpl<$Res, ListeningPhase>;
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
class _$ListeningPhaseCopyWithImpl<$Res, $Val extends ListeningPhase>
    implements $ListeningPhaseCopyWith<$Res> {
  _$ListeningPhaseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

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
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as ListeningPhaseType,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: null == transcript
          ? _value.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ListeningPhaseImplCopyWith<$Res>
    implements $ListeningPhaseCopyWith<$Res> {
  factory _$$ListeningPhaseImplCopyWith(_$ListeningPhaseImpl value,
          $Res Function(_$ListeningPhaseImpl) then) =
      __$$ListeningPhaseImplCopyWithImpl<$Res>;
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
class __$$ListeningPhaseImplCopyWithImpl<$Res>
    extends _$ListeningPhaseCopyWithImpl<$Res, _$ListeningPhaseImpl>
    implements _$$ListeningPhaseImplCopyWith<$Res> {
  __$$ListeningPhaseImplCopyWithImpl(
      _$ListeningPhaseImpl _value, $Res Function(_$ListeningPhaseImpl) _then)
      : super(_value, _then);

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
    return _then(_$ListeningPhaseImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as ListeningPhaseType,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      transcript: null == transcript
          ? _value.transcript
          : transcript // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ListeningPhaseImpl implements _ListeningPhase {
  const _$ListeningPhaseImpl(
      {required this.id,
      required this.name,
      this.type = ListeningPhaseType.dialogue,
      this.audioAsset,
      this.transcript = '',
      final List<Interaction> items = const <Interaction>[]})
      : _items = items;

  factory _$ListeningPhaseImpl.fromJson(Map<String, dynamic> json) =>
      _$$ListeningPhaseImplFromJson(json);

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

  @override
  String toString() {
    return 'ListeningPhase(id: $id, name: $name, type: $type, audioAsset: $audioAsset, transcript: $transcript, items: $items)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ListeningPhaseImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.audioAsset, audioAsset) ||
                other.audioAsset == audioAsset) &&
            (identical(other.transcript, transcript) ||
                other.transcript == transcript) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, type, audioAsset,
      transcript, const DeepCollectionEquality().hash(_items));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ListeningPhaseImplCopyWith<_$ListeningPhaseImpl> get copyWith =>
      __$$ListeningPhaseImplCopyWithImpl<_$ListeningPhaseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ListeningPhaseImplToJson(
      this,
    );
  }
}

abstract class _ListeningPhase implements ListeningPhase {
  const factory _ListeningPhase(
      {required final String id,
      required final String name,
      final ListeningPhaseType type,
      final String? audioAsset,
      final String transcript,
      final List<Interaction> items}) = _$ListeningPhaseImpl;

  factory _ListeningPhase.fromJson(Map<String, dynamic> json) =
      _$ListeningPhaseImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override

  /// Which part of the listening lesson this phase represents.
  ListeningPhaseType get type;
  @override

  /// Audio asset to play for this phase.
  String? get audioAsset;
  @override

  /// Optional transcript shown after the audio has played.
  String get transcript;
  @override

  /// Interactions for this phase. Word-pairing and dialogue phases use these;
  /// summary phases leave it empty.
  List<Interaction> get items;
  @override
  @JsonKey(ignore: true)
  _$$ListeningPhaseImplCopyWith<_$ListeningPhaseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
