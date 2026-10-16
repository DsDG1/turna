// Copyright (c) 2024 Turna. All rights reserved.
//
// The ArkTS half of the Dart↔ArkTS reviewer wire vocabulary.
//
// Every constant here crosses the MethodChannel 'me.dsdogs.turna/
// official_anki_reviewer' (or rides one of its replies). The Dart twin is
// lib/application/anki_official/render/official_anki_reviewer_protocol.dart:
// for every `export const` here there is a `static const` there under the
// camelCase spelling of the same name (RECEIPT_OK ↔ receiptOk), and
// test/application/anki_official/official_anki_reviewer_protocol_guard_test.dart
// parses both sources and fails on any name or value that does not pair up.
//
// Adding a constant on one side only is a guard failure; one-sided constants
// are legal only through that test's explicit allowed-difference lists.
// Values must stay literal strings (no computed constants): the guard reads
// this file as text, and so does any future archaeologist.

/// Served by this plugin; declared in AnkiReviewerPlugin.ets's registration.
export const CHANNEL_NAME: string = 'me.dsdogs.turna/official_anki_reviewer';

// ------------------------------------------------ Dart → ArkTS method names
// (dispatched in AnkiReviewerPlugin.ets; invoked from
// OfficialAnkiReviewerChannel and the probe on the Dart side)

export const METHOD_OPEN_REVIEWER: string = 'openReviewer';
export const METHOD_PRESENT_REVIEWER: string = 'presentReviewer';
export const METHOD_CACHE_REVIEWER_MEDIA: string = 'cacheReviewerMedia';
export const METHOD_REVIEWER_LAST_ACK: string = 'reviewerLastAck';
export const METHOD_AWAIT_REVIEWER_READY: string = 'awaitReviewerReady';
export const METHOD_NOTIFY_REVIEWER_FAILURE: string = 'notifyReviewerFailure';
export const METHOD_PROBE_REVIEWER_CAPABILITIES: string = 'probeReviewerCapabilities';
export const METHOD_PROBE_REVIEWER_ASSETS: string = 'probeReviewerAssets';

// ------------------------------------------------ ArkTS → Dart method names
// (called from AnkiReviewerBridge.ets; dispatched in
// OfficialAnkiReviewerChannel.bindOutbound on the Dart side)

export const METHOD_SHOW_ANSWER: string = 'showAnswer';
export const METHOD_RATE: string = 'rate';
export const METHOD_TYPED_CHANGED: string = 'typedChanged';
export const METHOD_RETRY_ADVANCE: string = 'retryAdvance';
export const METHOD_RETRY_PRESENT: string = 'retryPresent';
export const METHOD_REQUEST_UNDO: string = 'requestUndo';
export const METHOD_REVIEW_SETTLEMENT: string = 'reviewSettlement';

// --------------------------------------------------------- argument names

/// openReviewer's argument; also the Want parameter AnkiReviewerAbility reads.
export const ARG_MEDIA_ROOT: string = 'mediaRoot';
export const ARG_PAYLOAD_JSON: string = 'payloadJson';
export const ARG_SIDE: string = 'side';
export const ARG_NAME: string = 'name';
export const ARG_BASE64: string = 'base64';

// ------------------------------------------------------- rating receipts (10)
//
// Receipt codes for the four rating buttons; the page's button interlock
// decides from these whether to re-arm, hold, or swap in the completion row.
// 'advance_failed' additionally swaps the row for the explicit "retry the
// advance" entry — its recovery re-runs the advance, never the rating.

export const RECEIPT_OK: string = 'ok';
export const RECEIPT_OK_COMPLETE: string = 'ok_complete';
export const RECEIPT_ANSWER_NOT_READY: string = 'answer_not_ready';
export const RECEIPT_SCHEDULER_BUSY: string = 'scheduler_busy';
export const RECEIPT_CARD_MISMATCH: string = 'card_mismatch';
export const RECEIPT_SESSION_CLOSED: string = 'session_closed';
export const RECEIPT_ENGINE_ERROR: string = 'engine_error';
export const RECEIPT_SCHEDULER_UNAVAILABLE: string = 'scheduler_unavailable';
export const RECEIPT_NO_CARD: string = 'no_card';
export const RECEIPT_ADVANCE_FAILED: string = 'advance_failed';

// ------------------------------------------------------------- ack type values
//
// The OHOS ack shape only: {type|stableCode, side, generation}. The Android /
// iOS ack shape ({ok, code, generation, side, height, recoverable}) is a
// separate, deliberately ununified contract — see the Dart protocol module's
// doc. The ack FIELD names live as the RenderAck interface members in
// AnkiReviewerSession.ets, which constants cannot express; the guard test
// needle-checks the interface instead.

export const ACK_TYPE_RENDER_COMPLETE: string = 'renderComplete';
export const ACK_TYPE_RENDER_ERROR: string = 'renderError';

// ------------------------------------------------------------- sides / themes

export const SIDE_QUESTION: string = 'question';
export const SIDE_ANSWER: string = 'answer';
export const THEME_DAY: string = 'day';
export const THEME_NIGHT: string = 'night';

// ------------------------------------------------------------------ ratings

export const RATING_AGAIN: string = 'again';
export const RATING_HARD: string = 'hard';
export const RATING_GOOD: string = 'good';
export const RATING_EASY: string = 'easy';

// ------------------------------------------------------------- failure codes

/// Synthesised by both sides when a present ended without any ack at all.
export const RENDER_TIMEOUT: string = 'RENDER_TIMEOUT';

/// ArkTS-only fallback when a failure report carries no code at all. Dart
/// never compares this value (it falls to the fatal default), so it has no
/// Dart twin — it is listed in the guard test's allowed-difference set.
export const RENDER_ERROR: string = 'RENDER_ERROR';

/// Failure codes for which retrying the present cannot help. Mirrors
/// OfficialAnkiReviewerProtocol.recoverableCodes / fatalCodes on the Dart
/// side; the page classifies its error banners from these, so a one-sided
/// edit changes which failures offer "exit only" on device.
export const RECOVERABLE_CODES: Array<string> = [
  'RENDER_TIMEOUT',
  'RENDER_SUPERSEDED',
  'MATHJAX_ASSET_MISSING',
  'MATHJAX_TYPESET_FAILED',
  'SHELL_ASSET_MISSING',
  'FRAME_ASSET_MISSING',
  'WEBVIEW_MAIN_FRAME_ERROR',
  'SHELL_NOT_READY',
];

export const FATAL_CODES: Array<string> = [
  'UNRENDERABLE_CARD',
  'UNRENDERABLE_TEMPLATE',
  'CARD_NOT_FOUND',
  'FATAL_RENDER_ERROR',
];

// ------------------------------------------------------------------- verdicts
//
// How the ability ends via terminateSelfWithResult; Dart treats them as
// opaque but they ride openReviewer's reply, so they are pinned.

export const VERDICT_EARLY_EXIT: string = 'early_exit';
export const VERDICT_COMPLETED: string = 'completed';
