// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'srs_word.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SrsWord _$SrsWordFromJson(Map<String, dynamic> json) {
  return _SrsWord.fromJson(json);
}

/// @nodoc
mixin _$SrsWord {
  String get wordId => throw _privateConstructorUsedError;
  DateTime get dueAt => throw _privateConstructorUsedError;
  int get intervalDays => throw _privateConstructorUsedError;
  double get ease => throw _privateConstructorUsedError;
  int get reps => throw _privateConstructorUsedError;
  int get lapses => throw _privateConstructorUsedError;
  bool get isLeech => throw _privateConstructorUsedError;
  SrsItemType get type => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $SrsWordCopyWith<SrsWord> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SrsWordCopyWith<$Res> {
  factory $SrsWordCopyWith(SrsWord value, $Res Function(SrsWord) then) =
      _$SrsWordCopyWithImpl<$Res, SrsWord>;
  @useResult
  $Res call(
      {String wordId,
      DateTime dueAt,
      int intervalDays,
      double ease,
      int reps,
      int lapses,
      bool isLeech,
      SrsItemType type});
}

/// @nodoc
class _$SrsWordCopyWithImpl<$Res, $Val extends SrsWord>
    implements $SrsWordCopyWith<$Res> {
  _$SrsWordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? wordId = null,
    Object? dueAt = null,
    Object? intervalDays = null,
    Object? ease = null,
    Object? reps = null,
    Object? lapses = null,
    Object? isLeech = null,
    Object? type = null,
  }) {
    return _then(_value.copyWith(
      wordId: null == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      dueAt: null == dueAt
          ? _value.dueAt
          : dueAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      intervalDays: null == intervalDays
          ? _value.intervalDays
          : intervalDays // ignore: cast_nullable_to_non_nullable
              as int,
      ease: null == ease
          ? _value.ease
          : ease // ignore: cast_nullable_to_non_nullable
              as double,
      reps: null == reps
          ? _value.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      lapses: null == lapses
          ? _value.lapses
          : lapses // ignore: cast_nullable_to_non_nullable
              as int,
      isLeech: null == isLeech
          ? _value.isLeech
          : isLeech // ignore: cast_nullable_to_non_nullable
              as bool,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SrsItemType,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SrsWordImplCopyWith<$Res> implements $SrsWordCopyWith<$Res> {
  factory _$$SrsWordImplCopyWith(
          _$SrsWordImpl value, $Res Function(_$SrsWordImpl) then) =
      __$$SrsWordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String wordId,
      DateTime dueAt,
      int intervalDays,
      double ease,
      int reps,
      int lapses,
      bool isLeech,
      SrsItemType type});
}

/// @nodoc
class __$$SrsWordImplCopyWithImpl<$Res>
    extends _$SrsWordCopyWithImpl<$Res, _$SrsWordImpl>
    implements _$$SrsWordImplCopyWith<$Res> {
  __$$SrsWordImplCopyWithImpl(
      _$SrsWordImpl _value, $Res Function(_$SrsWordImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? wordId = null,
    Object? dueAt = null,
    Object? intervalDays = null,
    Object? ease = null,
    Object? reps = null,
    Object? lapses = null,
    Object? isLeech = null,
    Object? type = null,
  }) {
    return _then(_$SrsWordImpl(
      wordId: null == wordId
          ? _value.wordId
          : wordId // ignore: cast_nullable_to_non_nullable
              as String,
      dueAt: null == dueAt
          ? _value.dueAt
          : dueAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      intervalDays: null == intervalDays
          ? _value.intervalDays
          : intervalDays // ignore: cast_nullable_to_non_nullable
              as int,
      ease: null == ease
          ? _value.ease
          : ease // ignore: cast_nullable_to_non_nullable
              as double,
      reps: null == reps
          ? _value.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int,
      lapses: null == lapses
          ? _value.lapses
          : lapses // ignore: cast_nullable_to_non_nullable
              as int,
      isLeech: null == isLeech
          ? _value.isLeech
          : isLeech // ignore: cast_nullable_to_non_nullable
              as bool,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SrsItemType,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SrsWordImpl implements _SrsWord {
  const _$SrsWordImpl(
      {required this.wordId,
      required this.dueAt,
      this.intervalDays = 1,
      this.ease = 2.5,
      this.reps = 0,
      this.lapses = 0,
      this.isLeech = false,
      this.type = SrsItemType.word});

  factory _$SrsWordImpl.fromJson(Map<String, dynamic> json) =>
      _$$SrsWordImplFromJson(json);

  @override
  final String wordId;
  @override
  final DateTime dueAt;
  @override
  @JsonKey()
  final int intervalDays;
  @override
  @JsonKey()
  final double ease;
  @override
  @JsonKey()
  final int reps;
  @override
  @JsonKey()
  final int lapses;
  @override
  @JsonKey()
  final bool isLeech;
  @override
  @JsonKey()
  final SrsItemType type;

  @override
  String toString() {
    return 'SrsWord(wordId: $wordId, dueAt: $dueAt, intervalDays: $intervalDays, ease: $ease, reps: $reps, lapses: $lapses, isLeech: $isLeech, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SrsWordImpl &&
            (identical(other.wordId, wordId) || other.wordId == wordId) &&
            (identical(other.dueAt, dueAt) || other.dueAt == dueAt) &&
            (identical(other.intervalDays, intervalDays) ||
                other.intervalDays == intervalDays) &&
            (identical(other.ease, ease) || other.ease == ease) &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.lapses, lapses) || other.lapses == lapses) &&
            (identical(other.isLeech, isLeech) || other.isLeech == isLeech) &&
            (identical(other.type, type) || other.type == type));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, wordId, dueAt, intervalDays,
      ease, reps, lapses, isLeech, type);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SrsWordImplCopyWith<_$SrsWordImpl> get copyWith =>
      __$$SrsWordImplCopyWithImpl<_$SrsWordImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SrsWordImplToJson(
      this,
    );
  }
}

abstract class _SrsWord implements SrsWord {
  const factory _SrsWord(
      {required final String wordId,
      required final DateTime dueAt,
      final int intervalDays,
      final double ease,
      final int reps,
      final int lapses,
      final bool isLeech,
      final SrsItemType type}) = _$SrsWordImpl;

  factory _SrsWord.fromJson(Map<String, dynamic> json) = _$SrsWordImpl.fromJson;

  @override
  String get wordId;
  @override
  DateTime get dueAt;
  @override
  int get intervalDays;
  @override
  double get ease;
  @override
  int get reps;
  @override
  int get lapses;
  @override
  bool get isLeech;
  @override
  SrsItemType get type;
  @override
  @JsonKey(ignore: true)
  _$$SrsWordImplCopyWith<_$SrsWordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
