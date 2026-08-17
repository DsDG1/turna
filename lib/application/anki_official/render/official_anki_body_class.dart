/// Atomic card body classes. Night classes come from the UI only.
class OfficialAnkiBodyClass {
  OfficialAnkiBodyClass._();

  static final _cardN = RegExp(r'^card\d+$');
  static const _desktop = {'isWin', 'isMac', 'isLin'};

  static Set<String> apply({
    required Iterable<String> current,
    required int templateOrdinal,
    required bool night,
  }) {
    final next = <String>{};
    for (final cls in current) {
      if (cls.isEmpty || cls == 'card' || _cardN.hasMatch(cls)) continue;
      if (cls == 'nightMode' || cls == 'night_mode') continue;
      if (_desktop.contains(cls)) continue;
      next.add(cls);
    }
    next.add('card');
    next.add('card${templateOrdinal + 1}');
    if (night) {
      next.add('nightMode');
      next.add('night_mode');
    }
    return next;
  }

  static String fromNative({required int templateOrdinal}) =>
      'card card${templateOrdinal + 1}';
}
