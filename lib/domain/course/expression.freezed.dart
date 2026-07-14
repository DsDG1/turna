// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'expression.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Expression _$ExpressionFromJson(Map<String, dynamic> json) {
  return _Expression.fromJson(json);
}

/// @nodoc
mixin _$Expression {
  String get id => throw _privateConstructorUsedError;

  /// The expression in the target language, e.g. "habari za asubuhi".
  String get term => throw _privateConstructorUsedError;

  /// English translation, e.g. "good morning".
  String get translation => throw _privateConstructorUsedError;

  /// Optional pronunciation hint.
  String? get pronunciation => throw _privateConstructorUsedError;

  /// Optional pre-recorded audio asset; falls back to TTS if absent.
  String? get audioAsset => throw _privateConstructorUsedError;

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  List<String> get tags => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ExpressionCopyWith<Expression> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExpressionCopyWith<$Res> {
  factory $ExpressionCopyWith(
          Expression value, $Res Function(Expression) then) =
      _$ExpressionCopyWithImpl<$Res, Expression>;
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
class _$ExpressionCopyWithImpl<$Res, $Val extends Expression>
    implements $ExpressionCopyWith<$Res> {
  _$ExpressionCopyWithImpl(this._value, this._then);

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
abstract class _$$ExpressionImplCopyWith<$Res>
    implements $ExpressionCopyWith<$Res> {
  factory _$$ExpressionImplCopyWith(
          _$ExpressionImpl value, $Res Function(_$ExpressionImpl) then) =
      __$$ExpressionImplCopyWithImpl<$Res>;
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
class __$$ExpressionImplCopyWithImpl<$Res>
    extends _$ExpressionCopyWithImpl<$Res, _$ExpressionImpl>
    implements _$$ExpressionImplCopyWith<$Res> {
  __$$ExpressionImplCopyWithImpl(
      _$ExpressionImpl _value, $Res Function(_$ExpressionImpl) _then)
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
    return _then(_$ExpressionImpl(
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
class _$ExpressionImpl implements _Expression {
  const _$ExpressionImpl(
      {required this.id,
      required this.term,
      required this.translation,
      this.pronunciation,
      this.audioAsset,
      final List<String> tags = const <String>[]})
      : _tags = tags;

  factory _$ExpressionImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExpressionImplFromJson(json);

  @override
  final String id;

  /// The expression in the target language, e.g. "habari za asubuhi".
  @override
  final String term;

  /// English translation, e.g. "good morning".
  @override
  final String translation;

  /// Optional pronunciation hint.
  @override
  final String? pronunciation;

  /// Optional pre-recorded audio asset; falls back to TTS if absent.
  @override
  final String? audioAsset;

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  final List<String> _tags;

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  @override
  String toString() {
    return 'Expression(id: $id, term: $term, translation: $translation, pronunciation: $pronunciation, audioAsset: $audioAsset, tags: $tags)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExpressionImpl &&
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
  _$$ExpressionImplCopyWith<_$ExpressionImpl> get copyWith =>
      __$$ExpressionImplCopyWithImpl<_$ExpressionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExpressionImplToJson(
      this,
    );
  }
}

abstract class _Expression implements Expression {
  const factory _Expression(
      {required final String id,
      required final String term,
      required final String translation,
      final String? pronunciation,
      final String? audioAsset,
      final List<String> tags}) = _$ExpressionImpl;

  factory _Expression.fromJson(Map<String, dynamic> json) =
      _$ExpressionImpl.fromJson;

  @override
  String get id;
  @override

  /// The expression in the target language, e.g. "habari za asubuhi".
  String get term;
  @override

  /// English translation, e.g. "good morning".
  String get translation;
  @override

  /// Optional pronunciation hint.
  String? get pronunciation;
  @override

  /// Optional pre-recorded audio asset; falls back to TTS if absent.
  String? get audioAsset;
  @override

  /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
  List<String> get tags;
  @override
  @JsonKey(ignore: true)
  _$$ExpressionImplCopyWith<_$ExpressionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
