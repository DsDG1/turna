// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/courses/components/section_visuals.dart';

void main() {
  group('SectionVisuals.iconFor', () {
    test('maps each known section id to a distinct icon', () {
      const ids = [
        'section1',
        'section2',
        'section3',
        'section4',
        'section5',
        'section6',
        'section7',
        'section8',
      ];

      final icons = ids.map(SectionVisuals.iconFor).toList();

      for (final icon in icons) {
        expect(icon, isNot(TurnaIconId.book));
      }
      expect(icons.toSet(), hasLength(ids.length));
    });

    test('returns the book fallback for unknown ids', () {
      expect(SectionVisuals.iconFor('section99'), TurnaIconId.book);
      expect(SectionVisuals.iconFor(''), TurnaIconId.book);
    });

    test('uses the expected thematic icons for section1–3', () {
      expect(SectionVisuals.iconFor('section1'), TurnaIconId.sunrise);
      expect(SectionVisuals.iconFor('section2'), TurnaIconId.leaf);
      expect(SectionVisuals.iconFor('section3'), TurnaIconId.sun);
    });
  });

  group('SectionVisuals.colorsFor', () {
    test('returns non-default colors for known section ids', () {
      final known = SectionVisuals.colorsFor('section1');
      final fallback = SectionVisuals.colorsFor('unknown');

      expect(known.background, isNot(fallback.background));
      expect(known.foreground, isNot(fallback.foreground));
    });

    test('known sections do not all share the same foreground', () {
      final foregrounds = {
        for (var i = 1; i <= 8; i++)
          SectionVisuals.colorsFor('section$i').foreground,
      };
      // At least several distinct tints across the 8 sections.
      expect(foregrounds.length, greaterThanOrEqualTo(4));
    });
  });
}
