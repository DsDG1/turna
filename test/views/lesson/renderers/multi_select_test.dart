import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('MultiSelect submits true when all correct options picked',
      (tester) async {
    final renderer = MultiSelectRenderer();
    const interaction = Interaction.multiSelect(
      id: 'ms-1',
      prompt: 'Select the words you heard',
      options: ['apple', 'banana', 'carrot', 'date'],
      correctIndices: [0, 2],
      minSelections: 2,
      maxSelections: 2,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'apple');
    await tapOption(tester, 'carrot');
    await tapCheck(tester);

    expect(harness.submissions, [(true, '0,2')]);
  });

  testWidgets('MultiSelect submits false when a wrong option is picked',
      (tester) async {
    final renderer = MultiSelectRenderer();
    const interaction = Interaction.multiSelect(
      id: 'ms-2',
      prompt: 'Select the words you heard',
      options: ['apple', 'banana', 'carrot', 'date'],
      correctIndices: [0, 2],
      minSelections: 2,
      maxSelections: 2,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'apple');
    await tapOption(tester, 'banana');
    await tapCheck(tester);

    expect(harness.submissions, [(false, '0,1')]);
  });

  testWidgets('MultiSelect disables check until selection count is in range',
      (tester) async {
    final renderer = MultiSelectRenderer();
    const interaction = Interaction.multiSelect(
      id: 'ms-3',
      prompt: 'Select the words you heard',
      options: ['apple', 'banana', 'carrot', 'date'],
      correctIndices: [0, 2],
      minSelections: 2,
      maxSelections: 2,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));

    // No selection yet: check button should be disabled.
    expect(isCheckEnabled(tester), isFalse);

    await tapOption(tester, 'apple');
    expect(isCheckEnabled(tester), isFalse);

    await tapOption(tester, 'carrot');
    expect(isCheckEnabled(tester), isTrue);
  });
}
