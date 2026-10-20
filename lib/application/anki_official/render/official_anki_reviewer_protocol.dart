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

  /// Closes a reviewer that was opened speculatively (P0-1 warm-up) without a
  /// card ever being presented.
  ///
  /// Distinct from the page-initiated calls above: this one is
  /// Dart-initiated and must work even before the ability has created its
  /// session — the whole point of a warm-up is that it starts before anything
  /// else is ready, so the cancel path has to survive the "not open yet" race
  /// by remembering the request rather than dropping it.
  static const methodCloseReviewer = 'closeReviewer';

  // ------------------------------------------- ArkTS → Dart method names
  // (AnkiReviewerBridge.ets calls these back; the switch lives in
  // OfficialAnkiReviewerChannel.bindOutbound)

  static const methodShowAnswer = 'showAnswer';
  static const methodShowQuestion = 'showQuestion';
  static const methodRate = 'rate';
  static const methodTypedChanged = 'typedChanged';
  static const methodRetryAdvance = 'retryAdvance';
  static const methodRetryPresent = 'retryPresent';
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
  // Receipt codes for the page's rating buttons. They cross the channel
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

  /// The chrome theme token the ArkUI page paints its own bars with.
  ///
  /// Distinct from [themeDay]/[themeNight] on purpose: `theme` is read by the
  /// card frame (which only knows day/night, since it drives the card's own
  /// CSS), while these four name the Flutter theme variant the page sits on.
  /// Turna ships four variants (`lib/core/theme.dart`), and collapsing the
  /// two high-contrast ones into plain day/night is exactly the gap this
  /// field closes — the native chrome used to lose high contrast entirely.
  static const chromeLight = 'light';
  static const chromeDark = 'dark';
  static const chromeHighContrastLight = 'highContrastLight';
  static const chromeHighContrastDark = 'highContrastDark';

  /// Resolves the four-variant chrome token from the two inputs the Flutter
  /// side actually has: app brightness and the accessibility high-contrast
  /// flag.
  ///
  /// One mapping, two callers — the reviewer stage (which paints the chrome
  /// on every rebind) and the page's pre-frame adoption path (which presents
  /// the first card before that stage exists). Two copies would let the first
  /// card arrive on a different palette than the one the stage would pick a
  /// frame later, which is the visible flash UI-15 was about.
  static String chromeThemeFor({
    required bool dark,
    required bool highContrast,
  }) {
    if (highContrast) {
      return dark ? chromeHighContrastDark : chromeHighContrastLight;
    }
    return dark ? chromeDark : chromeLight;
  }

  /// Field names the ArkTS page reads off the present payload for its own
  /// chrome (not for the card frame). Pinned here so a rename cannot land on
  /// one side only.
  static const payloadSourceProgress = 'sourceProgress';
  static const payloadCanRedo = 'canRedo';
  static const payloadCanMutate = 'canMutate';
  static const payloadChromeTheme = 'chromeTheme';
  static const payloadAutoComplete = 'autoComplete';

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

  /// The OHOS present body was not JSON, or it carried no numeric generation.
  /// ArkTS refuses it before `OfficialReviewer.present` runs, so a stale
  /// generation-0 ack cannot settle the card. Retry sends the body again.
  static const presentPayloadInvalid = 'PRESENT_PAYLOAD_INVALID';

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
    'PRESENT_PAYLOAD_INVALID',
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

  /// The reviewer was opened speculatively (P0-1 warm-up) and closed before
  /// any card arrived — the batch never loaded, so this is not a learner
  /// exit and must not settle a session.
  static const verdictWarmCanceled = 'warm_canceled';
}

/// The chrome state the page owns and the native page cannot derive.
///
/// Every field has an Android counterpart on `_AnkiSessionToolbar` /
/// `ReviewProgressHeader`; the point of the record is that a new chrome value
/// is one field here plus one field in the payload, instead of a fifth set of
/// positional parameters threaded through five widgets.
typedef OfficialReviewerChromeSnapshot = ({
  /// `currentIndex+1/targets.length · deckName` during Review All, else null.
  /// Same string Android renders in the toolbar badge.
  String? sourceProgress,

  /// `ReviewSessionController.canRedo` — there is an undone receipt to replay.
  bool canRedo,

  /// `!isLocked && !isComplete` — the queue may be mutated right now.
  bool canMutate,

  /// Whether the native page may close itself the moment the queue finishes
  /// (UI-16).
  ///
  /// True only for a single-source session. Under Review All a source can
  /// finish while more sources remain, and the next source re-attaches to the
  /// *same* ability (same `mediaRoot` → `onNewWant` reuses the session); an
  /// auto-close timer armed by the finished source would then tear down the
  /// page the next source is already using. Review All keeps the explicit
  /// 「完成」 button; single-source sessions hand off automatically so the
  /// learner lands straight on Flutter's `UnifiedReviewCompletion` — the same
  /// completion screen Android shows.
  bool autoComplete,
});

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
/// `previewOnly` switches the page from rating chrome to 0-write
/// preview chrome, and `hasAudio`/`avHint` drive the manual audio replay
/// entry and non-fatal AV status line.
///
/// `sourceProgress`/`canRedo`/`canMutate` are the three chrome-state values
/// Android reads straight off `_AnkiSessionToolbar` (`controller.canRedo`,
/// `!controller.isLocked && !controller.isComplete`, and the
/// `currentIndex/targets.length · deckName` badge). The native page has no
/// controller, so they have to ride the payload; before this they were
/// simply absent — the three queue buttons looked live with no undo history,
/// and Review All never said which deck it was in.
///
/// `chromeTheme` names the Flutter theme variant (`light`/`dark`/
/// `highContrastLight`/`highContrastDark`). `theme` stays day/night because
/// the card frame only understands those two — collapsing the high-contrast
/// variants into day/night is the gap this field closes.
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
  String? sourceProgress,
  bool canRedo = false,
  bool canMutate = false,
  bool autoComplete = false,
  String? chromeTheme,
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
    OfficialAnkiReviewerProtocol.payloadSourceProgress: sourceProgress ?? '',
    OfficialAnkiReviewerProtocol.payloadCanRedo: canRedo,
    OfficialAnkiReviewerProtocol.payloadCanMutate: canMutate,
    OfficialAnkiReviewerProtocol.payloadAutoComplete: autoComplete,
    OfficialAnkiReviewerProtocol.payloadChromeTheme:
        chromeTheme ?? (dark ? 'dark' : 'light'),
  };
}
