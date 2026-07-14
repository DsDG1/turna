// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'grammar_point.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

GrammarPoint _$GrammarPointFromJson(Map<String, dynamic> json) {
  return _GrammarPoint.fromJson(json);
}

/// @nodoc
mixin _$GrammarPoint {
  String get id => throw _privateConstructorUsedError;

  /// Short title, e.g. "Present tense -a verb conjugation".
  String get title => throw _privateConstructorUsedError;

  /// Full explanation shown in lesson and review.
  String get explanation => throw _privateConstructorUsedError;

  /// IDs of expressions that exemplify this grammar point.
  List<String> get exampleExpressionIds => throw _privateConstructorUsedError;

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  List<String> get exampleSentenceIds => throw _privateConstructorUsedError;

  /// Short practice drills for the grammar-review screen.
  @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
  List<Interaction> get practiceItems => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $GrammarPointCopyWith<GrammarPoint> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GrammarPointCopyWith<$Res> {
  factory $GrammarPointCopyWith(
          GrammarPoint value, $Res Function(GrammarPoint) then) =
      _$GrammarPointCopyWithImpl<$Res, GrammarPoint>;
  @useResult
  $Res call(
      {String id,
      String title,
      String explanation,
      List<String> exampleExpressionIds,
      List<String> exampleSentenceIds,
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      List<Interaction> practiceItems});
}

/// @nodoc
class _$GrammarPointCopyWithImpl<$Res, $Val extends GrammarPoint>
    implements $GrammarPointCopyWith<$Res> {
  _$GrammarPointCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? explanation = null,
    Object? exampleExpressionIds = null,
    Object? exampleSentenceIds = null,
    Object? practiceItems = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      explanation: null == explanation
          ? _value.explanation
          : explanation // ignore: cast_nullable_to_non_nullable
              as String,
      exampleExpressionIds: null == exampleExpressionIds
          ? _value.exampleExpressionIds
          : exampleExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      exampleSentenceIds: null == exampleSentenceIds
          ? _value.exampleSentenceIds
          : exampleSentenceIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      practiceItems: null == practiceItems
          ? _value.practiceItems
          : practiceItems // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$GrammarPointImplCopyWith<$Res>
    implements $GrammarPointCopyWith<$Res> {
  factory _$$GrammarPointImplCopyWith(
          _$GrammarPointImpl value, $Res Function(_$GrammarPointImpl) then) =
      __$$GrammarPointImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      String explanation,
      List<String> exampleExpressionIds,
      List<String> exampleSentenceIds,
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      List<Interaction> practiceItems});
}

/// @nodoc
class __$$GrammarPointImplCopyWithImpl<$Res>
    extends _$GrammarPointCopyWithImpl<$Res, _$GrammarPointImpl>
    implements _$$GrammarPointImplCopyWith<$Res> {
  __$$GrammarPointImplCopyWithImpl(
      _$GrammarPointImpl _value, $Res Function(_$GrammarPointImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? explanation = null,
    Object? exampleExpressionIds = null,
    Object? exampleSentenceIds = null,
    Object? practiceItems = null,
  }) {
    return _then(_$GrammarPointImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      explanation: null == explanation
          ? _value.explanation
          : explanation // ignore: cast_nullable_to_non_nullable
              as String,
      exampleExpressionIds: null == exampleExpressionIds
          ? _value._exampleExpressionIds
          : exampleExpressionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      exampleSentenceIds: null == exampleSentenceIds
          ? _value._exampleSentenceIds
          : exampleSentenceIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      practiceItems: null == practiceItems
          ? _value._practiceItems
          : practiceItems // ignore: cast_nullable_to_non_nullable
              as List<Interaction>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$GrammarPointImpl implements _GrammarPoint {
  const _$GrammarPointImpl(
      {required this.id,
      required this.title,
      this.explanation = '',
      final List<String> exampleExpressionIds = const <String>[],
      final List<String> exampleSentenceIds = const <String>[],
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      final List<Interaction> practiceItems = const <Interaction>[]})
      : _exampleExpressionIds = exampleExpressionIds,
        _exampleSentenceIds = exampleSentenceIds,
        _practiceItems = practiceItems;

  factory _$GrammarPointImpl.fromJson(Map<String, dynamic> json) =>
      _$$GrammarPointImplFromJson(json);

  @override
  final String id;

  /// Short title, e.g. "Present tense -a verb conjugation".
  @override
  final String title;

  /// Full explanation shown in lesson and review.
  @override
  @JsonKey()
  final String explanation;

  /// IDs of expressions that exemplify this grammar point.
  final List<String> _exampleExpressionIds;

  /// IDs of expressions that exemplify this grammar point.
  @override
  @JsonKey()
  List<String> get exampleExpressionIds {
    if (_exampleExpressionIds is EqualUnmodifiableListView)
      return _exampleExpressionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exampleExpressionIds);
  }

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  final List<String> _exampleSentenceIds;

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  @override
  @JsonKey()
  List<String> get exampleSentenceIds {
    if (_exampleSentenceIds is EqualUnmodifiableListView)
      return _exampleSentenceIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_exampleSentenceIds);
  }

  /// Short practice drills for the grammar-review screen.
  final List<Interaction> _practiceItems;

  /// Short practice drills for the grammar-review screen.
  @override
  @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
  List<Interaction> get practiceItems {
    if (_practiceItems is EqualUnmodifiableListView) return _practiceItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_practiceItems);
  }

  @override
  String toString() {
    return 'GrammarPoint(id: $id, title: $title, explanation: $explanation, exampleExpressionIds: $exampleExpressionIds, exampleSentenceIds: $exampleSentenceIds, practiceItems: $practiceItems)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GrammarPointImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.explanation, explanation) ||
                other.explanation == explanation) &&
            const DeepCollectionEquality()
                .equals(other._exampleExpressionIds, _exampleExpressionIds) &&
            const DeepCollectionEquality()
                .equals(other._exampleSentenceIds, _exampleSentenceIds) &&
            const DeepCollectionEquality()
                .equals(other._practiceItems, _practiceItems));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      explanation,
      const DeepCollectionEquality().hash(_exampleExpressionIds),
      const DeepCollectionEquality().hash(_exampleSentenceIds),
      const DeepCollectionEquality().hash(_practiceItems));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$GrammarPointImplCopyWith<_$GrammarPointImpl> get copyWith =>
      __$$GrammarPointImplCopyWithImpl<_$GrammarPointImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GrammarPointImplToJson(
      this,
    );
  }
}

abstract class _GrammarPoint implements GrammarPoint {
  const factory _GrammarPoint(
      {required final String id,
      required final String title,
      final String explanation,
      final List<String> exampleExpressionIds,
      final List<String> exampleSentenceIds,
      @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
      final List<Interaction> practiceItems}) = _$GrammarPointImpl;

  factory _GrammarPoint.fromJson(Map<String, dynamic> json) =
      _$GrammarPointImpl.fromJson;

  @override
  String get id;
  @override

  /// Short title, e.g. "Present tense -a verb conjugation".
  String get title;
  @override

  /// Full explanation shown in lesson and review.
  String get explanation;
  @override

  /// IDs of expressions that exemplify this grammar point.
  List<String> get exampleExpressionIds;
  @override

  /// IDs of example sentences (could be stored as expression ids or separate
  /// sentence ids in the future).
  List<String> get exampleSentenceIds;
  @override

  /// Short practice drills for the grammar-review screen.
  @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
  List<Interaction> get practiceItems;
  @override
  @JsonKey(ignore: true)
  _$$GrammarPointImplCopyWith<_$GrammarPointImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
