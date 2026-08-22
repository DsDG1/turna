import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/anki/anki_review_content.dart';
import 'package:turna/application/anki/anki_study_session_host.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki/study_ledger_adapters.dart';
import 'package:turna/application/anki/study_product_analytics.dart';
import 'package:turna/application/anki/study_session_controller.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/turna_review_ledger.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_official_review_gate.dart';
import 'package:turna/views/anki/anki_webview_sizing.dart';
import 'package:turna/views/review/components/binary_recall_bar.dart';
import 'package:turna/views/review/components/review_progress_header.dart';
import 'package:turna/views/review/components/study_card_surface.dart';
import 'package:turna/views/review/components/unified_review_completion.dart';
import 'package:turna/views/theme.dart';

/// Shared formal-review session for Turna-owned and Official-owned Anki cards.
///
/// Every production entry lands here. Official capability failures fail closed
/// and never open a different-semantics page.
@RoutePage()
class AnkiReviewSessionPage extends StatefulWidget {
  const AnkiReviewSessionPage({super.key, this.sectionId});

  final String? sectionId;

  @override
  State<AnkiReviewSessionPage> createState() => _AnkiReviewSessionPageState();
}

class _AnkiReviewSessionPageState extends State<AnkiReviewSessionPage> {
  late final AnkiDeckManager _deckManager;
  final Set<String> _newCardInteractionIds = {};

  bool _loading = true;
  bool _empty = false;
  Object? _error;
  StudySessionController? _controller;
  Map<String, AnkiHtmlCard> _fidelityInteractions = const {};

  @override
  void initState() {
    super.initState();
    _deckManager = getIt<AnkiDeckManager>();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  @override
  void dispose() {
    _controller?.removeListener(_onController);
    _controller?.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _empty = false;
      _error = null;
      _controller?.removeListener(_onController);
      _controller?.dispose();
      _controller = null;
      _fidelityInteractions = const {};
      _newCardInteractionIds.clear();
    });

    try {
      final importId = widget.sectionId == null
          ? ''
          : AnkiReviewAssembler.importIdFromSectionId(widget.sectionId!);
      final officialOwner = OfficialAnkiHomeDue.officialImportIds.contains(
        importId,
      );
      final launch = const FormalReviewLauncher().resolve(
        entry: FormalReviewEntryKind.ankiHub,
        courseId: importId.isEmpty ? 'anki' : 'anki-$importId',
        sectionId: widget.sectionId,
        officialOwner: officialOwner,
        officialCapable:
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

      final blocked = await const AnkiOfficialReviewGate().openInsteadOfLegacy(
        context,
        sectionId: widget.sectionId,
      );
      if (!mounted) return;
      if (blocked) {
        setState(() {
          _error = FormalReviewLauncher.failClosedMessage;
          _loading = false;
        });
        return;
      }

      final course = context.read<CourseProvider>();
      final srs = context.read<SrsProvider>();
      final noteDao = getIt<AnkiNoteDao>();
      final expiredBuried = await noteDao.clearBuriedBefore(
        DateTime.now().millisecondsSinceEpoch,
      );
      for (final card in expiredBuried) {
        await srs.setWordFlags(card.wordId, buried: false);
      }

      final selectedImportId = widget.sectionId == null
          ? ''
          : AnkiReviewAssembler.importIdFromSectionId(widget.sectionId!);
      final maxNew = selectedImportId.isEmpty
          ? _deckManager.newRemainingToday
          : await _deckManager.remainingForImport(
              selectedImportId,
              isNew: true,
            );
      final maxReview = selectedImportId.isEmpty
          ? _deckManager.reviewRemainingToday
          : await _deckManager.remainingForImport(
              selectedImportId,
              isNew: false,
            );

      final batch = await AnkiReviewAssembler(
        srs,
        course,
        noteDao: noteDao,
      ).assembleReviewBatchAsync(
        sectionId: widget.sectionId,
        maxNew: maxNew,
        maxReview: maxReview,
      );
      if (!mounted) return;

      final courseId =
          selectedImportId.isEmpty ? 'anki' : 'anki-$selectedImportId';
      final items = <StudyItem>[];
      final fidelityInteractions = <String, AnkiHtmlCard>{};
      for (final card in batch) {
        final interaction = card.interaction;
        final wordId = card.scheduled.wordId;
        if (card.scheduled.reps == 0) {
          _newCardInteractionIds.add(interaction.id);
        }
        final item = AnkiStudySessionHost.itemFromReviewCard(
          wordId: wordId,
          interaction: interaction,
          mode: StudyMode.review,
          courseId: courseId,
        );
        items.add(item);
        if (interaction is AnkiHtmlCard) {
          fidelityInteractions[item.sessionItemId] = interaction;
        }
      }

      if (items.isEmpty) {
        setState(() {
          _empty = true;
          _loading = false;
        });
        return;
      }

      final host = AnkiStudySessionHost.debugOverride ??
          AnkiStudySessionHost.resolveOrNull() ??
          AnkiStudySessionHost(
            resolver: StudyLedgerResolver(
              turna: TurnaStudyLedger(TurnaReviewLedger(srs)),
            ),
            onEffects: (item, receipt) async {
              StudyProductAnalytics.instance.record(receipt);
              await _recordQuota(item);
            },
            onEffectsUndone: (receipt) async {
              StudyProductAnalytics.instance.forget(receipt.eventId);
              await _undoQuota(receipt);
            },
          );
      final controller = host.open(items);
      controller.addListener(_onController);
      await controller.start();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _fidelityInteractions = fidelityInteractions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _recordQuota(StudyItem item) {
    return _deckManager.recordCardReviewed(
      isNewCard: _newCardInteractionIds.contains(item.sessionItemId),
      importId: _importIdFromWordId(TurnaStudyLedger.wordIdFor(item.cardKey)),
    );
  }

  Future<void> _undoQuota(StudyEventReceipt receipt) {
    return _deckManager.recordCardUnreviewed(
      wasNewCard: false,
      importId: _importIdFromWordId(TurnaStudyLedger.wordIdFor(receipt.cardKey)),
    );
  }

  String? _importIdFromWordId(String wordId) {
    if (!wordId.startsWith('anki-')) return null;
    final cardSeparator = wordId.lastIndexOf('-c');
    if (cardSeparator <= 5) return null;
    return wordId.substring(5, cardSeparator);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_loading && _error == null && controller != null) {
      return _AnkiStudySessionView(
        controller: controller,
        fidelityInteractions: _fidelityInteractions,
      );
    }

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
            ? const CircularProgressIndicator()
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error == FormalReviewLauncher.failClosedMessage
                            ? FormalReviewLauncher.failClosedMessage
                            : AppStrings.ankiReviewLoadFailed,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _start,
                        child: Text(AppStrings.ankiReviewRetry),
                      ),
                    ],
                  )
                : Text(AppStrings.ankiNoCardsDue),
      ),
    );
  }
}

