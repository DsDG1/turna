import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

/// The single source of the Dart↔ArkTS reviewer wire vocabulary.
///
/// Every string here crosses the MethodChannel `me.dsdogs.turna/
/// official_anki_reviewer` (or rides one of its replies), so the two halves
/// of the contract must move together: a rename on one side is a silent
/// `MissingPluginException` or a receipt nobody classifies, and it only
/// shows up when someone opens a card on a device.
///
/// The ArkTS twin is `ohos/entry/src/main/ets/anki/AnkiReviewerProtocol.ets`:
/// for every `static const` here there is an `export const` there under the
/// UPPER_SNAKE spelling of the same name (`receiptOk` ↔ `RECEIPT_OK`), and
/// [test/application/anki_official/
/// official_anki_reviewer_protocol_guard_test.dart] parses both sources and
/// fails on any name or value that does not pair up. One-sided constants are
/// only legal through that test's explicit allowed-difference lists, each
/// entry with a reason.
///
/// Deliberate asymmetries this module does NOT try to erase (recorded so
/// nobody "fixes" them into a regression):
///
/// * **The two ack shapes stay two shapes.** OHOS acks are
///   `{type|stableCode, side, generation}` decoded by the OHOS binding;
///   Android/iOS acks are `{ok, code, generation, side, height, recoverable}`
///   decoded by [OfficialAnkiPresentResult.fromNative]. Both are verified
///   production code and are documented here, not unified.
/// * **Range/MIME has three implementations on purpose.** Dart's
///   `OfficialAnkiHttpRange`/`OfficialAnkiMime` are the normative source
///   (kept alive by their own tests), `anki/AnkiHttp.ets` is the production
///   ArkTS mirror, and `ets/probe/AnkiProbeAssets.ets` keeps a deliberately
///   looser copy. Its three accepted differences, each declared at the top of
///   that file and pinned by differential needles in the guard test: an
///   unrecognized Range prefix and an unparseable Range spec answer 200 with
///   the whole file where production answers 416, and its MIME pair maps `.js`
///   to `application/javascript` instead of `text/javascript` with a
///   correspondingly looser utf-8 branch. Separately, `originAllowed`
///   normalises port `-1` (Dart URL) vs `0` (ArkTS URL).
abstract final class OfficialAnkiReviewerProtocol {
  // ------------------------------------------------------------------ channel

  /// Served by `AnkiReviewerPlugin.ets` on the ArkTS side.
  static const channelName = 'me.dsdogs.turna/official_anki_reviewer';

  // ------------------------------------------- Dart → ArkTS method names
  // (the switch in AnkiReviewerPlugin.ets; invoked from
  // OfficialAnkiReviewerChannel and the probe)

  static const methodOpenReviewer = 'openReviewer';
  static const methodPresentReviewer = 'presentReviewer';
  static const methodCacheReviewerMedia = 'cacheReviewerMedia';
  static const methodAwaitReviewerReady = 'awaitReviewerReady';
  static const methodNotifyReviewerFailure = 'notifyReviewerFailure';
  static const methodProbeReviewerCapabilities = 'probeReviewerCapabilities';
  static const methodProbeReviewerAssets = 'probeReviewerAssets';

  // ------------------------------------------- ArkTS → Dart method names
  // (AnkiReviewerBridge.ets calls these back; the switch lives in
  // OfficialAnkiReviewerChannel.bindOutbound)

  static const methodShowAnswer = 'showAnswer';
  static const methodShowQuestion = 'showQuestion';
  static const methodRate = 'rate';
  static const methodTypedChanged = 'typedChanged';
  static const methodRetryAdvance = 'retryAdvance';
  static const methodRetryPresent = 'retryPresent';
  static const methodRequestUndo = 'requestUndo';
  static const methodReviewSettlement = 'reviewSettlement';
  static const methodReplayAudio = 'replayAudio';

  // ------------------------------------------------- argument / field names

