// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/routing/course_ready_guard.dart';
import 'package:varnamala/routing/routing.gr.dart';

@lazySingleton
@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(this._courseReadyGuard);

  final CourseReadyGuard _courseReadyGuard;

  @override
  RouteType get defaultRouteType => const RouteType.cupertino();

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: SplashRoute.page, initial: true),
        // CourseReadyGuard: redirect to splash when shells are not loaded yet.
        // Splash itself has no guard. Phase 22 can attach the same guard to
        // dictionary / deep-link routes.
        AutoRoute(page: HomeRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: NewLessonRoute.page),
        AutoRoute(page: SectionPickerRoute.page),
        AutoRoute(page: AiWishChatRoute.page),
        AutoRoute(page: AiHintChatRoute.page),
        AutoRoute(page: TextbookImportRoute.page),
        AutoRoute(page: VowelAndConsonantLearningRoute.page),
        AutoRoute(page: MatchWordsRoute.page),
        AutoRoute(page: DailyChallengeRoute.page),
        AutoRoute(page: SrsReviewRoute.page),
        AutoRoute(page: GrammarReviewRoute.page),
        AutoRoute(page: MistakeListRoute.page),
        AutoRoute(page: MistakePracticeRoute.page),
        AutoRoute(
            page: MistakeReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: DictionaryRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: WeakWordsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiImportRoute.page),
        AutoRoute(page: AnkiReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: AnkiReviewSessionRoute.page, guards: [_courseReadyGuard]),
      ];
}
