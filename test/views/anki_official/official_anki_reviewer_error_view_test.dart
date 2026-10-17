import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';

/// The error view is also the visibility switch for its two buttons: pass a
/// callback and the button renders, pass null and it does not. The OHOS
/// reviewer leans on that contract to give the learner an exit, so it is worth
/// pinning here rather than only in the stage.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('retry and back both render and fire their own callback',
      (tester) async {
    var retries = 0;
    var backs = 0;
    await tester.pumpWidget(host(OfficialAnkiReviewerErrorView(
      messageKey: 'official_anki.render_failed',
      onRetry: () => retries++,
      onBack: () => backs++,
    )));

    expect(find.text(AppStrings.officialAnkiRetryCurrentSide), findsOneWidget);
    expect(find.text(AppStrings.commonBack), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonBack));
    await tester.pump();
    expect(backs, 1);
    expect(retries, 0, reason: 'back must not double as retry');
  });

  testWidgets('back alone renders without a retry entry', (tester) async {
    // The OHOS fail-closed branch is exactly this shape: a user setting turned
    // scripts off, so re-running the same boot cannot help — only an exit.
    await tester.pumpWidget(host(const OfficialAnkiReviewerErrorView(
      messageKey: 'official_anki.renderer_flag_fail_closed',
      onBack: _noop,
    )));

    expect(find.text(AppStrings.commonBack), findsOneWidget);
    expect(find.text(AppStrings.officialAnkiRetryCurrentSide), findsNothing);
  });

  testWidgets('no callbacks means no button row at all', (tester) async {
    await tester.pumpWidget(host(const OfficialAnkiReviewerErrorView(
      messageKey: 'official_anki.render_failed',
    )));

    expect(find.text(AppStrings.commonBack), findsNothing);
    expect(find.text(AppStrings.officialAnkiRetryCurrentSide), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('fromUi filters retry on a fatal surface but keeps back',
      (tester) async {
    var retries = 0;
    var backs = 0;
    await tester.pumpWidget(host(OfficialAnkiReviewerErrorView.fromUi(
      ui: const OfficialAnkiReviewerUi.fatalError(code: 'engine_error'),
      onRetry: () => retries++,
      onBack: () => backs++,
    )));

    expect(find.text(AppStrings.officialAnkiRetryCurrentSide), findsNothing,
        reason: 'fatalError.offersRetryCurrentSide is false');
    expect(find.text(AppStrings.commonBack), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonBack));
    await tester.pump();
    expect(backs, 1);
    expect(retries, 0);
  });

  testWidgets('fromUi keeps retry on a recoverable surface', (tester) async {
    await tester.pumpWidget(host(OfficialAnkiReviewerErrorView.fromUi(
      ui: const OfficialAnkiReviewerUi.recoverableError(
        code: 'render_timeout',
        side: 'question',
        generation: 1,
      ),
      onRetry: _noop,
      onBack: _noop,
    )));

    expect(find.text(AppStrings.officialAnkiRetryCurrentSide), findsOneWidget);
    expect(find.text(AppStrings.commonBack), findsOneWidget);
  });
}

void _noop() {}
