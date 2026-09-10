import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/policy/presentation_policy.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';

void main() {
  const policy = OfficialAnkiPresentationPolicy();

  test('violated choice card that is a genuine short pair degrades to flip',
      () {
    final values = _values(target: '判断题：对吗？', native: '对', violated: true);
    final kind = policy.selectOfficialKind(
      values: values,
      mapping: null,
      typeAnswerEnabled: false,
    );
    expect(kind, OfficialAnkiProjectionKind.flip);
  });

  test('violated choice card with a long stem keeps fidelity', () {
    final values = _values(target: '长' * 80, native: '答案', violated: true);
    final kind = policy.selectOfficialKind(
      values: values,
      mapping: null,
      typeAnswerEnabled: false,
    );
    expect(kind, OfficialAnkiProjectionKind.canonicalLink);
  });

  test('violated choice card with an explanation-sized back keeps fidelity',
      () {
    final values = _values(
      target: '问题？',
      native: '这是一段很长的解析说明文字' * 5,
      violated: true,
    );
    final kind = policy.selectOfficialKind(
      values: values,
      mapping: null,
      typeAnswerEnabled: false,
    );
    expect(kind, OfficialAnkiProjectionKind.canonicalLink);
  });

  test('non-violated choice with resolved options stays multipleChoice', () {
    final values = _values(
      options: const ['甲', '乙'],
      correctIndices: const [0],
    );
    final kind = policy.selectOfficialKind(
      values: values,
      mapping: null,
      typeAnswerEnabled: false,
    );
    expect(kind, OfficialAnkiProjectionKind.multipleChoice);
  });
}

OfficialAnkiRoleValues _values({
  String target = '问题',
  String native = '答案',
  bool violated = false,
  List<String> options = const [],
  List<int>? correctIndices,
}) {
  return OfficialAnkiRoleValues(
    target: target,
    native: native,
    pronunciation: '',
    example: '',
    audio: null,
    image: null,
    options: options,
    truncatedRequired: false,
    archetype: CardArchetype.choice,
    archetypeConfidence: 0.9,
    archetypeViolated: violated,
    hasExplicitOptions: options.isNotEmpty,
    correctIndices: correctIndices,
  );
}
