import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/formal_review_source_coordinator.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/study_session/anki_review_content.dart';
import 'package:turna/application/study_session/anki_study_session_host.dart';
import 'package:turna/application/study_session/session_settlement_service.dart';
import 'package:turna/application/study_session/study_ledger_adapters.dart';
import 'package:turna/application/study_session/study_product_analytics.dart';
import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:provider/provider.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_official_review_gate.dart';
import 'package:turna/views/anki/anki_webview_sizing.dart';
import 'package:turna/views/review/components/binary_recall_bar.dart';
import 'package:turna/views/review/components/review_progress_header.dart';
import 'package:turna/views/review/components/study_card_surface.dart';
import 'package:turna/views/review/components/unified_review_completion.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';

/// Shared formal-review session for Official-owned Anki cards.
///
/// Every production entry lands here. Official capability failures fail closed
/// and never open a different-semantics page (doc 35 L2: the Legacy assembler
/// + Turna SRS runtime branch is deleted; still-Legacy-owned sources fail
/// closed). Official owners use [FormalReviewLauncher.assembleOfficialBatch] +
/// [OfficialStudyLedger].
@RoutePage()
class AnkiReviewSessionPage extends StatefulWidget {
  const AnkiReviewSessionPage({
    super.key,
    this.sectionId,
    this.officialOwner,
  });

  final String? sectionId;

  /// When set by [FormalReviewLauncher], used instead of inferring owner
  /// from the due repository. `null` falls back to the due snapshot: empty
  /// section = any Official source, else contains.
  final bool? officialOwner;

  /// Test seam that replaces the production Official batch loader.
  /// Production always uses [OfficialFormalReviewProductionLoader] when null.
  static Future<OfficialFormalReviewLoadResult?> Function({
    required String importId,
    required String courseId,
  })? debugOfficialBatchBuilder;

  /// Production loader (overridable in tests that drive the page widget).
  static OfficialFormalReviewProductionLoader productionLoader =
      const OfficialFormalReviewProductionLoader();

  @override
  State<AnkiReviewSessionPage> createState() => _AnkiReviewSessionPageState();
}

class _AnkiReviewSessionPageState extends State<AnkiReviewSessionPage> {
  bool _loading = true;
  Object? _error;
  StudySessionController? _controller;
  OfficialReviewSession? _officialSession;
  OfficialFormalReviewLiveQueue? _officialSessionLiveQueue;
  Map<String, AnkiHtmlCard> _fidelityInteractions = const {};
  FormalReviewSourceCoordinator? _sourceCoordinator;
  bool _advancingSource = false;
  bool _advanceScheduled = false;
  bool _reviewAllComplete = false;
  int _earnedXp = 0;
  bool _sessionCompletedRecorded = false;
  final DateTime _sessionStartedAt = DateTime.now();

  /// One per page instance: scopes the settlement gem reward's
  /// idempotency key so every completed session earns exactly once.
  final String _gemSessionSequence =
      DateTime.now().microsecondsSinceEpoch.toString();

  /// Wave 2 (§8.4): a Blocked load — the scheduler owes cards but none
  /// could be rendered. Surfaced with retry / continue-later; never
  /// silently ends the source.
  OfficialFormalReviewBlocked? _blockedLoad;

