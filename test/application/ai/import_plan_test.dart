import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/textbook/import_plan.dart';
import 'package:turna/application/ai/textbook/knowledge_merger.dart';

void main() {
  Map<String, dynamic> section(String id) => {
        'id': id,
        'name': id,
        'words': [
          {'id': 'w1'}
        ],
        'expressions': [],
        'grammarPoints': [],
        'units': [
          {
            'id': '$id-u1',
            'lessons': [
              {'id': '$id-u1-l1'}
            ],
          }
        ],
      };

  test('no collision → all append', () {
    final plans = planBulkImport(
      sections: [section('tb-a'), section('tb-b')],
      existingSectionIds: {},
      strategy: ImportStrategy.merge,
    );
    expect(plans.every((p) => p.action == ImportAction.append), isTrue);
    expect(plans.every((p) => !p.exists), isTrue);
  });

  test('merge on collision', () {
    final plans = planBulkImport(
      sections: [section('tb-a')],
      existingSectionIds: {'tb-a'},
      strategy: ImportStrategy.merge,
    );
    expect(plans.single.action, ImportAction.merge);
    expect(plans.single.exists, isTrue);
    expect(plans.single.targetId, 'tb-a');
  });

  test('skip on collision', () {
    final plans = planBulkImport(
      sections: [section('tb-a')],
      existingSectionIds: {'tb-a'},
      strategy: ImportStrategy.skipExisting,
    );
    expect(plans.single.action, ImportAction.skip);
    expect(plans.single.willWrite, isFalse);
  });

  test('forceReplace on collision', () {
    final plans = planBulkImport(
      sections: [section('tb-a')],
      existingSectionIds: {'tb-a'},
      strategy: ImportStrategy.forceReplace,
    );
    expect(plans.single.action, ImportAction.replace);
  });

  test('appendAsNew allocates unique target id', () {
    final plans = planBulkImport(
      sections: [section('tb-a'), section('tb-a')],
      existingSectionIds: {'tb-a'},
      strategy: ImportStrategy.appendAsNew,
    );
    expect(plans[0].action, ImportAction.appendNew);
    expect(plans[0].targetId, 'tb-a-2');
    expect(plans[1].targetId, 'tb-a-3');
    expect(plans[0].targetId, isNot(plans[1].targetId));
  });

  test('applyPlanToSection rewrites nested ids for appendNew', () {
    final plan = SectionImportPlan(
      index: 0,
      sourceId: 'tb-a',
      targetId: 'tb-a-2',
      exists: true,
      action: ImportAction.appendNew,
    );
    final out = applyPlanToSection(section('tb-a'), plan)!;
    expect(out['id'], 'tb-a-2');
    final unit = (out['units'] as List).first as Map;
    expect(unit['id'], 'tb-a-2-u1');
    final lesson = (unit['lessons'] as List).first as Map;
    expect(lesson['id'], 'tb-a-2-u1-l1');
  });

  test('applyPlanToSection returns null for skip', () {
    final plan = const SectionImportPlan(
      index: 0,
      sourceId: 'tb-a',
      targetId: 'tb-a',
      exists: true,
      action: ImportAction.skip,
    );
    expect(applyPlanToSection(section('tb-a'), plan), isNull);
  });
}
