import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_import/adaptation/card_presentation_resolver.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/review/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/review/official_formal_review_results.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';

export 'package:turna/application/anki_official/review/official_formal_review_results.dart';

/// One live formal-review card (ADR 0044).
///
/// A snapshot is valid for exactly one scheduler `current`: answering (or
/// any queue mutation) invalidates it, and the next card always comes from
/// a fresh read of the session queue — never from a fixed pre-assembled
/// array.
@immutable
class FormalReviewCardSnapshot {
  const FormalReviewCardSnapshot({
    required this.sourceId,
    required this.cardId,
    required this.renderGeneration,
    required this.presentation,
    required this.inQueue,
    this.fidelityHtml,
    this.answerToken,
  });

  final String sourceId;
  final int cardId;

  /// Increments whenever the underlying queue was refreshed; a snapshot
  /// built against an older generation is stale by construction.
  final int renderGeneration;
  final CardPresentation presentation;

  /// False once the scheduler moved this card out of the live queue.
  final bool inQueue;

  /// Present when the card renders through the fidelity WebView.
  final AnkiHtmlCard? fidelityHtml;

  /// Opaque engine token for the current scheduling context.
  final String? answerToken;

  bool get isValid => inQueue && presentation.sourceFingerprint.isNotEmpty;
}

/// Rendered presentation + fidelity HTML for one card, produced by
/// [OfficialAnkiEngine.renderCard] and cached per (source, card) for the
/// lifetime of a review session so live queue rebuilds never re-render
/// cards the user already saw.
///
/// [rendered] carries the engine's full output — faces, css, typed-answer
/// metadata, AV tags — so the OHOS/Android reviewer stage can ADOPT the
/// loader's render instead of asking the engine for the same card again
/// (P5: every card used to render twice, once for the batch and once for
/// the on-screen controller).
class OfficialRenderedFace {
  const OfficialRenderedFace({
    required this.presentation,
    required this.htmlCard,
    required this.rendered,
  });

  final CardPresentation presentation;
  final AnkiHtmlCard htmlCard;
  final OfficialAnkiRenderedCard rendered;
}

/// 正式复习 flip 面的媒体：只用 `renderCard` 给出的 `soundOrVideo` 标签。
///
/// 三条边界（ADR 0057 §7.3 / §8.4）：
/// - TTS 标签是官方 AV 语义，不伪装成一个存在的音频文件；
/// - 视频不在本阶段支持范围，宁可不列，也不让它落进音频条被当成音频播；
/// - 面归属用官方给的正/背 AV 标签，不从字段顺序猜。
List<CanonicalMediaRef> formalReviewFlipMedia(
  OfficialAnkiRenderedCard rendered,
) {
  const audioExtensions = <String>{
    'mp3',
    'ogg',
    'oga',
    'wav',
    'm4a',
    'aac',
    'flac',
    'opus',
    'webm',
  };

  CanonicalMediaRef? refFor(OfficialAnkiAvTag tag, MediaOccurrenceSide side) {
    if (tag.kind != OfficialAnkiAvKind.soundOrVideo) return null;
    final raw = tag.filename?.trim();
    if (raw == null || raw.isEmpty) return null;
    final name = raw.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    final extension = name.substring(dot + 1).toLowerCase();
    if (!audioExtensions.contains(extension)) return null;
    return CanonicalMediaRef(
      filename: name,
      kind: CanonicalMediaKind.audio,
      side: side,
    );
  }

  return <CanonicalMediaRef>[
    for (final tag in rendered.questionAvTags)
      if (refFor(tag, MediaOccurrenceSide.front) case final ref?) ref,
    for (final tag in rendered.answerAvTags)
      if (refFor(tag, MediaOccurrenceSide.back) case final ref?) ref,
  ];
}

/// Whether an engine-rendered face must stay in the fidelity WebView instead
/// of the stripped flip face (ADR 0057 §8).
///
/// This is the single definition of "plain text cannot carry this face": any
/// tag, entity, cloze or MathJax marker means stripping would corrupt it. The
/// formal-review renderer consumes it; the choice itself is made by the
/// presentation resolver, so this predicate only picks between two ways of
/// showing the ORIGINAL card, never a different presentation.
bool officialRenderedFaceNeedsFidelity(String html) {
  if (html.isEmpty) return false;
  return html.contains('<') ||
      html.contains('&') ||
      html.contains('{{c') ||
      html.contains('\\(') ||
      html.contains('\\[');
}

