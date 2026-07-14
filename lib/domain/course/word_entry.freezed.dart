// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'word_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WordEntry _$WordEntryFromJson(Map<String, dynamic> json) {
  return _WordEntry.fromJson(json);
}

/// @nodoc
mixin _$WordEntry {
  String get id => throw _privateConstructorUsedError;
  String get term => throw _privateConstructorUsedError;
  String get translation => throw _privateConstructorUsedError;
  String? get pronunciation => throw _privateConstructorUsedError;
  String? get audioAsset => throw _privateConstructorUsedError;
  List<String> get tags => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WordEntryCopyWith<WordEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WordEntryCopyWith<$Res> {
  factory $WordEntryCopyWith(WordEntry value, $Res Function(WordEntry) then) =
      _$WordEntryCopyWithImpl<$Res, WordEntry>;
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
class _$WordEntryCopyWithImpl<$Res, $Val extends WordEntry>
    implements $WordEntryCopyWith<$Res> {
  _$WordEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

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
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      term: null == term
          ? _value.term
          : term // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _value.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      pronunciation: freezed == pronunciation
          ? _value.pronunciation
          : pronunciation // ignore: cast_nullable_to_non_nullable
              as String?,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: null == tags
          ? _value.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WordEntryImplCopyWith<$Res>
    implements $WordEntryCopyWith<$Res> {
  factory _$$WordEntryImplCopyWith(
          _$WordEntryImpl value, $Res Function(_$WordEntryImpl) then) =
      __$$WordEntryImplCopyWithImpl<$Res>;
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
class __$$WordEntryImplCopyWithImpl<$Res>
    extends _$WordEntryCopyWithImpl<$Res, _$WordEntryImpl>
    implements _$$WordEntryImplCopyWith<$Res> {
  __$$WordEntryImplCopyWithImpl(
      _$WordEntryImpl _value, $Res Function(_$WordEntryImpl) _then)
      : super(_value, _then);

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
    return _then(_$WordEntryImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      term: null == term
          ? _value.term
          : term // ignore: cast_nullable_to_non_nullable
              as String,
      translation: null == translation
          ? _value.translation
          : translation // ignore: cast_nullable_to_non_nullable
              as String,
      pronunciation: freezed == pronunciation
          ? _value.pronunciation
          : pronunciation // ignore: cast_nullable_to_non_nullable
              as String?,
      audioAsset: freezed == audioAsset
          ? _value.audioAsset
          : audioAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      tags: null == tags
          ? _value._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WordEntryImpl implements _WordEntry {
  const _$WordEntryImpl(
      {required this.id,
      required this.term,
      required this.translation,
      this.pronunciation,
      this.audioAsset,
      final List<String> tags = const <String>[]})
      : _tags = tags;

  factory _$WordEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$WordEntryImplFromJson(json);

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

  @override
  String toString() {
    return 'WordEntry(id: $id, term: $term, translation: $translation, pronunciation: $pronunciation, audioAsset: $audioAsset, tags: $tags)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WordEntryImpl &&
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

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, term, translation,
      pronunciation, audioAsset, const DeepCollectionEquality().hash(_tags));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WordEntryImplCopyWith<_$WordEntryImpl> get copyWith =>
      __$$WordEntryImplCopyWithImpl<_$WordEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WordEntryImplToJson(
      this,
    );
  }
}

abstract class _WordEntry implements WordEntry {
  const factory _WordEntry(
      {required final String id,
      required final String term,
      required final String translation,
      final String? pronunciation,
      final String? audioAsset,
      final List<String> tags}) = _$WordEntryImpl;

  factory _WordEntry.fromJson(Map<String, dynamic> json) =
      _$WordEntryImpl.fromJson;

  @override
  String get id;
  @override
  String get term;
  @override
  String get translation;
  @override
  String? get pronunciation;
  @override
  String? get audioAsset;
  @override
  List<String> get tags;
  @override
  @JsonKey(ignore: true)
  _$$WordEntryImplCopyWith<_$WordEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
