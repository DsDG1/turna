// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'word_entry.freezed.dart';
part 'word_entry.g.dart';

/// Global vocabulary pool entry. Decoupled from lessons — [ShowWord]
/// interactions reference words by id.
@freezed
abstract class WordEntry with _$WordEntry {
  const factory WordEntry({
    required String id,
    required String term,
    required String translation,
    String? pronunciation,
    String? audioAsset,

    /// Closed POS tag (`noun`, `verb`, …), or null when the course omits it.
    String? pos,
    @Default(<String>[]) List<String> tags,
  }) = _WordEntry;

  factory WordEntry.fromJson(Map<String, dynamic> json) =>
      _$WordEntryFromJson(json);
}