/// Content fingerprint of a rendered card: changes exactly when the card's
/// rendered faces change (template ordinal, body class, css, both faces).
///
/// The old value was the constant `'official-render-$cardId'`, which never
/// changed — anything using the fingerprint to detect "the card changed"
/// (caches, drift detection) was silently broken on the formal-review side.
String officialRenderedContentFingerprint(OfficialAnkiRenderedCard rendered) {
  final digest = sha256.convert(
    utf8.encode(
      '${rendered.templateOrdinal}|${rendered.bodyClass}|'
      '${rendered.css}|${rendered.questionHtml}|${rendered.answerHtml}',
    ),
  );
  return 'official-render-${digest.toString()}';
}

/// Official formal-review presentation resolver (ADR 0044 + ADR 0057 §8).
///
/// The presentation decision comes from [OfficialCardPresentationResolver]
/// with `formalReview: true` — phase one pins every card to the original
/// rendering there, so this class never re-derives a presentation of its own
/// (ADR 0057 §1: one resolver). What remains local is the choice between two
/// ways of showing that original card: the fidelity WebView, or a stripped
/// flip face for cards whose HTML carries no markup at all.
class OfficialFormalReviewRenderer {
  const OfficialFormalReviewRenderer({required this.engine, this.profileId});

  final OfficialAnkiEngine engine;
  final String? profileId;

  Future<OfficialRenderedFace> render({
    required String sourceId,
    required int cardId,
  }) async {
    final rendered = await engine.renderCard(cardId: cardId);

    // Phase one never inspects card facts: the policy short-circuits
    // formalReview to the original card (ADR 0057 §8), so the empty values
    // are never read. Going through the resolver anyway keeps the decision
    // typed and in one place — if a later phase allows structured cards in
    // formal review, this is the only call site that has to react.
    final resolution = const OfficialCardPresentationResolver().resolve(
      values: OfficialAnkiRoleValues.empty,
      mapping: null,
      formalReview: true,
    );
    if (!resolution.decision.isOriginalCard) {
      // Structured decisions are unreachable in phase one; failing closed to
      // the original card is safer than rendering half a structured exercise
      // without the projection machinery this path does not have.
      officialAnkiV2Log(
        'formal review got a ${resolution.kind.name} decision for card '
        '$cardId; phase one renders the original card instead',
        warning: true,
      );
    }

    final frontHtml = rendered.questionHtml.trim();
    final backHtml = rendered.answerHtml.trim();
    final fingerprint = officialRenderedContentFingerprint(rendered);

    final htmlCard = AnkiHtmlCard(
      id: 'official-$sourceId-$cardId',
      frontHtml: rendered.questionHtml,
      backHtml: rendered.answerHtml,
      css: rendered.css,
      sourceCardId: '$cardId',
      wordId: 'official-anki-$sourceId-c$cardId',
    );

    if (officialRenderedFaceNeedsFidelity(frontHtml) ||
        officialRenderedFaceNeedsFidelity(backHtml)) {
      // Fidelity-first: the shared host renders the real HTML through the
      // WebView; the stripped text remains available only as an
      // accessibility fallback inside the fidelity surface.
      return OfficialRenderedFace(
        presentation: FidelityCardPresentation(
          cardKey: CanonicalCardKey(
            backend: AnkiBackendKind.official,
            profileId: profileId ?? '',
            sourceId: sourceId,
            cardId: cardId,
          ),
          templateRef: CanonicalTemplateRef(
            // The render contract exposes no notetype id; the ordinal plus the
            // content fingerprint below still identify the rendering uniquely.
            notetypeId: 0,
            ordinal: rendered.templateOrdinal,
            fingerprint: fingerprint,
          ),
          sourceFingerprint: fingerprint,
        ),
        htmlCard: htmlCard,
        rendered: rendered,
      );
    }

    final frontText = _plainText(rendered.questionDisplayHtml, frontHtml);
    final backText = _plainText(rendered.answerDisplayHtml, backHtml);
    return OfficialRenderedFace(
      presentation: FlipCardPresentation(
        cardKey: CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: profileId ?? '',
          sourceId: sourceId,
          cardId: cardId,
        ),
        frontText: frontText.isEmpty ? '—' : frontText,
        backText: backText.isEmpty ? '—' : backText,
        // ADR 0057 §8：正式复习仍是原卡优先，但原卡自带的音画不该在纯文本面
        // 上消失。按 renderCard 的 AV 事实恢复，并按官方给出的面归属。
        media: formalReviewFlipMedia(rendered),
        sourceFingerprint: fingerprint,
      ),
      htmlCard: htmlCard,
      rendered: rendered,
    );
  }

  static String _plainText(String display, String raw) {
    final trimmed = display.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return raw.trim();
  }
}

