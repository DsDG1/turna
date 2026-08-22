// Shared helpers for interaction renderer widget tests.

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

class RendererTestHarness {
  final List<(bool correct, String? userAnswer)> submissions = [];

  Widget build(InteractionRenderer renderer, Interaction interaction) {
    return MaterialApp(
      home: Scaffold(
        body: renderer.build(
          interaction,
          InteractionState.idle,
          (correct, {userAnswerText, reviewQuality}) {
            submissions.add((correct, userAnswerText));
          },
        ),
      ),
    );
  }

  /// Same as [build], but hosts the renderer under a real AutoRoute root
  /// stack for renderers that navigate via `context.router` (e.g. official
  /// canonical links). The official reviewer route is registered so pushes
  /// resolve exactly like in the app shell.
  Widget buildRouted(InteractionRenderer renderer, Interaction interaction) {
    return MaterialApp.router(
      routerConfig: _HarnessRouter(
        host: Scaffold(
          body: renderer.build(
            interaction,
            InteractionState.idle,
            (correct, {userAnswerText, reviewQuality}) {
              submissions.add((correct, userAnswerText));
            },
          ),
        ),
      ).config(),
    );
  }
}

class _HarnessRouter extends RootStackRouter {
  _HarnessRouter({required this.host});

  final Widget host;

  @override
  RouteType get defaultRouteType => const RouteType.adaptive();

  @override
  List<AutoRoute> get routes => [
        AutoRoute(
          page: PageInfo('_HarnessHost', builder: (_) => host),
          initial: true,
        ),
        AutoRoute(page: OfficialAnkiReviewerRoute.page),
      ];
}

Future<void> tapOption(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(InkWell, label));
  await tester.pumpAndSettle();
}

/// LessonCheckButton is a gradient InkWell CTA (not ElevatedButton).
Future<void> tapCheck(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(InkWell, '核对'));
  await tester.pumpAndSettle();
}

Future<void> tapContinue(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(InkWell, '继续'));
  await tester.pumpAndSettle();
}

/// Whether the lesson CHECK CTA is enabled (InkWell.onTap non-null).
bool isCheckEnabled(WidgetTester tester) {
  final ink = tester.widget<InkWell>(find.widgetWithText(InkWell, '核对'));
  return ink.onTap != null;
}

Future<void> enterText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}
