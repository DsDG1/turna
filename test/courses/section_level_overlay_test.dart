import 'package:flutter_test/flutter_test.dart';
import 'package:turna/courses/section_level_overlay.dart';
import 'package:turna/domain/course/section.dart';

void main() {
  const bare = Section(id: 'section1', name: 'Basics', units: []);

  test('empty body level falls back to the index shell', () {
    expect(
      sectionLevelForSeed(bodyLevel: null, indexLevel: 'A1'),
      'A1',
    );
    expect(
      sectionLevelForSeed(bodyLevel: '', indexLevel: 'A2'),
      'A2',
    );
    expect(
      sectionLevelForSeed(bodyLevel: 'B1', indexLevel: 'A1'),
      'B1',
    );
  });

  test('index map keeps only non-empty levels', () {
    final levels = sectionLevelsFromIndex({
      'sections': [
        {'id': 'section1', 'level': 'A1'},
        {'id': 'section2', 'level': ''},
        {'id': '', 'level': 'B2'},
        'not-a-map',
      ],
    });
    expect(levels, {'section1': 'A1'});
  });

  test('overlay fills an empty stored level and keeps Anki', () {
    expect(
      overlaySectionLevel(bare, {'section1': 'A1'}).level,
      'A1',
    );
    final anki = bare.copyWith(id: 'anki-1', level: 'Anki');
    expect(
      overlaySectionLevel(anki, {'anki-1': 'A1'}).level,
      'Anki',
    );
    expect(overlaySectionLevel(bare, const {}).level, isNull);
  });
}