/// Drives the shared session host from the scheduler's LIVE queue
/// (ADR 0044).
///
/// The batch's [items] list is mutated in place after every answer: the
/// answered card's next appearance (learning reinsertion, cross-day
/// reordering) is wherever the scheduler puts it, and cards leaving the
/// queue leave the batch. The current card is always
/// `session.current.cardId` — the controller index only positions into the
/// rebuilt list, and `answerAndConfirm(expectedCardId:)` fails loudly if
/// they ever disagree.
///
/// A card that fails to render during a rebuild is recorded as a
/// structured [OfficialCardRenderFailure]; when that card is the CURRENT
/// one the queue reports [OfficialLiveQueueBlockedOnCurrentCard], keeps
/// the previous items visible and locks scoring — it is never silently
/// dropped (maintainability plan §8.3).
/// How many cards the reviewer renders before it hands the batch over (P0-2).
///
/// Eight, not one. A single-card batch would make the controller's `totalCount`
/// start at 1 and jump to 8 on the first answer (the progress bar reads 1/1
/// then 1/8), and `OfficialStudyBatchAssembler` skips cards without a
/// presentation — so a one-card window also lets the batch/ledger converge
/// early. Eight still costs about 8% of a hundred-card render.
///
/// The same number is the rolling window in [_doRebuild]: after every mutation
/// the current card plus the next seven are kept rendered, and the rest arrive
/// as the learner advances.
const int officialInitialRenderWindow = 8;

class OfficialFormalReviewLiveQueue extends ChangeNotifier {
  OfficialFormalReviewLiveQueue({
    required this.session,
    required this.sourceId,
    required this.courseId,
    required this.renderer,
    required this.assembler,
    required List<StudyItem> items,
    required this.activePlacementCardKeys,
    this.retiredCardKeys = const {},
  })  : _items = List.of(items),
        _faces = <int, OfficialRenderedFace>{};

  final OfficialReviewSession session;
  final String sourceId;
  final String courseId;
  final OfficialFormalReviewRenderer renderer;
  final OfficialStudyBatchAssembler assembler;

  /// The queue's own items copy. P3: rebuilds REPLACE the list — the queue
  /// never mutates a list it does not own, and the live session controller
  /// receives the replacement through [itemsSink].
  List<StudyItem> _items;
  final Map<int, OfficialRenderedFace> _faces;

  /// Late-bound by the page once the [StudySessionController] exists (the
  /// queue is constructed inside the loader, before any controller).
  /// Receives every rebuilt batch; null (legacy/test paths) means the
  /// queue only updates its own copy.
  void Function(List<StudyItem> items)? itemsSink;

  final Set<CanonicalCardKey> activePlacementCardKeys;
  final Set<CanonicalCardKey> retiredCardKeys;

  /// Fidelity HTML faces keyed by sessionItemId for the shared host.
  final Map<String, AnkiHtmlCard> fidelityInteractions = {};

  /// Structured render failures from the last rebuild — displayed in the
  /// session summary, never containing card content.
  final List<OfficialCardRenderFailure> renderFailures = [];

  int _generation = 0;
  bool rebuilding = false;
  Object? lastRebuildError;

  /// Set while the scheduler's current card cannot be rendered; scoring
  /// must stay locked until [retryCurrentCard] succeeds.
  OfficialCardRenderFailure? currentBlockedFailure;

  int get renderGeneration => _generation;
  int get liveLength => _items.length;
  List<StudyItem> get items => _items;

  int _sessionTotalCards = 0;

