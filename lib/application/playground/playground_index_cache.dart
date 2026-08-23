import 'dart:collection';

import 'package:turna/application/playground/playground_index.dart';

class PlaygroundIndexCache {
  PlaygroundIndexCache({this.maxEntries = 4});

  static final PlaygroundIndexCache instance = PlaygroundIndexCache();

  final int maxEntries;
  final LinkedHashMap<String, PlaygroundIndex> _entries = LinkedHashMap();

  int get entryCount => _entries.length;

  PlaygroundIndex? get(PlaygroundSourceRevision revision) {
    final cached = _entries.remove(revision.value);
    if (cached != null) _entries[revision.value] = cached;
    return cached;
  }

  void put(PlaygroundSourceRevision revision, PlaygroundIndex index) {
    _entries.remove(revision.value);
    _entries[revision.value] = index;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
