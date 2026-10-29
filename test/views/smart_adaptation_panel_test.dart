import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_input_builder.dart';
import 'package:turna/application/anki_import/adaptation/ai_card_adaptation_service.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/domain/anki/adaptation/presentation_decision.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/components/smart_adaptation_panel.dart';

/// P6b UI gate: the smart-adaptation entry never pretends to have a plan, and
/// every failure state is visible with a way to continue (plan §13.1).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const schema = OfficialAnkiProjectionSchema(
    notetypeId: 7,
    name: 'Basic',
    kind: 'normal',
    fieldNames: ['Expression', 'Meaning'],
    templateNames: ['Card 1'],
    schemaFingerprint: 'fp',
  );

  CardAdaptationPlan plan() => const CardAdaptationPlan(
        planId: 'plan-1',
        revision: 2,
        scope: AdaptationScope(
          sourceId: 'src-1',
          notetypeId: 7,
          templateOrdinal: 0,
        ),
        bindings: <String, int>{'prompt': 0, 'answer': 1},
        front: <AdaptationBlock>[
          AdaptationBlock(kind: 'text', fieldIndex: 0),
        ],
        back: <AdaptationBlock>[
          AdaptationBlock(kind: 'text', fieldIndex: 1),
        ],
      );

  Future<void> pump(
    WidgetTester tester, {
    required bool aiConfigured,
    required Future<CardAdaptationResult> Function(OfficialAnkiProjectionSchema)
        onGenerate,
    Future<bool> Function(OfficialAnkiProjectionSchema, CardAdaptationPlan)?
        onApply,
    void Function(OfficialAnkiProjectionSchema)? onRestore,
    bool staged = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmartAdaptationPanel(
            schemas: const [schema],
            aiConfigured: aiConfigured,
            hasPlan: (_) => staged,
            onGenerate: onGenerate,
            onApply: onApply ??
                (_, __) async {
                  return true;
                },
            onRestore: onRestore ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without AI configuration the generate action is disabled',
      (tester) async {
    await pump(
      tester,
      aiConfigured: false,
      onGenerate: (_) async => const CardAdaptationUnavailable('ai_unavailable'),
    );

    expect(find.text(AppStrings.ankiAdaptationNotConfigured), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('adaptation-generate-7')),
    );
    expect(button.onPressed, isNull, reason: '未配置时不能点');
  });

  testWidgets('an accepted plan shows its revision and applies', (tester) async {
    CardAdaptationPlan? applied;
    await pump(
      tester,
      aiConfigured: true,
      onGenerate: (_) async => CardAdaptationAccepted(
        plan: plan(),
        input: AdaptationInputBuilder.build(schema: schema),
        repaired: false,
      ),
      onApply: (_, next) async {
        applied = next;
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('adaptation-generate-7')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.ankiAdaptationPlanLabel('plan-1', 2)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adaptation-apply-7')));
    await tester.pumpAndSettle();
    expect(applied?.planId, 'plan-1');
  });

  testWidgets('an unavailable model says so and offers no apply', (tester) async {
    await pump(
      tester,
      aiConfigured: true,
      onGenerate: (_) async => const CardAdaptationUnavailable('transport'),
    );

    await tester.tap(find.byKey(const ValueKey('adaptation-generate-7')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.ankiAdaptationTransport), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptation-apply-7')), findsNothing);
  });

  testWidgets('a truncated reply is reported as truncated, not generic',
      (tester) async {
    await pump(
      tester,
      aiConfigured: true,
      onGenerate: (_) async => const CardAdaptationRejected(code: 'truncated'),
    );

    await tester.tap(find.byKey(const ValueKey('adaptation-generate-7')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.ankiAdaptationTruncated), findsOneWidget);
  });

  testWidgets('a locally rejected plan reports the validation failure',
      (tester) async {
    await pump(
      tester,
      aiConfigured: true,
      onGenerate: (_) async => const CardAdaptationRejected(
        code: 'invalid_plan',
        issues: [AdaptationIssue.answerOnFront],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('adaptation-generate-7')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.ankiAdaptationRejected), findsOneWidget);
    expect(
      find.text('答案会出现在题面'),
      findsOneWidget,
      reason: '拒绝要说明具体原因，而不是一句笼统的失败',
    );
    expect(find.byKey(const ValueKey('adaptation-apply-7')), findsNothing);
  });

  test('every presentation reason has a human label', () {
    for (final reason in PresentationReason.values) {
      final label = AppStrings.presentationReasonLabel(reason);
      expect(label, isNotEmpty, reason: reason.name);
      expect(
        label.toLowerCase().contains('anki'),
        isFalse,
        reason: '${reason.name}: 面向用户的文案不出现专名',
      );
    }
  });

  testWidgets('a staged plan can be restored to the original card',
      (tester) async {
    var restored = 0;
    await pump(
      tester,
      aiConfigured: true,
      staged: true,
      onGenerate: (_) async => const CardAdaptationUnavailable('ai_unavailable'),
      onRestore: (_) => restored++,
    );

    expect(find.text(AppStrings.ankiAdaptationStaged), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adaptation-restore-7')));
    await tester.pumpAndSettle();

    expect(restored, 1);
  });
}