  /// How many cards this session is expected to cover — the review header's
  /// DENOMINATOR. Deliberately NOT [liveLength]: that is the rolling render
  /// window ([officialInitialRenderWindow]), so using it pinned the OHOS
  /// header at "1 / 8" no matter how many cards were actually due.
  ///
  /// Prefers the session's exact allowed set — the loader narrows it to
  /// `formalDue ∩ renderable`, which is precisely what this learner owes —
  /// and falls back to the first queue length seen. Monotonic: answering
  /// shrinks the live queue, and a card re-shown by a lapse must never make
  /// the progress bar jump backwards.
  int get sessionTotalCards {
    final allowed = session.allowedCardIds;
    final live = (allowed != null && allowed.isNotEmpty)
        ? allowed.length
        : (session.queue?.cards.length ?? 0);
    if (live > _sessionTotalCards) _sessionTotalCards = live;
    return _sessionTotalCards;
  }

  /// Snapshot of the scheduler's current card (D4). `null` when the queue
  /// is empty or the current card has no rendered face yet.
  FormalReviewCardSnapshot? currentSnapshot() {
    final queue = session.queue;
    final current = session.current;
    if (queue == null || current == null) return null;
    final face = _faces[current.cardId];
    if (face == null) return null;
    return FormalReviewCardSnapshot(
      sourceId: sourceId,
      cardId: current.cardId,
      renderGeneration: _generation,
      presentation: face.presentation,
      inQueue: queue.cards.any((c) => c.cardId == current.cardId),
      fidelityHtml: face.htmlCard,
      answerToken: current.answerToken,
    );
  }

  bool _pendingRebuild = false;

  /// Rebuilds the batch items from the refreshed live queue. Called after
  /// every answer / undo / bury / suspend — the session queue is already
  /// refreshed by then; this maps it back onto shared StudyItems, rendering
  /// previously unseen cards first.
  Future<OfficialLiveQueueRebuildResult> rebuildFromLiveQueue() async {
    if (rebuilding) {
      _pendingRebuild = true;
      return const OfficialLiveQueueRebuildStale();
    }
    rebuilding = true;
    lastRebuildError = null;
    OfficialLiveQueueRebuildResult? lastResult;
    try {
      do {
        _pendingRebuild = false;
        lastResult = await _doRebuild();
      } while (_pendingRebuild);
      return lastResult;
    } finally {
      rebuilding = false;
    }
  }

  Future<OfficialLiveQueueRebuildResult> _doRebuild() async {
    try {
      final queue = session.queue;
      if (queue == null) return const OfficialLiveQueueRebuildStale();
      final failures = <OfficialCardRenderFailure>[];
      // P0-2: a rolling window, not the whole queue.
      //
      // It starts at the scheduler's current card so `currentSnapshot()` always
      // has a face to show, then runs forward to keep the next few warm. Cards
      // behind the current one keep their cached faces (undo can come back to
      // them), which is why the window counts already-rendered cards rather
      // than re-rendering them.
      final startAtCardId = session.current?.cardId;
      final cards = queue.cards;
      final startIndex = startAtCardId == null
          ? 0
          : cards.indexWhere((c) => c.cardId == startAtCardId);
      final ordered = startIndex <= 0 ? cards : cards.sublist(startIndex);

      var rendered = 0;
      for (final card in ordered) {
        if (rendered >= officialInitialRenderWindow) break;
        if (_faces.containsKey(card.cardId)) {
          rendered += 1;
          continue;
        }
        try {
          _faces[card.cardId] = await renderer.render(
            sourceId: sourceId,
            cardId: card.cardId,
          );
          rendered += 1;
        } catch (error) {
          // A failure does not consume a window slot: one unrenderable card
          // must not shrink the window to nothing and stall the session.
          final failure = OfficialCardRenderFailure.fromError(
            error,
            sourceId: sourceId,
            cardId: card.cardId,
            stage: OfficialRenderFailureStage.rebuild,
            renderGeneration: _generation,
          );
          failures.add(failure);
          OfficialFormalReviewRenderAudit.recordRenderFailure(failure);
        }
      }

      final current = session.current;
      final currentCardId = current?.cardId;
      if (currentCardId != null && !_faces.containsKey(currentCardId)) {
        final failure = failures.firstWhere(
          (f) => f.cardId == currentCardId,
          orElse: () => OfficialCardRenderFailure(
            sourceId: sourceId,
            cardId: currentCardId,
            code: 'render_internal_error',
            stage: OfficialRenderFailureStage.rebuild,
            recoverable: false,
            renderGeneration: _generation,
          ),
        );
        currentBlockedFailure = failure;
        renderFailures
          ..clear()
          ..addAll(failures);
        notifyListeners();
        return OfficialLiveQueueBlockedOnCurrentCard(failure);
      }
      currentBlockedFailure = null;
      renderFailures
        ..clear()
        ..addAll(failures);

      final presentations = <CanonicalCardKey, CardPresentation>{
        for (final entry in _faces.values)
          entry.presentation.cardKey: entry.presentation,
      };
      final rebuilt = assembler.assembleFromEligibility(
        sourceId: sourceId,
        courseId: courseId,
        queueCards: queue.cards,
        presentations: presentations,
        activePlacementCardKeys: activePlacementCardKeys,
        retiredCardKeys: retiredCardKeys,
      );
      _generation += 1;
      _items = List.of(rebuilt);
      fidelityInteractions
        ..clear()
        ..addEntries([
          for (final item in _items)
            if (_faces[item.cardKey.cardId]?.htmlCard != null)
              MapEntry(
                item.sessionItemId,
                _faces[item.cardKey.cardId]!.htmlCard,
              ),
        ]);
      // P3: the controller follows by REPLACEMENT, never by in-place
      // mutation of a shared list.
      itemsSink?.call(_items);
      notifyListeners();
      return const OfficialLiveQueueRebuilt();
    } catch (error) {
      lastRebuildError = error;
      return OfficialLiveQueueRebuildFailed(error);
    }
  }

