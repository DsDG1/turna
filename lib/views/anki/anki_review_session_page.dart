import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/review/review_capabilities.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_ledger_resolver.dart';
import 'package:turna/domain/review/review_source.dart';
import 'package:turna/domain/review/turna_review_ledger.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_official_review_gate.dart';
import 'package:turna/views/review/unified_review_page.dart';
import 'package:turna/views/theme.dart';

/// Legacy-import Anki queue hosted by the shared course-style review session.
///
/// Official-routed imports are intercepted by [AnkiOfficialReviewGate]. The
/// remaining cards write only to Turna SRS through [TurnaReviewLedger].
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
  List<ReviewItem>? _items;
  ReviewLedgerResolver? _resolver;

  @override
  void initState() {
    super.initState();
    _deckManager = getIt<AnkiDeckManager>();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _empty = false;
      _error = null;
      _items = null;
      _resolver = null;
      _newCardInteractionIds.clear();
    });

    try {
      final openedOfficial =
          await const AnkiOfficialReviewGate().openInsteadOfLegacy(
        context,
        sectionId: widget.sectionId,
      );
      if (!mounted) return;
      if (openedOfficial) {
        await Navigator.of(context).maybePop();
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

      final items = <ReviewItem>[];
      for (final card in batch) {
        final interaction = card.interaction;
        final wordId = card.scheduled.wordId;
        if (card.scheduled.reps == 0) {
          _newCardInteractionIds.add(interaction.id);
        }
        final source = LegacyAnkiSource(
          importId: _importIdFromWordId(wordId) ?? 'legacy',
        );
        items.add(
          ReviewItem(
            sessionItemId: interaction.id,
            source: source,
            content: _contentFor(interaction),
            capabilities: ReviewCapabilities.legacyAnki,
            schedulingKey: ReviewSchedulingKey(
              rawId: wordId,
              source: source,
            ),
          ),
        );
      }

      setState(() {
        _items = items;
        _resolver = ReviewLedgerResolver(
          turnaLedger: TurnaReviewLedger(srs),
        );
        _empty = items.isEmpty;
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

  ReviewContentBodyData _contentFor(Interaction interaction) {
    if (interaction is AnkiHtmlCard) {
      return OfficialTemplateContent(
        frontHtml: interaction.frontHtml,
        backHtml: interaction.backHtml,
        css: interaction.css,
        mediaBasePath: interaction.mediaBasePath,
      );
    }
    if (interaction is AnkiCard) {
      return StandardCourseCardContent(
        frontText: interaction.front,
        backText: interaction.back,
        backNote: interaction.hint,
        interaction: interaction,
      );
    }
    return StandardCourseCardContent(
      frontText: interactionPromptLabel(interaction),
      backText: interactionCorrectAnswerLabel(interaction) ?? '—',
      interaction: interaction,
    );
  }

  String? _importIdFromWordId(String wordId) {
    if (!wordId.startsWith('anki-')) return null;
    final cardSeparator = wordId.lastIndexOf('-c');
    if (cardSeparator <= 5) return null;
    return wordId.substring(5, cardSeparator);
  }

  Future<void> _recordQuota(ReviewItem item) {
    return _deckManager.recordCardReviewed(
      isNewCard: _newCardInteractionIds.contains(item.sessionItemId),
      importId: _importIdFromWordId(item.schedulingKey.rawId),
    );
  }

  Future<void> _undoQuota(ReviewEventReceipt receipt) {
    final previous = receipt.opaqueUndoState;
    return _deckManager.recordCardUnreviewed(
      wasNewCard: previous is SrsWord && previous.reps == 0,
      importId: _importIdFromWordId(receipt.schedulingKey.rawId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final resolver = _resolver;
    if (!_loading &&
        !_empty &&
        _error == null &&
        items != null &&
        resolver != null) {
      return UnifiedReviewPage(
        items: items,
        ledgerResolver: resolver,
        title: AppStrings.ankiReviewTitle,
        onOutcomeRecorded: (item, _) => _recordQuota(item),
        onOutcomeUndone: _undoQuota,
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
                      Text(AppStrings.ankiReviewLoadFailed),
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
