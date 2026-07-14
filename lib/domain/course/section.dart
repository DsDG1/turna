// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'unit.dart';

part 'section.freezed.dart';
part 'section.g.dart';

/// Top-level curriculum grouping (e.g. "A1 Basics").
@freezed
class Section with _$Section {
  const factory Section({
    required String id,
    required String name,
    @Default('') String description,
    String? level,
    @Default(<String>[]) List<String> prerequisiteSectionIds,
    required List<Unit> units,
  }) = _Section;

  factory Section.fromJson(Map<String, dynamic> json) =>
      _$SectionFromJson(json);
}