  /// `openReviewer`'s argument; also the Want parameter the ability reads.
  static const argMediaRoot = 'mediaRoot';
  static const argPayloadJson = 'payloadJson';
  static const argSide = 'side';
  static const argName = 'name';
  static const argBase64 = 'base64';

  // ----------------------------------------------------- rating receipts (10)
  //
  // Receipt codes for the page's four rating buttons. They cross the channel
  // as plain strings, so every value is part of the wire contract with
  // `AnkiReviewerPage` — renaming one is a protocol change on both sides.
  //
  // A refusal used to be invisible: the page fired `rate` and nothing ever
  // came back, so every rejected click read on device as a dead button. The
  // page disables the buttons on tap and decides from this code whether to
  // re-enable them, show the completion row, or report a hard failure.
  // `advanceFailed` additionally swaps the row for an explicit "retry the
  // advance" entry, because its recovery re-runs the advance — never the
  // rating, which the scheduler already holds.

  static const receiptOk = 'ok';
  static const receiptOkComplete = 'ok_complete';
  static const receiptAnswerNotReady = 'answer_not_ready';
  static const receiptSchedulerBusy = 'scheduler_busy';
  static const receiptCardMismatch = 'card_mismatch';
  static const receiptSessionClosed = 'session_closed';
  static const receiptEngineError = 'engine_error';
  static const receiptSchedulerUnavailable = 'scheduler_unavailable';
  static const receiptNoCard = 'no_card';

  /// The rating itself committed, but moving the session to the next card
  /// threw. Retrying the ADVANCE is safe (the commit is deduped by mutation
  /// id); re-rating is not.
  static const receiptAdvanceFailed = 'advance_failed';

  // ----------------------------------------------------- ack type / fields
  //
  // The OHOS ack shape only. See the class doc for why the Android/iOS shape
  // is not unified with it. The four field names below are Dart-read map
  // keys; on the ArkTS side the same names live as `RenderAck` interface
  // members, which constants cannot express — the guard test needle-checks
  // the interface instead.

  /// The frame drew the requested face.
  static const ackTypeRenderComplete = 'renderComplete';

  /// The frame (or the session synthesising on its behalf) gave up.
  static const ackTypeRenderError = 'renderError';

  static const ackFieldType = 'type';
  static const ackFieldSide = 'side';
  static const ackFieldGeneration = 'generation';
  static const ackFieldStableCode = 'stableCode';

  // ------------------------------------------------------------ sides / themes

  static const sideQuestion = 'question';
  static const sideAnswer = 'answer';
  static const themeDay = 'day';
  static const themeNight = 'night';

  // ------------------------------------------------------------------ ratings
  //
  // Anki's four buttons. The page sends the label itself; the mapping to a
  // scheduler value stays on the Dart side (grades bridge), where the
  // buttons and the intervals they produce are defined together.

  static const ratingAgain = 'again';
  static const ratingHard = 'hard';
  static const ratingGood = 'good';
  static const ratingEasy = 'easy';

  // ------------------------------------------------------------- failure codes

  /// Synthesised by both sides when a present ended without any ack at all.
  /// The only stable code both sides literally produce, hence a scalar here;
  /// it is also a member of [recoverableCodes].
  static const renderTimeout = 'RENDER_TIMEOUT';

  /// Failure codes for which retrying the present cannot help (the card
  /// itself is unrenderable). Mirrored as `RECOVERABLE_CODES`/`FATAL_CODES`
  /// in the ArkTS protocol — the page classifies banners from these, so a
  /// one-sided edit changes which failures offer "exit only" on device.
  static const recoverableCodes = <String>{
    'RENDER_TIMEOUT',
    'RENDER_SUPERSEDED',
    'MATHJAX_ASSET_MISSING',
    'MATHJAX_TYPESET_FAILED',
    'SHELL_ASSET_MISSING',
    'FRAME_ASSET_MISSING',
    'WEBVIEW_MAIN_FRAME_ERROR',
    'SHELL_NOT_READY',
  };

  static const fatalCodes = <String>{
    'UNRENDERABLE_CARD',
    'UNRENDERABLE_TEMPLATE',
    'CARD_NOT_FOUND',
    'FATAL_RENDER_ERROR',
  };

