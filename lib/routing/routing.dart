// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/routing/course_ready_guard.dart';
import 'package:turna/routing/diagnostics_release_guard.dart';
import 'package:turna/routing/routing.gr.dart';

@lazySingleton
@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter(this._courseReadyGuard);

  final CourseReadyGuard _courseReadyGuard;
  static const DiagnosticsReleaseGuard _diagnosticsGuard =
      DiagnosticsReleaseGuard();

  // Platform-adaptive policy (contract in docs/project-guide.md §3, enforced by
  // test/routing/routing_policy_contract_test.dart): Android/Fuchsia/desktop ->
  // Material routes with
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
        AutoRoute(page: AiHintChatRoute.page),
        AutoRoute(page: AiTutorChatRoute.page),
        AutoRoute(page: AiDiagnosisRoute.page),
        AutoRoute(page: AiSavedListRoute.page),
        AutoRoute(page: TextbookImportRoute.page),
        AutoRoute(page: AiHubRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: AiPracticeLibraryRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AiPracticeRunRoute.page, guards: [_courseReadyGuard]),
        // Detail is pushed from the practice library and the hub preview
        // card menus; it must stay registered or those entries dead-end.
        AutoRoute(page: AiPracticeDetailRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AiFeatureGuideRoute.page),
        AutoRoute(page: DailyChallengeRoute.page),
        AutoRoute(page: SrsReviewRoute.page),
        AutoRoute(page: ReviewProgressRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: LearningInsightsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: ReviewSourceDetailRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AchievementsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: GrammarReviewRoute.page),
        AutoRoute(page: MistakeListRoute.page),
        AutoRoute(page: MistakeDashboardRoute.page),
        AutoRoute(page: MistakeDetailRoute.page),
        AutoRoute(page: MistakePracticeRoute.page),
        AutoRoute(page: MistakeReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: DictionaryRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: WeakWordsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiImportRoute.page),
        // Memory-card domain home (ADR 0066): due overview, deck list,
        // import entry — reachable independently of the language courses.
        AutoRoute(page: MemoryCardHubRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiDeckStatsRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiCardBrowserRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: AnkiReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: AnkiReviewSessionRoute.page, guards: [_courseReadyGuard]),
        // Unified review stays registered as a deep-link fallback only:
        // the production path embeds UnifiedReviewPage as a widget from
        // SrsReviewPage (no router push in lib/).
        AutoRoute(page: UnifiedReviewRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(
            page: CourseManagementRoute.page, guards: [_courseReadyGuard]),
        AutoRoute(page: OfficialAnkiRepairCenterRoute.page),
        AutoRoute(
            page: OfficialAnkiReviewerRoute.page, guards: [_diagnosticsGuard]),
        // Settings family: static content pages, no course guard
        // (mirrors SystemHealthRoute).
        AutoRoute(page: SystemHealthRoute.page),
        AutoRoute(page: StorageDiagnosticsRoute.page),
        AutoRoute(page: AboutTurnaRoute.page),
        AutoRoute(page: PrivacyDetailsRoute.page),
        AutoRoute(page: TransparencyLogRoute.page),
        AutoRoute(page: AiApiConfigRoute.page),
        AutoRoute(page: RemoteBackupRoute.page),
        AutoRoute(page: AvatarRingsRoute.page),
        // Formal Settings category routes (Plan §12.2): every category is a
        // real, routable page — no in-page pseudo navigation.
        AutoRoute(page: AccountSettingsRoute.page),
        AutoRoute(page: LearningSettingsRoute.page),
        AutoRoute(page: AppearanceSoundSettingsRoute.page),
        AutoRoute(page: AccessibilitySettingsRoute.page),
        AutoRoute(page: DataBackupSettingsRoute.page),
        AutoRoute(page: AdvancedSettingsRoute.page),
        AutoRoute(page: LegacyCompatibilityRoute.page),
        AutoRoute(page: AboutSettingsRoute.page),
      ];
}
