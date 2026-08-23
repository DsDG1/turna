// Tests for [AnkiOrganizationResolver]: unit/lesson key extraction from
// notetype fields and tags, priority, and the collection preview aggregate.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';

void main() {
  const resolver = AnkiOrganizationResolver();

  AnkiNotetype nt(List<String> fields) => AnkiNotetype(
        id: 1,
        name: 'Basic',
        fieldNames: fields,
      );

  AnkiNote note(List<String> fields, {String tags = ''}) => AnkiNote(
        id: 1,
        mid: 1,
        fields: fields,
        tags: tags,
      );

  group('AnkiOrganizationResolver.resolve', () {
    test('notetype unit/lesson fields populate the keys', () {
      final notetype = nt(['Unit', 'Lesson', 'Front', 'Back']);
      final n = note(['2', 'Greetings', 'Q', 'A']);
      final org = resolver.resolve(n, notetype);
      expect(org.unitKey, '2');
      expect(org.lessonKey, 'Greetings');
    });

    test('unit::/lesson:: tags populate the keys', () {
      final notetype = nt(['Front', 'Back']);
      final n = note(['Q', 'A'], tags: 'unit::3 lesson::hello vocab');
      final org = resolver.resolve(n, notetype);
      expect(org.unitKey, '3');
      expect(org.lessonKey, 'hello');
    });

    test('single-colon tag prefixes also work (unit:3, chapter::5)', () {
      final notetype = nt(['Front', 'Back']);
      final n = note(['Q', 'A'], tags: 'unit:3');
      expect(resolver.resolve(n, notetype).unitKey, '3');

      final n2 = note(['Q', 'A'], tags: 'chapter::5');
      expect(resolver.resolve(n2, notetype).unitKey, '5');
    });

    test('no metadata yields null keys', () {
      final notetype = nt(['Front', 'Back']);
      final n = note(['Q', 'A']);
      final org = resolver.resolve(n, notetype);
      expect(org.unitKey, isNull);
      expect(org.lessonKey, isNull);
      expect(org.hasAny, isFalse);
    });

    test('field value takes priority over a tag', () {
      final notetype = nt(['Unit', 'Front', 'Back']);
      final n = note(['2', 'Q', 'A'], tags: 'unit::9');
      expect(resolver.resolve(n, notetype).unitKey, '2');
    });

    test('html in a field value is stripped', () {
      final notetype = nt(['Unit', 'Front', 'Back']);
      final n = note(['<b>2</b>', 'Q', 'A']);
      expect(resolver.resolve(n, notetype).unitKey, '2');
    });

    test('empty field value falls through to tags', () {
      final notetype = nt(['Unit', 'Front', 'Back']);
      final n = note(['', 'Q', 'A'], tags: 'unit::7');
      expect(resolver.resolve(n, notetype).unitKey, '7');
    });

    test('chinese field names (单元/课) are recognized', () {
      final notetype = nt(['单元', '课', '正面', '反面']);
      final n = note(['2', '第一课', '问', '答']);
      final org = resolver.resolve(n, notetype);
      expect(org.unitKey, '2');
      expect(org.lessonKey, '第一课');
    });
  });

  group('AnkiOrganizationResolver.resolve (Section Beta)', () {
    test('default path keeps folding section/chapter fields into units', () {
      final notetype = nt(['Chapter', 'Unit', 'Front', 'Back']);
      final n = note(['Animals', '2', 'Q', 'A']);
      final org = resolver.resolve(n, notetype);
      expect(org.unitKey, 'Animals',
          reason: 'historical behavior: chapter fields act as unit metadata');
      expect(org.sectionKey, isNull);
    });

    test('beta lifts a section field out of the unit key with evidence', () {
      final notetype = nt(['Chapter', 'Unit', 'Front', 'Back']);
      final n = note(['Animals', '2', 'Q', 'A']);
      final org = resolver.resolve(n, notetype, sectionBeta: true);
      expect(org.sectionKey, 'Animals');
      expect(org.sectionEvidence, AnkiSectionEvidence.explicitField);
      expect(org.sectionConfidence, greaterThanOrEqualTo(0.9));
      expect(org.unitKey, '2',
          reason: 'the section field no longer doubles as the unit');
    });

    test('beta lifts section::/chapter:: tags', () {
      final notetype = nt(['Unit', 'Front', 'Back']);
      final n = note(['2', 'Q', 'A'], tags: 'chapter::3 vocab');
      final org = resolver.resolve(n, notetype, sectionBeta: true);
      expect(org.sectionKey, '3');
      expect(org.sectionEvidence, AnkiSectionEvidence.explicitTag);
      expect(org.unitKey, '2');
    });

    test('unit-name prefixes derive a section key', () {
      expect(
        AnkiOrganizationResolver.sectionKeyFromUnitName('Chapter 1: Basics'),
        ('chapter 1', 'Chapter 1'),
      );
      expect(
        AnkiOrganizationResolver.sectionKeyFromUnitName('ch.2 Verbs'),
        ('ch. 2', 'ch.2'),
      );
      expect(
        AnkiOrganizationResolver.sectionKeyFromUnitName('Unit 3'),
        isNull,
        reason: 'plain "Unit N" stays a unit — the plan groups units under '
            'chapters, not units under units',
      );
      expect(AnkiOrganizationResolver.sectionKeyFromUnitName('Greetings'),
          isNull);
    });
  });

  group('AnkiOrganizationResolver.preview (Section Beta)', () {
    final notetypes = {
      1: nt(['Chapter', 'Unit', 'Lesson', 'Front', 'Back']),
      2: nt(['Unit', 'Front', 'Back']),
    };

    test('beta reports semantic sections with an evidence breakdown', () {
      final notes = [
        AnkiNote(id: 1, mid: 1, fields: ['Animals', '1', 'Dogs', 'q', 'a']),
        AnkiNote(id: 2, mid: 1, fields: ['Animals', '2', 'Cats', 'q', 'a']),
        AnkiNote(id: 3, mid: 2, fields: ['Chapter 9', 'q', 'a']),
      ];
      final p = resolver.preview(
        notes: notes,
        notetypes: notetypes,
        sectionBeta: true,
      );
      expect(p.sectionNames, containsAll(['Animals', 'Chapter 9']));
      expect(
        p.sectionEvidenceCounts[AnkiSectionEvidence.explicitField],
        greaterThanOrEqualTo(1),
      );
      expect(
        p.sectionEvidenceCounts[AnkiSectionEvidence.unitPrefix],
        greaterThanOrEqualTo(1),
      );
      expect(p.lowConfidenceSectionHint, isNull,
          reason: 'at least one section has explicit evidence');
      expect(p.sectionCountLabel, contains('字段'));
    });

    test('prefix-only sections surface the low-confidence hint', () {
      final notes = [
        AnkiNote(id: 3, mid: 2, fields: ['Chapter 9', 'q', 'a']),
      ];
      final p = resolver.preview(
        notes: notes,
        notetypes: notetypes,
        sectionBeta: true,
      );
      expect(p.sectionNames, ['Chapter 9']);
      expect(p.lowConfidenceSectionHint, isNotNull);
    });

    test('non-beta preview reports no sections', () {
      final notes = [
        AnkiNote(id: 1, mid: 1, fields: ['Animals', '1', 'Dogs', 'q', 'a']),
      ];
      final p = resolver.preview(notes: notes, notetypes: notetypes);
      expect(p.sectionNames, isEmpty);
      expect(p.hasAny, isTrue, reason: 'units still resolve');
    });
  });

  group('AnkiOrganizationResolver.preview', () {
    test('aggregates distinct units/lessons and resolved count', () {
      final notetypes = {
        1: nt(['Unit', 'Lesson', 'Front', 'Back']),
        2: nt(['Front', 'Back']),
      };
      final notes = [
        AnkiNote(id: 1, mid: 1, fields: ['1', 'A', 'q', 'a']),
        AnkiNote(id: 2, mid: 1, fields: ['1', 'B', 'q', 'a']),
        AnkiNote(id: 3, mid: 2, fields: ['q', 'a'], tags: 'lesson::C'),
        AnkiNote(id: 4, mid: 2, fields: ['q', 'a']),
      ];
      final p = resolver.preview(notes: notes, notetypes: notetypes);
      expect(p.resolvedCardCount, 3); // notes 1,2,3
      expect(p.unitCount, 1); // only "1"
      expect(p.lessonCount, 3); // A, B, C
      expect(p.unitNames, ['1']);
      expect(p.lessonNames, ['A', 'B', 'C']);
      expect(p.hasAny, isTrue);
    });

    test('empty collection has no organization', () {
      final p = resolver.preview(notes: [], notetypes: {});
      expect(p.hasAny, isFalse);
      expect(p.resolvedCardCount, 0);
    });
  });
}
