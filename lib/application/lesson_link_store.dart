// Flutter imports:
import 'dart:convert';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/service/locator.dart';

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
  /// or [removeIds].
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
      // Prefer empty over silent wipe; observable in release via logger.
      logger.w('LessonLinkStore decode failed: $e');
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

  String? lessonNameFor(String id) => linkFor(id)?.lessonName;

  /// Drop the given word ids (e.g. resources a pack re-import removed —
  /// see `CourseRepository.deleteOrphanedLearnerRows`). Serializes writes.
  Future<void> removeIds(Set<String> wordIds) {
    return _enqueue(() async {
      final current = readAll();
      final removed = wordIds.where(current.containsKey);
      if (removed.isEmpty) return;
      for (final id in removed) {
        current.remove(id);
      }
      await _persist(current);
    });
  }

  /// O(1) lookup without copying the full map. Returns `null` if unknown.
  LessonWordLink? linkFor(String id) {
    if (_cache == null) readAll(); // populate cache
    return _cache![id];
  }

  /// Whether [id] already has a recorded first-seen link — reads the cache
  /// directly without copying the whole map (unlike [lessonNameFor], which
  /// allocates a full copy per lookup). Use this for pre-flight "is this new?"
  /// checks before [upsertFirstSeen].
  bool containsId(String id) {
    if (_cache == null) readAll(); // populate cache
    return _cache!.containsKey(id);
  }

  Map<String, LessonWordLink> filtered(LinkType type) {
    final all = readAll();
    return Map.fromEntries(all.entries.where((e) => e.value.type == type));
  }

  /// Invalidate first-seen link metadata after an external restore.
  Future<void> reloadFromPrefs() => _enqueue(() async {
        _cache = null;
        readAll();
      });

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
      logger.w('LessonLinkStore write failed: $e');
    });
    return _writeChain;
  }
}