class _AnkiStudySessionView extends StatelessWidget {
  const _AnkiStudySessionView({
    required this.controller,
    this.fidelityInteractions = const {},
  });

  final StudySessionController controller;
  final Map<String, AnkiHtmlCard> fidelityInteractions;

  @override
  Widget build(BuildContext context) {
    if (controller.isComplete || controller.items.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: UnifiedReviewCompletion(
            totalCount: controller.totalCount,
            rememberedCount: controller.rememberedCount,
            forgottenCount: controller.forgottenCount,
            elapsed: DateTime.now().difference(controller.startedAt),
            onFinish: () => Navigator.of(context).maybePop(),
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
                  Expanded(
                    child: StudyCardSurface(
                      presentation: item.presentation,
                      content: _contentFor(item),
                      isRevealed: revealed,
                      generation: controller.generation,
                      onReveal: () {
                        unawaited(
                          AnkiStudySessionHost.revealAndPresentAnswer(controller),
                        );
                      },
                      onPresented: controller.acceptPresentation,
                      onObjectiveResult: structured
                          ? (correct) {
                              unawaited(
                                controller.submitObjectiveAnswer(correct: correct),
                              );
                            }
                          : null,
                    ),
                  ),
                  SizedBox(height: sizing.bottomGap),
                  if (controller.phase == StudyCardPhase.recoverableError) ...[
                    const Text(
                      '当前卡片无法安全写入，请重试或稍后返回。',
                      key: Key('anki-study-session-error'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: controller.retryCurrent,
                      child: Text(AppStrings.ankiReviewRetry),
                    ),
                  ] else if (structured)
                    const SizedBox.shrink()
                  else if (!revealed)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: controller.canReveal
                            ? () => unawaited(
                                  AnkiStudySessionHost.revealAndPresentAnswer(
                                    controller,
                                  ),
                                )
                            : null,
                        child: Text(AppStrings.lessonShowAnswer),
                      ),
                    )
                  else
                    BinaryRecallBar(
                      onOutcome: (outcome) async {
                        await controller.submitRecall(outcome);
                        if (controller.phase == StudyCardPhase.readyForNext) {
                          await controller.continueNext();
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