  Future<void> _recordSessionCompletion({
    required int total,
    required int remembered,
    required int forgotten,
    required Duration elapsed,
  }) async {
    if (total == 0 || _sessionCompletedRecorded) return;
    _sessionCompletedRecorded = true;
    final xp = await SessionSettlementService.fromContext(context).settle(
      source: SessionSettlementSource.anki,
      sessionSequence: _gemSessionSequence,
      remembered: remembered,
      forgotten: forgotten,
      elapsed: elapsed,
    );
    if (mounted) {
      setState(() {
        _earnedXp = xp;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onController);
    _controller?.dispose();
    _officialSessionLiveQueue?.removeListener(_onLiveQueueRebuilt);
    _officialSession?.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    final controller = _controller;
    if (controller != null && controller.isComplete) {
      if (_sourceCoordinator != null &&
          !_advancingSource &&
          !_advanceScheduled) {
        _advanceScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) {
            _advanceScheduled = false;
            unawaited(_advanceReviewAll());
          },
        );
      } else if (_sourceCoordinator == null && !_sessionCompletedRecorded) {
        unawaited(_recordSessionCompletion(
          total: controller.answeredCount,
          remembered: controller.rememberedCount,
          forgotten: controller.forgottenCount,
          elapsed: DateTime.now().difference(controller.startedAt),
        ));
      }
    }
    setState(() {});
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
      _blockedLoad = null;
      _controller?.removeListener(_onController);
      _controller?.dispose();
      _controller = null;
      _officialSessionLiveQueue?.removeListener(_onLiveQueueRebuilt);
      _officialSessionLiveQueue = null;
      _officialSession?.dispose();
      _officialSession = null;
      _fidelityInteractions = const {};
    });

    try {
      if (widget.sectionId == null) {
        final catalogCoordinator = FormalReviewSourceCoordinator.fromCatalog(
          context.read<CourseProvider>().catalogEntries,
        );
        _sourceCoordinator ??= catalogCoordinator.targets.isNotEmpty
            ? catalogCoordinator
            : FormalReviewSourceCoordinator.fromOfficialSourceIds(
                OfficialFormalDueRepository.instance.officialImportIds,
              );
      }
      final sourceTarget = _sourceCoordinator?.current;
      if (_sourceCoordinator?.isComplete == true) {
        if (!mounted) return;
        setState(() {
          _reviewAllComplete = true;
          _loading = false;
        });
        return;
      }
      final selectedSectionId = sourceTarget == null ? widget.sectionId : null;
      final importId = sourceTarget?.importOrSourceId ??
          (selectedSectionId == null
              ? ''
              : LegacyAnkiIdentifiers.importIdFromSectionId(selectedSectionId));
      final officialOwner = sourceTarget != null
          ? sourceTarget.owner == AnkiEngineKind.official
          : widget.officialOwner ??
              OfficialFormalDueRepository.instance.officialImportIds
                  .contains(importId);
      final launch = const FormalReviewLauncher().resolve(
        entry: FormalReviewEntryKind.ankiHub,
        courseId: importId.isEmpty ? 'anki' : 'anki-$importId',
        sectionId: selectedSectionId,
        officialOwner: officialOwner,
        schedulerRuntimeAvailable:
            OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
      );
      if (launch.isFailClosed) {
        if (!mounted) return;
        setState(() {
          _error = FormalReviewLauncher.failClosedMessage;
          _loading = false;
        });
        return;
      }

      final blocked = sourceTarget != null
          ? false
          : await const AnkiOfficialReviewGate().openInsteadOfLegacy(
              context,
              sectionId: selectedSectionId,
            );
      if (!mounted) return;
      if (blocked) {
        setState(() {
          _error = FormalReviewLauncher.failClosedMessage;
          _loading = false;
        });
        return;
      }

      final selectedImportId = importId;
      final courseId =
          selectedImportId.isEmpty ? 'anki' : 'anki-$selectedImportId';

      if (officialOwner) {
        await _startOfficialOwned(
          importId: selectedImportId,
          courseId: courseId,
        );
        return;
      }

      // Doc 35 L2: the Legacy assembler + Turna SRS runtime branch is
      // deleted. A source that is still Legacy-owned (recorded legacy
      // owner, never migrated) fails closed instead of silently rendering
      // a different scheduler's semantics.
      if (!mounted) return;
      setState(() {
        _error = FormalReviewLauncher.failClosedMessage;
        _loading = false;
      });
      return;
    } catch (error) {
      final coordinator = _sourceCoordinator;
      if (coordinator?.current != null) {
        coordinator!.recordFailure(
          error,
          kind: FormalReviewFailureKind.runtime,
        );
        await _advanceReviewAll(recordSession: false);
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _advanceReviewAll({bool recordSession = true}) async {
    final coordinator = _sourceCoordinator;
    if (coordinator == null || _advancingSource) return;
    _advancingSource = true;
    final controller = _controller;
    if (recordSession && controller != null) {
      coordinator.recordSession(
        total: controller.answeredCount,
        remembered: controller.rememberedCount,
        forgotten: controller.forgottenCount,
      );
    }
    coordinator.advance();
    if (coordinator.isComplete) {
      if (mounted) {
        setState(() {
          _reviewAllComplete = true;
          _loading = false;
        });
      }
      unawaited(_recordSessionCompletion(
        total: coordinator.totalCount,
        remembered: coordinator.rememberedCount,
        forgotten: coordinator.forgottenCount,
        elapsed: DateTime.now().difference(_sessionStartedAt),
      ));
      _advancingSource = false;
      return;
    }
    _advancingSource = false;
    await _start();
  }

  /// Official owners: FormalReviewLauncher + OfficialStudyLedger only.
  /// Typed load results (maintainability plan §8.4): NoDue advances Review
  /// All, Blocked waits for an explicit user action — never a silent end.
  Future<void> _startOfficialOwned({
    required String importId,
    required String courseId,
  }) async {
    final builder = AnkiReviewSessionPage.debugOfficialBatchBuilder;
    final OfficialFormalReviewLoadResult? loadResult;
    if (builder != null) {
      loadResult = await builder(importId: importId, courseId: courseId);
    } else {
      loadResult = await AnkiReviewSessionPage.productionLoader.load(
        importId: importId,
        courseId: courseId,
      );
    }
    if (!mounted) return;
    final result = loadResult;
    if (result is OfficialFormalReviewBlocked) {
      // The scheduler still owes these cards — visible, retryable, and in
      // Review All recorded as a render failure the user can continue
      // past explicitly.
      _sourceCoordinator?.recordFailure(
        StateError('blocked:${result.sourceId}'),
        kind: FormalReviewFailureKind.render,
        retryable: true,
        code: result.failures.isNotEmpty
            ? result.failures.first.code
            : 'unknown',
      );
      setState(() {
        _blockedLoad = result;
        _loading = false;
      });
      return;
    }
    OfficialFormalReviewBatch? batch;
    if (result is OfficialFormalReviewReady) {
      batch = result.batch;
    }
    if (batch == null || batch.items.isEmpty) {
      if (_sourceCoordinator != null) {
        await _advanceReviewAll(recordSession: false);
        return;
      }
      setState(() {
        _loading = false;
      });
      return;
    }
    final readyBatch = batch;

    _officialSession = readyBatch.session;
    final liveQueue = readyBatch.liveQueue;
    _officialSessionLiveQueue = liveQueue;
    if (liveQueue != null) {
      liveQueue.addListener(_onLiveQueueRebuilt);
    }

    final host = AnkiStudySessionHost.debugOverride ??
        AnkiStudySessionHost.resolveOrNull() ??
        AnkiStudySessionHost(
          resolver: StudyLedgerResolver(official: readyBatch.ledger),
          onEffects: (item, receipt) async {
            StudyProductAnalytics.instance.record(receipt);
            // Live scheduler contract (plan 34 D4): every committed answer
            // rebuilds the batch from the refreshed queue, so learning
            // reinsertion and cross-day reordering reach the page.
            await liveQueue?.rebuildFromLiveQueue();
          },
          onEffectsUndone: (receipt) async {
            StudyProductAnalytics.instance.forget(receipt.eventId);
            await liveQueue?.rebuildFromLiveQueue();
          },
        );
    final controller = host.openOfficialReview(
      readyBatch.items,
      officialLedger: readyBatch.ledger,
    );
    // P3: the queue pushes rebuilt batches by replacement (it never
    // mutates a shared list).
    liveQueue?.itemsSink = controller.replaceItems;
    controller.addListener(_onController);
    await controller.start();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      // Fidelity HTML faces from production renderCard (fidelity-first
      // policy; flip faces carry plain text only when the card has none).
      _fidelityInteractions = readyBatch.fidelityInteractions;
      _blockedLoad = null;
      _loading = false;
    });
  }

  /// Wave 2 §8.4: retry the current source after a Blocked load. The old
  /// session was already disposed by the loader; this disposes any stale
  /// page-held session before re-loading, so there is never a second
  /// concurrent scheduler session and nothing is double-answered.
  Future<void> _retryBlockedSource() async {
    final blocked = _blockedLoad;
    if (blocked == null) return;
    final coordinator = _sourceCoordinator;
    if (coordinator != null && coordinator.failures.isNotEmpty) {
      // Drop the failure we recorded for this attempt; a successful retry
      // replaces it, an exhausted retry records a fresh one.
      coordinator.failures.removeLast();
    }
    setState(() {
      _blockedLoad = null;
      _loading = true;
    });
    await _start();
  }

  /// Wave 2 §8.4 / §9.4: Review All "continue later" — the failed source
  /// stays recorded and is listed on the completion page.
  Future<void> _continuePastBlockedSource() async {
    if (_blockedLoad == null) return;
    setState(() {
      _blockedLoad = null;
    });
    await _advanceReviewAll(recordSession: false);
  }

  /// The live queue mutated the shared items list — refresh the page's
  /// fidelity faces so rebuilt items keep their WebView content.
  void _onLiveQueueRebuilt() {
    final liveQueue = _officialSessionLiveQueue;
    if (liveQueue == null || !mounted) return;
    setState(() {
      _fidelityInteractions = Map.of(liveQueue.fidelityInteractions);
    });
  }

  /// Wave 2 §8.3: retry the blocked current card inside the SAME session —
  /// no second scheduler session, no re-answer.
  Future<void> _retryBlockedCurrentCard() async {
    final liveQueue = _officialSessionLiveQueue;
    if (liveQueue == null) return;
    await liveQueue.retryCurrentCard();
    if (!mounted) return;
    setState(() {
      _fidelityInteractions = Map.of(liveQueue.fidelityInteractions);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reviewAll = _sourceCoordinator;
    if (_reviewAllComplete && reviewAll != null) {
      final empty = reviewAll.totalCount == 0;
      return Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        body: SafeArea(
          child: Column(
            children: [
              if (reviewAll.failures.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: TurnaTheme.error.withValues(alpha: 0.10),
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusLarge),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: TurnaTheme.error,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '以下来源未能完成：${reviewAll.failures.map((failure) => failure.target.displayName).join('、')}',
                                  style: const TextStyle(
                                    color: TurnaTheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (reviewAll.failedTargets.isNotEmpty)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                key: const Key('anki-review-all-retry-failed'),
                                onPressed: () => unawaited(
                                  _retryFailedSources(reviewAll),
                                ),
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('重试失败来源'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: empty
                    ? _AnkiFormalReviewEmptyPanel(
                        onClose: () => Navigator.of(context).maybePop(),
                      )
                    : UnifiedReviewCompletion(
                        totalCount: reviewAll.totalCount,
                        rememberedCount: reviewAll.rememberedCount,
                        forgottenCount: reviewAll.forgottenCount,
                        elapsed: DateTime.now().difference(_sessionStartedAt),
                        xpEarned: _earnedXp,
                        gemsEarned: 0,
                        onFinish: () => Navigator.of(context).maybePop(),
                      ),
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (!_loading && _error == null && controller != null) {
      return _AnkiStudySessionView(
        controller: controller,
        fidelityInteractions: _fidelityInteractions,
        officialSession: _officialSession,
        liveQueue: _officialSessionLiveQueue,
        onRetryBlockedCard: _retryBlockedCurrentCard,
        sourceProgress: reviewAll?.current == null
            ? null
            : '${reviewAll!.currentIndex + 1}/${reviewAll.targets.length} · '
                '${reviewAll.current!.displayName}',
        earnedXp: _earnedXp,
      );
    }

    final blocked = _blockedLoad;
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.ankiReviewTitle),
        leading: IconButton(
          tooltip: AppStrings.commonClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: _loading
            ? const _PreparingPanel()
            : blocked != null
                ? _BlockedLoadPanel(
                    blocked: blocked,
                    inReviewAll: reviewAll != null,
                    onRetry: _retryBlockedSource,
                    onContinue: _continuePastBlockedSource,
                  )
                : _error != null
                    ? PracticeEmptyState(
                        icon: Icons.error_outline_rounded,
                        accentColor: TurnaTheme.error,
                        title: _error == FormalReviewLauncher.failClosedMessage
                            ? AppStrings.officialAnkiError(
                                FormalReviewLauncher.failClosedMessage,
                              )
                            : AppStrings.ankiReviewLoadFailed,
                        actionLabel: AppStrings.ankiReviewRetry,
                        onAction: () => unawaited(_start()),
                      )
                    : const _AnkiFormalReviewEmptyPanel(),
      ),
    );
  }

  /// Wave 3 §9.4: retry only the failed sources; counts already recorded
  /// for successful sources carry over to the new pass.
  Future<void> _retryFailedSources(
    FormalReviewSourceCoordinator previous,
  ) async {
    final retryTargets = previous.failedTargets;
    if (retryTargets.isEmpty) return;
    final next = FormalReviewSourceCoordinator(retryTargets)
      ..totalCount = previous.totalCount
      ..rememberedCount = previous.rememberedCount
      ..forgottenCount = previous.forgottenCount;
    setState(() {
      _sourceCoordinator = next;
      _reviewAllComplete = false;
      _loading = true;
    });
    await _start();
  }
}

/// Empty formal-review set: not a completed session. New/reset cards are
/// learned in the course tree first.
class _AnkiFormalReviewEmptyPanel extends StatelessWidget {
  const _AnkiFormalReviewEmptyPanel({this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return PracticeEmptyState(
      key: const Key('anki-formal-review-empty'),
      icon: Icons.style_outlined,
      accentColor: TurnaTheme.textHintColor(context),
      title: AppStrings.ankiNoCardsDue,
      message: AppStrings.ankiFormalReviewEmptyHint,
      actionLabel: onClose != null ? AppStrings.commonDone : null,
      onAction: onClose,
    );
  }
}

/// Wave 2 §8.4: unified Blocked surface. Debug builds may show the card /
/// source / stable code; release shows the safe copy only. No implicit
/// scheduling happens from here.
class _BlockedLoadPanel extends StatelessWidget {
  const _BlockedLoadPanel({
    required this.blocked,
    required this.inReviewAll,
    required this.onRetry,
    required this.onContinue,
  });

  final OfficialFormalReviewBlocked blocked;
  final bool inReviewAll;
  final Future<void> Function() onRetry;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final debugDetails = kDebugMode
        ? 'source=${blocked.sourceId} '
            'code=${blocked.failures.isNotEmpty ? blocked.failures.first.code : 'unknown'} '
            'cards=${blocked.schedulerCardCount}'
        : null;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_off_rounded,
              size: 56,
              color: TurnaTheme.textHintColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              '此来源的卡片暂时无法显示',
              key: const Key('anki-review-blocked'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '调度器仍欠 ${blocked.schedulerCardCount} 张卡，未做任何评分、搁置或暂停。',
              style: TextStyle(
                fontSize: 14,
                color: TurnaTheme.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            if (debugDetails != null) ...[
              const SizedBox(height: 8),
              Text(
                debugDetails,
                key: const Key('anki-review-blocked-debug'),
                style: TextStyle(
                  fontSize: 11,
                  color: TurnaTheme.textHintColor(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(AppStrings.ankiReviewRetry),
            ),
            if (inReviewAll) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('anki-review-blocked-continue'),
                onPressed: () => unawaited(onContinue()),
                child: const Text('稍后处理此来源并继续'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreparingPanel extends StatelessWidget {
  const _PreparingPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: TurnaTheme.brandTeal,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.ankiReviewPreparing,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _AnkiStudySessionView extends StatelessWidget {
  const _AnkiStudySessionView({
    required this.controller,
    this.fidelityInteractions = const {},
    this.officialSession,
    this.liveQueue,
    this.onRetryBlockedCard,
    this.sourceProgress,
    this.earnedXp = 0,
  });

  final StudySessionController controller;
  final Map<String, AnkiHtmlCard> fidelityInteractions;
  final OfficialReviewSession? officialSession;

  /// Live queue driver for official owners; mutations (bury/suspend) refresh
  /// the batch through it (plan 34 D4).
  final OfficialFormalReviewLiveQueue? liveQueue;

  /// Wave 2 §8.3: retries the blocked current card in the same session.
  final Future<void> Function()? onRetryBlockedCard;
  final String? sourceProgress;
  final int earnedXp;

  /// Live scheduler contract (plan 34 D4): after every committed mutation
  /// the next card is the scheduler's refreshed [OfficialReviewSession.current]
  /// — never index+1 over a batch list that just shrank or reordered.
  Future<void> _advanceFromScheduler() async {
    final session = officialSession;
    if (session == null) {
      await controller.continueNext();
      return;
    }
    final currentCardId = session.current?.cardId;
    if (currentCardId == null) {
      await controller.advanceTo(null);
      return;
    }
    for (final item in controller.items) {
      if (item.cardKey.cardId == currentCardId) {
        await controller.advanceTo(item.sessionItemId);
        return;
      }
    }
    // Give liveQueue one chance to reconcile if rebuild is in flight or pending
    if (liveQueue != null) {
      await liveQueue!.rebuildFromLiveQueue();
      for (final item in controller.items) {
        if (item.cardKey.cardId == currentCardId) {
          await controller.advanceTo(item.sessionItemId);
          return;
        }
      }
    }
    // Unreachable while the scheduler's current always sits inside the
    // assembled batch; surface a structured desync (retryable) instead of
    // silently completing a session the scheduler still owes.
    controller.reportSchedulerDesync(currentCardId);
  }

  @override
  Widget build(BuildContext context) {
    // Live-queue hosts replace items after every answer, so totalCount is
    // the residual scheduler queue at completion, never the session size —
    // the summary must count answered cards (40 answered against a residual
    // 1-card batch rendered 4000%).
    final answeredCount = controller.answeredCount;
    if (controller.isComplete && answeredCount > 0) {
      return Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        body: SafeArea(
          child: UnifiedReviewCompletion(
            totalCount: answeredCount,
            rememberedCount: controller.rememberedCount,
            forgottenCount: controller.forgottenCount,
            elapsed: DateTime.now().difference(controller.startedAt),
            xpEarned: earnedXp,
            gemsEarned: 0,
            onFinish: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }
    if (controller.items.isEmpty ||
        (controller.isComplete && answeredCount == 0)) {
      return Scaffold(
        body: SafeArea(
          child: _AnkiFormalReviewEmptyPanel(
            onClose: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    final item = controller.currentItem;
    if (item == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final revealed = controller.answerReceipt != null ||
        controller.phase == StudyCardPhase.showingAnswer ||
        controller.phase == StudyCardPhase.showingFeedback ||
        controller.phase == StudyCardPhase.readyForNext;
    final structured = item.presentation is StructuredCardPresentation;
    // Wave 2 §8.3: a blocked current card locks scoring until retried.
    final blockedFailure = liveQueue?.currentBlockedFailure;

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: ReviewProgressHeader(
        progress: controller.totalCount == 0
            ? 1
            : controller.currentIndex / controller.totalCount,
        currentIndex: controller.currentIndex + 1,
        totalCount: controller.totalCount,
        onBack: () => Navigator.of(context).maybePop(),
        onUndo: () async {
          final ok = await controller.undoLast();
          if (!ok || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已撤销上一张评分'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        canUndo: controller.lastReceipt != null && !controller.isLocked,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Same responsive chrome as the unified review page: the gap
            // between card area and rating bar shrinks on short screens and
            // tablets center within the max content width.
            final mq = MediaQuery.of(context);
            final sizing = resolveAnkiWebViewSizing(
              AnkiWebViewSizingInput(
                viewport: Size(constraints.maxWidth, constraints.maxHeight),
                orientation: mq.orientation,
                scene: AnkiWebViewScene.review,
              ),
            );
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: sizing.horizontalPadding,
                vertical: 16,
              ),
              child: Column(
                children: [
                  _AnkiSessionToolbar(
                    sourceProgress: sourceProgress,
                    canRedo: controller.canRedo,
                    canMutate: !controller.isLocked && !controller.isComplete,
                    onRedo: () async {
                      final ok = await controller.redoLast();
                      if (ok) {
                        await liveQueue?.rebuildFromLiveQueue();
                        await _advanceFromScheduler();
                      }
                    },
                    onBury: () async {
                      final ok = await controller.buryCurrent(
                        onMutated: liveQueue == null
                            ? null
                            : () => liveQueue!.rebuildFromLiveQueue(),
                      );
                      if (ok) {
                        await _advanceFromScheduler();
                      }
                    },
                    onSuspend: () async {
                      final ok = await controller.suspendCurrent(
                        onMutated: liveQueue == null
                            ? null
                            : () => liveQueue!.rebuildFromLiveQueue(),
                      );
                      if (ok) {
                        await _advanceFromScheduler();
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StudyCardSurface(
                      presentation: item.presentation,
                      content: _contentFor(item),
                      isRevealed: revealed,
                      generation: controller.generation,
                      onReveal: () {
                        unawaited(
                          AnkiStudySessionHost.revealAndPresentAnswer(
                            controller,
                            onOfficialShowAnswer: officialSession?.showAnswer,
                          ),
                        );
                      },
                      onPresented: controller.acceptPresentation,
                      onObjectiveResult: structured
                          ? (correct) {
                              unawaited(
                                controller.submitObjectiveAnswer(
                                    correct: correct),
                              );
                            }
                          : null,
                    ),
                  ),
                  SizedBox(height: sizing.bottomGap),
                  if (blockedFailure != null) ...[
                    Text(
                      '当前卡片暂时无法显示，评分已锁定。',
                      key: const Key('anki-study-session-render-blocked'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: TurnaTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (kDebugMode)
                      Text(
                        'card=${blockedFailure.cardId} '
                        'source=${blockedFailure.sourceId} '
                        'code=${blockedFailure.code}',
                        key: const Key('anki-study-session-render-debug'),
                        style: TextStyle(
                          fontSize: 11,
                          color: TurnaTheme.textHintColor(context),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onRetryBlockedCard == null
                          ? null
                          : () => unawaited(onRetryBlockedCard!()),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(AppStrings.ankiReviewRetry),
                    ),
                  ] else if (controller.phase ==
                      StudyCardPhase.recoverableError) ...[
                    const Text(
                      '当前卡片无法安全写入，请重试或稍后返回。',
                      key: Key('anki-study-session-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TurnaTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: controller.retryCurrent,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(AppStrings.ankiReviewRetry),
                    ),
                  ] else if (structured)
                    const SizedBox.shrink()
                  else if (!revealed)
                    _ShowAnswerButton(
                      onPressed: controller.canReveal
                          ? () => unawaited(
                                AnkiStudySessionHost.revealAndPresentAnswer(
                                  controller,
                                  onOfficialShowAnswer:
                                      officialSession?.showAnswer,
                                ),
                              )
                          : null,
                    )
                  else
                    BinaryRecallBar(
                      onOutcome: (outcome) async {
                        await controller.submitRecall(outcome);
                        if (controller.phase == StudyCardPhase.readyForNext) {
                          await _advanceFromScheduler();
                        }
                      },
                      enabled: controller.canSubmitRecall,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  ReviewContentBodyData _contentFor(StudyItem item) {
    return reviewContentFor(item, fidelityInteractions: fidelityInteractions);
  }
}

/// Source chip + redo/bury/suspend. Kept out of the progress header so the
/// count and undo stay readable on a narrow phone.
class _AnkiSessionToolbar extends StatelessWidget {
  const _AnkiSessionToolbar({
    required this.sourceProgress,
    required this.canRedo,
    required this.canMutate,
    required this.onRedo,
    required this.onBury,
    required this.onSuspend,
  });

  final String? sourceProgress;
  final bool canRedo;
  final bool canMutate;
  final Future<void> Function() onRedo;
  final Future<void> Function() onBury;
  final Future<void> Function() onSuspend;

  @override
  Widget build(BuildContext context) {
    final secondary = TurnaTheme.textSecondaryColor(context);
    return Row(
      children: [
        if (sourceProgress != null)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: TurnaTheme.softTint(
                  context,
                  TurnaTheme.brandSky,
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                border: Border.all(
                  color: TurnaTheme.practiceTileBorder(context),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.style_rounded,
                    size: 16,
                    color: TurnaTheme.accentOnCard(context, TurnaTheme.brandSky),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sourceProgress!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          const Spacer(),
        IconButton(
          tooltip: AppStrings.ankiCardRedo,
          icon: const Icon(Icons.redo_rounded, size: 20),
          onPressed: canRedo ? () => unawaited(onRedo()) : null,
        ),
        IconButton(
          tooltip: AppStrings.ankiCardBury,
          icon: Icon(Icons.bedtime_outlined, size: 20, color: secondary),
          onPressed: canMutate ? () => unawaited(onBury()) : null,
        ),
        IconButton(
          tooltip: AppStrings.ankiCardSuspend,
          icon: Icon(
            Icons.pause_circle_outline_rounded,
            size: 20,
            color: secondary,
          ),
          onPressed: canMutate ? () => unawaited(onSuspend()) : null,
        ),
      ],
    );
  }
}

class _ShowAnswerButton extends StatelessWidget {
  const _ShowAnswerButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: TurnaTheme.brandTeal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
        child: Text(
          AppStrings.lessonShowAnswer,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