  // ----------------------------------------------------------------- verdicts
  //
  // How the ability ends. Dart currently treats them as opaque (the stage
  // pops on any close), but they ride `terminateSelfWithResult` across the
  // seam and into `openReviewer`'s reply, so they are pinned here too.

  static const verdictEarlyExit = 'early_exit';
  static const verdictCompleted = 'completed';
}

/// The present payload the reviewer shell understands on every platform:
/// the ten fields both the Android/iOS view and the OHOS page consume.
///
/// `comparisonHtml` is passed through as-is (nullable) because the two
/// consumers normalise differently: the Android/iOS channel carries null
/// across the codec, while the OHOS path JSON-encodes and normalises to an
/// empty string in [ohosReviewerPayload]. Changing that here would change
/// what the frame script receives on one of the platforms.
Map<String, Object?> officialAnkiReviewerPayload({
  required OfficialAnkiRenderedCard card,
  required int generation,
  required bool showingAnswer,
  required bool dark,
  String? comparisonHtml,
}) {
  return <String, Object?>{
    'cardId': card.cardId,
    'generation': generation,
    'questionDisplayHtml': card.questionDisplayHtml,
    'answerDisplayHtml': card.answerDisplayHtml,
    'css': card.css,
    'theme': dark
        ? OfficialAnkiReviewerProtocol.themeNight
        : OfficialAnkiReviewerProtocol.themeDay,
    'comparisonHtml': comparisonHtml,
    'side': showingAnswer
        ? OfficialAnkiReviewerProtocol.sideAnswer
        : OfficialAnkiReviewerProtocol.sideQuestion,
    'templateOrdinal': card.templateOrdinal,
    'bodyClass': card.bodyClass,
  };
}

/// The OHOS present payload: the cross-platform ten plus the ArkTS-only
/// nine.
///
/// `typedVisible` is read by the ArkUI page, not by the frame.
/// `comparisonHtml` is the official engine's `compare_answer` result; the
/// frame substitutes it for `[[type:…]]` and never sees the raw keystrokes.
/// `mediaNames` is likewise ArkTS-only: the origin server evicts everything
/// except these when the present arrives, so a long session's memory holds
/// one card's media instead of every card's (P1/P2 on the work list).
/// `progressIndex`/`progressTotal` drive the native header's count and bar
/// (UI-4) and `debug` lets the page append stable codes to its status line
/// in debug builds only (UI-3) — the page has no other way to know.
/// `textZoom` carries the user's card text scale percentage (`100` = 1.0x),
/// `previewOnly` switches the page from 4-button rating chrome to 0-write
/// preview chrome, and `hasAudio`/`avHint` drive the manual audio replay
/// entry and non-fatal AV status line.
Map<String, Object?> ohosReviewerPayload({
  required OfficialAnkiRenderedCard card,
  required int generation,
  required bool showingAnswer,
  required bool dark,
  String? comparisonHtml,
  Iterable<String> mediaNames = const [],
  int? progressIndex,
  int? progressTotal,
  bool debug = false,
  int textZoom = 100,
  bool previewOnly = false,
  bool? hasAudio,
  String? avHint,
}) {
  final effectiveHasAudio = hasAudio ??
      (showingAnswer
          ? card.answerAvTags.isNotEmpty
          : card.questionAvTags.isNotEmpty);
  return <String, Object?>{
    ...officialAnkiReviewerPayload(
      card: card,
      generation: generation,
      showingAnswer: showingAnswer,
      dark: dark,
      comparisonHtml: comparisonHtml ?? '',
    ),
    'typedVisible': card.typedAnswer != null,
    'mediaNames': mediaNames.toList(),
    'progressIndex': progressIndex,
    'progressTotal': progressTotal,
    'debug': debug,
    'textZoom': textZoom,
    'previewOnly': previewOnly,
    'hasAudio': effectiveHasAudio,
    'avHint': avHint ?? '',
  };
}
