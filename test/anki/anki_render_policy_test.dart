// Tests for AnkiRenderPolicy (deep-adaptation plan §3.2.3). Pure-function
// checks that each routing rule fires correctly and the "禁止伪 MCQ" 铁律
// (looks-like-options but can't parse -> fidelity) holds.

// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_render_policy.dart';

void main() {
  const policy = AnkiRenderPolicy();

  // Default "Basic" notetype (Front/Back, no templates, no cloze).
  const basicNt = AnkiNotetype(
    id: 1,
    name: 'Basic',
    fieldNames: ['Front', 'Back'],
  );
  const basicMapping = NotetypeMapping(
    type: NotetypeMappingType.ankiCard,
    frontFieldIndex: 0,
    backFieldIndex: 1,
  );

  AnkiCardData card(int id) => AnkiCardData(id: id, nid: id, did: 1, ord: 0);

  test('JS in template -> fidelity', () {
    const nt = AnkiNotetype(
      id: 2,
      name: 'JS',
      fieldNames: ['Front', 'Back'],
      templates: [
        AnkiTemplate(
            name: 'C', qfmt: '{{Front}}', afmt: '<script>x()</script>'),
      ],
    );
    final note = AnkiNote(id: 1, mid: 2, fields: const ['q', 'a']);
    expect(
      policy.decide(
          notetype: nt, note: note, card: card(1), mapping: basicMapping),
      AnkiRenderMode.fidelity,
    );
  });

  test('type-answer filter -> fidelity', () {
    const nt = AnkiNotetype(
      id: 5,
      name: 'Type answer',
      fieldNames: ['Front', 'Back'],
      templates: [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '{{Front}}<br>{{type:Back}}',
          afmt: '{{Front}}<hr id="answer">{{Back}}',
        ),
      ],
    );
    final note = AnkiNote(id: 1, mid: 5, fields: const ['q', 'a']);
    expect(
      policy.decide(
          notetype: nt, note: note, card: card(1), mapping: basicMapping),
      AnkiRenderMode.fidelity,
    );
  });

  test('cloze notetype -> structured', () {
    const nt =
        AnkiNotetype(id: 3, name: 'Cloze', isCloze: true, fieldNames: ['Text']);
    const mapping = NotetypeMapping(
        type: NotetypeMappingType.cloze, frontFieldIndex: 0, backFieldIndex: 0);
    final note = AnkiNote(id: 1, mid: 3, fields: const ['The {{c1::sun}}']);
    expect(
      policy.decide(notetype: nt, note: note, card: card(1), mapping: mapping),
      AnkiRenderMode.structured,
    );
  });

  test('short Front/Back vocab -> structured', () {
    final note = AnkiNote(id: 1, mid: 1, fields: const ['merhaba', 'hello']);
    expect(
      policy.decide(
          notetype: basicNt, note: note, card: card(1), mapping: basicMapping),
      AnkiRenderMode.structured,
    );
  });

  test('long answer (not short) -> fidelity', () {
    final note = AnkiNote(
      id: 1,
      mid: 1,
      fields: const [
        'Explain photosynthesis',
        'Photosynthesis is the process by which green plants and certain '
            'other organisms transform light energy into chemical energy.',
      ],
    );
    expect(
      policy.decide(
          notetype: basicNt, note: note, card: card(1), mapping: basicMapping),
      AnkiRenderMode.fidelity,
    );
  });

  test('embedded A/B/C options that parse -> structured', () {
    final note = AnkiNote(
      id: 1,
      mid: 1,
      fields: const [
        'Capital of France?\nA. London\nB. Paris\nC. Berlin',
        'B',
      ],
    );
    expect(
      policy.decide(
          notetype: basicNt, note: note, card: card(1), mapping: basicMapping),
      AnkiRenderMode.structured,
    );
  });

  test('looks-like-options but unparseable -> fidelity (铁律)', () {
    // A./B./C. markers but the options are malformed (can't split) - must NOT
    // fall back to a deck-distractor MCQ.
    final note = AnkiNote(
      id: 1,
      mid: 1,
      fields: const [
        // B./C./D. markers but no A. -> looksLikeEmbeddedOptions true, but
        // extractEmbeddedOptions returns null (inline parse requires an A start).
        'B. foo C. bar D. baz',
        'B',
      ],
    );
    // Short back would normally be structured (rule 7), but rule 6 fires first
    // (looks-like-options, can't parse) -> fidelity (铁律).
    final mode = policy.decide(
        notetype: basicNt, note: note, card: card(1), mapping: basicMapping);
    expect(mode, AnkiRenderMode.fidelity);
  });

  test('image in front -> fidelity (preserve media)', () {
    final note = AnkiNote(
      id: 1,
      mid: 1,
      fields: const ['<img src="flag.png">', 'Turkey'],
    );
    expect(
      policy.decide(
          notetype: basicNt, note: note, card: card(1), mapping: basicMapping),
      AnkiRenderMode.fidelity,
    );
  });

  test('complex HTML in the selected template -> fidelity', () {
    const nt = AnkiNotetype(
      id: 6,
      name: 'Template media',
      fieldNames: ['Front', 'Back'],
      templates: [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '<table><tr><td>{{Front}}</td></tr></table>',
          afmt: '{{FrontSide}}<hr id="answer">{{Back}}',
        ),
      ],
    );
    final note = AnkiNote(id: 1, mid: 6, fields: const ['question', 'answer']);
    expect(
      policy.decide(
        notetype: nt,
        note: note,
        card: card(1),
        mapping: basicMapping,
      ),
      AnkiRenderMode.fidelity,
    );
  });

  test('explicit multipleChoice mapping -> structured', () {
    const nt = AnkiNotetype(
      id: 4,
      name: 'MCQ',
      fieldNames: ['Question', 'Option A', 'Option B', 'Answer'],
    );
    const mapping = NotetypeMapping(
      type: NotetypeMappingType.multipleChoice,
      frontFieldIndex: 0,
      backFieldIndex: 3,
    );
    final note = AnkiNote(id: 1, mid: 4, fields: const ['q', 'a', 'b', 'A']);
    expect(
      policy.decide(notetype: nt, note: note, card: card(1), mapping: mapping),
      AnkiRenderMode.structured,
    );
  });
}
