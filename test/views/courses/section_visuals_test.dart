// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
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
        expect(icon, isNot(Icons.menu_book_rounded));
      }
      expect(icons.toSet(), hasLength(ids.length));
    });

    test('returns the book fallback for unknown ids', () {
      expect(
        SectionVisuals.iconFor('section99'),
        Icons.menu_book_rounded,
      );
      expect(
        SectionVisuals.iconFor(''),
        Icons.menu_book_rounded,
      );
    });

    test('uses the expected thematic icons for section1–3', () {
      expect(SectionVisuals.iconFor('section1'), Icons.waving_hand_rounded);
      expect(SectionVisuals.iconFor('section2'), Icons.pets_rounded);
      expect(SectionVisuals.iconFor('section3'), Icons.mood_rounded);
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
