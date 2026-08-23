// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/routing/course_ready_guard.dart';
import 'package:turna/routing/routing.gr.dart';

@lazySingleton
@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(this._courseReadyGuard);

  final CourseReadyGuard _courseReadyGuard;

  // Platform-adaptive policy (docs/platform-adaptive-page-transition-
  // unification-plan.md D1): Android/Fuchsia/desktop -> Material routes with
  // predictive back, iOS/macOS -> Cupertino routes with edge-swipe pop, web ->
  // no transition. Do not force a single platform style globally and do not
  // add custom transitions/durations here.
  @override
  RouteType get defaultRouteType => const RouteType.adaptive(
        enablePredictiveBackGesture: true,
      );

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
        AutoRoute(page: AiTutorChatRoute.page),
        AutoRoute(page: AiDiagnosisRoute.page),
        AutoRoute(page: AiSavedListRoute.page),
        AutoRoute(page: TextbookImportRoute.page),
        AutoRoute(page: AiHubRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AiFeatureGuideRoute.page),
        AutoRoute(page: VowelAndConsonantLearningRoute.page),
        AutoRoute(page: MatchWordsRoute.page),
        // 语言课程 Playground：CourseReadyGuard 之上再由页面自身做资格
        // 二次检查（Anki scope 拦截返回），见 language_playground_page。
        AutoRoute(
            page: LanguagePlaygroundRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: DailyChallengeRoute.page),
        AutoRoute(page: SrsReviewRoute.page),
        AutoRoute(page: ReviewProgressRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: LearningInsightsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AchievementsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: GrammarReviewRoute.page),
        AutoRoute(page: MistakeListRoute.page),
        AutoRoute(page: MistakePracticeRoute.page),
        AutoRoute(page: MistakeReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: DictionaryRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: WeakWordsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiImportRoute.page),
        AutoRoute(
            page: AnkiDeckStatsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: AnkiCardBrowserRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiReviewSessionRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: UnifiedReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: CourseManagementRoute.page, guards: [_courseReadyGuard]),
        // Official-Anki surfaces: flag-gated diagnostics, no course guard
        // (mirrors AnkiImportRoute semantics).
        AutoRoute(page: OfficialAnkiInternalRoute.page),
        AutoRoute(page: OfficialAnkiMappingRoute.page),
        AutoRoute(page: OfficialAnkiReviewerRoute.page),
        AutoRoute(page: OfficialAnkiReviewRoute.page),
        AutoRoute(page: OfficialAnkiMigrationPreviewRoute.page),
        AutoRoute(page: OfficialAnkiSourceManagementRoute.page),
        // Settings family: static content pages, no course guard
        // (mirrors SystemHealthRoute).
        AutoRoute(page: SystemHealthRoute.page),
        AutoRoute(page: StorageDiagnosticsRoute.page),
        AutoRoute(page: AboutTurnaRoute.page),
        AutoRoute(page: PrivacyDetailsRoute.page),
        AutoRoute(page: ChangelogRoute.page),
        AutoRoute(page: TransparencyLogRoute.page),
        AutoRoute(page: AiApiConfigRoute.page),
        AutoRoute(page: RemoteBackupRoute.page),
        AutoRoute(page: AvatarRingsRoute.page),
      ];
}
