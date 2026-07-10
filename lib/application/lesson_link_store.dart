// Flutter imports:
import 'dart:convert';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/domain/course/lesson_word_link.dart';
import 'package:varnamala/service/locator.dart';

/// Single writer for [LocalStateKeys.lessonWordLinks].
///
/// [SrsProvider] and [GrammarReviewProvider] both need first-seen lesson
/// metadata; previously each re-read/wrote the whole map and could clobber
/// the other. All link mutations go through this store.
@lazySingleton
class LessonLinkStore {
  final AppPrefs appPrefs;

  LessonLinkStore(this.appPrefs);

  Map<String, LessonWordLink>? _cache;
  Future<void> _writeChain = Future.value();

  /// Full map (all [LinkType]s). Mutations must go through [upsertFirstSeen]
  /// or [replaceAll].
  Map<String, LessonWordLink> readAll() {
    if (_cache != null) return Map.of(_cache!);

    final raw = appPrefs.preferences
        .getString(LocalStateKeys.lessonWordLinks, defaultValue: '{}')
        .getValue();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded.map(
        (k, v) =>
            MapEntry(k, LessonWordLink.fromJson(v as Map<String, dynamic>)),
      );
    } catch (e) {
      // Prefer empty over silent wipe without observability.
      // ignore: avoid_print
      print('LessonLinkStore decode failed: $e');
      _cache = <String, LessonWordLink>{};
    }
    return Map.of(_cache!);
  }

  /// Insert first-seen links only (existing keys kept). Serializes writes.
  Future<void> upsertFirstSeen({
    required Iterable<String> ids,
    required String lessonId,
    required String lessonName,
    required LinkType type,
  }) {
    return _enqueue(() async {
      final current = readAll();
      var changed = false;
      for (final id in ids) {
        if (!current.containsKey(id)) {
          current[id] = LessonWordLink(
            wordId: id,
            lessonId: lessonId,
            lessonName: lessonName,
            type: type,
            firstSeenAt: DateTime.now(),
          );
          changed = true;
        }
      }
      if (changed) await _persist(current);
    });
  }

  String? lessonNameFor(String id) => readAll()[id]?.lessonName;

  Map<String, LessonWordLink> filtered(LinkType type) {
    final all = readAll();
    return Map.fromEntries(all.entries.where((e) => e.value.type == type));
  }

  Future<void> _persist(Map<String, LessonWordLink> map) async {
    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k, v.toJson())),
    );
    await appPrefs.preferences
        .setString(LocalStateKeys.lessonWordLinks, encoded);
    _cache = map;
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).catchError((Object e) {
      // ignore: avoid_print
      print('LessonLinkStore write failed: $e');
    });
    return _writeChain;
  }
}
