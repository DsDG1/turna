// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'lesson.dart';

part 'unit.freezed.dart';
part 'unit.g.dart';

/// Mid-level curriculum grouping inside a section (e.g. "Greetings").
@freezed
abstract class Unit with _$Unit {
  const factory Unit({
    required String id,
    required String name,
    @Default('') String description,
    @Default(<String>[]) List<String> prerequisiteUnitIds,
    required List<Lesson> lessons,
  }) = _Unit;

  factory Unit.fromJson(Map<String, dynamic> json) => _$UnitFromJson(json);
}