  /// Retries ONLY the current card's render, then rebuilds against the
  /// same generation (maintainability plan §8.4). Never creates a second
  /// scheduler session and never answers/buries/suspends.
  Future<OfficialLiveQueueRebuildResult> retryCurrentCard() async {
    final current = session.current;
    if (current == null) return rebuildFromLiveQueue();
    final hadFailure = currentBlockedFailure != null;
    try {
      _faces[current.cardId] = await renderer.render(
        sourceId: sourceId,
        cardId: current.cardId,
      );
    } catch (error) {
      final next = OfficialCardRenderFailure.fromError(
        error,
        sourceId: sourceId,
        cardId: current.cardId,
        stage: OfficialRenderFailureStage.retry,
        renderGeneration: _generation,
      );
      OfficialFormalReviewRenderAudit.recordRenderFailure(next);
      currentBlockedFailure = next;
      notifyListeners();
      return OfficialLiveQueueBlockedOnCurrentCard(next);
    }
    currentBlockedFailure = null;
    if (hadFailure) {
      OfficialFormalReviewRenderAudit.recordRenderRecovered();
    }
    return rebuildFromLiveQueue();
  }

  /// Whether the scheduler still owes cards inside the allowed set.
  bool get hasMoreCards => session.queue?.cards.isNotEmpty ?? false;

  /// The loader's own render of [cardId], for hosts that adopt it instead of
  /// re-rendering (P5). `null` for cards this queue never rendered.
  OfficialAnkiRenderedCard? renderedCardFor(int cardId) =>
      _faces[cardId]?.rendered;

  /// Adopts pre-rendered faces (from the loader's initial render pass) so
  /// the first rebuild does not re-render cards the user already saw.
  void adoptFaces(Map<int, OfficialRenderedFace> faces) {
    _faces.addAll(faces);
  }
}

/// Bounded audit of formal-review render failures (maintainability plan
/// §8.5). Records identity + stable code + stage only — never card text,
/// HTML, typed answers or media paths.
class OfficialFormalReviewRenderAudit {
  OfficialFormalReviewRenderAudit._();

  static const _maxEvents = 200;
  static final List<OfficialCardRenderFailure> _failures = [];
  static int _recovered = 0;

  static List<OfficialCardRenderFailure> get failures =>
      List.unmodifiable(_failures);

  static int get recoveredCount => _recovered;

  static void recordRenderFailure(OfficialCardRenderFailure failure) {
    _failures.add(failure);
    if (_failures.length > _maxEvents) {
      _failures.removeRange(0, _failures.length - _maxEvents);
    }
  }

  static void recordRenderRecovered() {
    _recovered += 1;
  }

  static void resetForTest() {
    _failures.clear();
    _recovered = 0;
  }
}
