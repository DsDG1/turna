// Copyright (c) 2024 Turna. All rights reserved.
//
// The HarmonyOS reviewer page: route E's delivery of ADR 0050 §6 step 5b.
//
// Dart does not create a PlatformView on this platform (§3.1 rejected A/B/D on
// device receipts), so this page owns everything a reviewer needs on screen: the
// `Web` that renders the card, the typed-answer field, the flip control and the
// four rating buttons. What it deliberately does *not* own is the review logic —
// every state transition goes back to Dart and comes back as a new `present`
// payload, so the scheduling, the comparison and the ledger stay in one place.
//
// The typed answer is native here, and that is not a HarmonyOS workaround: on
// every platform the Web only ever receives `comparisonHtml` (the official
// engine's diff) and renders `[[type:…]]` as an empty placeholder span, so the
// input has never lived inside the frame. See `card-frame.js`'s `applyTyped`.

import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AnkiOriginServer, isShellUrl } from './AnkiOriginServer';
import { AnkiReviewerBridge } from './AnkiReviewerBridge';
import {
  ACK_TYPE_RENDER_COMPLETE,
  ACK_TYPE_RENDER_ERROR,
  RENDER_ERROR,
  RENDER_TIMEOUT,
  SIDE_ANSWER,
  THEME_DAY,
} from './AnkiReviewerProtocol';

const SHELL_URL: string = 'https://anki.local/assets/reviewer.html';
const ORIGIN_PREFIX: string = 'https://anki.local/';

/// How long a `present` may take before the page stops believing the frame will
/// answer. Mirrors `ackTimeoutMs()` on the Web side; a page that waited forever
/// would leave the flip button spinning with no way to tell a slow card from a
/// dead frame.
const PRESENT_TIMEOUT_MS: number = 12000;

/// The frame's own ack, carried back verbatim.
///
/// Declared rather than passed as `Record<string, object>`: ArkTS rejects
/// untyped object literals (`arkts-no-untyped-obj-literals`), and an ack with no
/// declared shape is also an ack whose fields nothing checks. Every field the
/// frame may send is listed, and every one is optional because the frame is
/// card-authored script — an ack is whatever it chose to say, and the two fields
/// actually branched on are `type` and `stableCode`.
export interface RenderAck {
  ok?: boolean;
  type?: string;
  stableCode?: string;
  generation?: number;
  cardId?: number;
  height?: number;
  nonce?: number;
  seq?: number;
  side?: string;
}

/// What the payload's present carries besides the card faces. Fields arrive
/// progressively across the wiring batches; all stay optional because the
/// frame is card-authored script and the payload is JSON text.
interface ReviewerPresentPayload {
  typedVisible?: boolean;
  cardId?: number;
  generation?: number;
  side?: string;
  theme?: string;
  progressIndex?: number;
  progressTotal?: number;
  debug?: boolean;
  mediaNames?: Array<string>;
}

/// One snapshot of the native chrome around the Web: what the bottom row
/// should show, what the progress bar should say, which theme to follow.
///
/// `answerLanded` is the timing contract with the rating row (B4): it turns
/// true only when the ANSWER face's own render ack came back, never when the
/// present call starts — the four buttons used to appear while the answer
/// was still on its way, and a quick tap scored the card against the
/// question face the learner was still looking at.
///
/// `presentPending` is true from the present call until that ack; the page
/// shows its loading hint and disables flip/rating entries meanwhile.
export interface ReviewerChromeState {
  presentPending: boolean;
  answerLanded: boolean;
  typedVisible: boolean;
  cardId: number;
  theme: string;
  progressIndex: number;
  progressTotal: number;
  debug: boolean;
}

type ChromeListener = (state: ReviewerChromeState) => void;
type FailureListener = (code: string) => void;

function chromeState(
  presentPending: boolean,
  answerLanded: boolean,
  typedVisible: boolean,
  cardId: number,
  theme: string,
  progressIndex: number,
  progressTotal: number,
  debug: boolean,
): ReviewerChromeState {
  const state: ReviewerChromeState = {
    presentPending: presentPending,
    answerLanded: answerLanded,
    typedVisible: typedVisible,
    cardId: cardId,
    theme: theme,
    progressIndex: progressIndex,
    progressTotal: progressTotal,
    debug: debug,
  };
  return state;
}

/// Poll cadence for reading `__turnaLastRender`, mirroring the Android
/// client's `APPLY_DELAY_MS`.
const POLL_DELAY_MS: number = 50;

function failedAck(type: string, stableCode: string): RenderAck {
  const ack: RenderAck = { ok: false, type: type, stableCode: stableCode };
  return ack;
}

/// Polls `__turnaLastRender` as a `|`-joined scalar row rather than as JSON:
/// `runJavaScript` resolves with the JSON encoding of the script's value, and
/// a JSON string full of escaped quotes cannot be unescaped here — ArkTS
/// `replace` substitutes only the first match, so the ported-from-Android
/// unwrap left most escapes in place and every poll failed to parse what the
/// frame had plainly published (12 s timeouts on faces that were on screen).
/// None of the seven fields can contain `|`, quotes or backslashes, so the
/// encoded result carries nothing but its outer quotes.
const POLL_EXPRESSION: string =
  '(function(){ var a = window.__turnaLastRender; if (!a) { return ""; } ' +
  'return [a.type, a.generation, a.side, a.stableCode, a.height, a.cardId, a.ok].join("|"); })()';

function unwrapEvalString(value: string): string {
  const raw: string = value.trim();
  if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
    return raw.substring(1, raw.length - 1);
  }
  if (raw === 'null') {
    return '';
  }
  return raw;
}

function parseAck(raw: string): RenderAck {
  if (raw.length === 0) {
    return failedAck(ACK_TYPE_RENDER_ERROR, 'FRAME_ACK_EMPTY');
  }
  const parts: Array<string> = raw.split('|');
  const ack: RenderAck = {};
  ack.type = parts[0] ?? '';
  const generation = Number(parts[1] ?? '0');
  if (!Number.isNaN(generation)) {
    ack.generation = generation;
  }
  ack.side = parts[2] ?? '';
  ack.stableCode = parts[3] ?? '';
  const height = Number(parts[4] ?? '0');
  if (!Number.isNaN(height)) {
    ack.height = height;
  }
  const cardId = Number(parts[5] ?? '0');
  if (!Number.isNaN(cardId)) {
    ack.cardId = cardId;
  }
  ack.ok = parts[6] === 'true';
  return ack;
}

export class AnkiReviewerSession {
  private server: AnkiOriginServer;
  private bridge: AnkiReviewerBridge;
  private web: webview.WebviewController | undefined = undefined;
  private answerShown: boolean = false;
  private shellReady: boolean = false;
  private chrome: ChromeListener | undefined = undefined;
  private failure: FailureListener | undefined = undefined;
  private chromeTheme: string = THEME_DAY;
  private chromeProgressIndex: number = 0;
  private chromeProgressTotal: number = 0;
  private chromeDebug: boolean = false;

  constructor(mediaRoot: string) {
    this.server = new AnkiOriginServer(mediaRoot);
    this.bridge = new AnkiReviewerBridge();
  }

  /// The bridge the ArkUI buttons call. It is its own type rather than a field
  /// on this session so the page's ArkTS build cannot reach the fields ArkUI
  /// hands to a component.
  public channel(): AnkiReviewerBridge {
    return this.bridge;
  }

  public origin(): AnkiOriginServer {
    return this.server;
  }

  public isShellReady(): boolean {
    return this.shellReady && this.web !== undefined;
  }

  public markShellReady(): void {
    this.shellReady = true;
  }

  public setChromeListener(listener: ChromeListener | undefined): void {
    this.chrome = listener;
  }

  /// B2: render failures reported here land on the page as a banner with
  /// retry/exit entries. Set by the page; called both from the present ack
  /// path below (failures the frame itself reported) and from the plugin
  /// (`notifyReviewerFailure`) for failures only Dart could see.
  public setFailureListener(listener: FailureListener | undefined): void {
    this.failure = listener;
  }

  public notifyFailure(code: string): void {
    const listener: FailureListener | undefined = this.failure;
    if (listener === undefined) {
      return;
    }
    listener(code);
  }

  private notifyChrome(state: ReviewerChromeState): void {
    const listener: ChromeListener | undefined = this.chrome;
    if (listener === undefined) {
      return;
    }
    listener(state);
  }

  /// Warms the assets. The shell is NOT loaded here: the Web's own initial
  /// `src` is the shell URL, so the kernel drives that load. A `loadUrl` from
  /// here has to be timed against the initial load and every timing tried on
  /// device lost the race one way or another — issued during the initial
  /// navigation it is silently swallowed; issued after `about:blank` settles it
  /// depends on an end event that only fires when a navigation follows. The
  /// contract is instead a head start: called from `aboutToAppear`, i.e. before
  /// the Web builds and asks for the shell, the preload wins in practice (and
  /// the startup probes have already warmed the rawfile pages for the process).
  public start(
    context: common.UIAbilityContext,
    controller: webview.WebviewController,
  ): Promise<string> {
    this.web = controller;
    this.server.preloadSync(context);
    return this.server.preload(context);
  }

  /// One card, one side. Resolves with the frame's own ack so the caller can
  /// distinguish "rendered" from "gave up", which is the difference between
  /// showing the answer and silently advancing a card that never drew.
  ///
  /// The ack is POLLED, not pushed: `reviewer.js` publishes its latest outcome
  /// to `window.__turnaLastRender` (its `publishDebug`), and the Android client
  /// reads that field in a loop until it says `renderComplete` or
  /// `renderError`. There is no bridge message for it — an earlier draft of
  /// this file waited for one that nothing ever sends, and every present ended
  /// in RENDER_TIMEOUT while the card sat happily drawn on screen.
  ///
  /// The poll only settles on an ack whose `generation` matches this payload
  /// (B7): the frame clears its published ack at the start of a present, but
  /// if that clear ever loses to the poll — a slow expression queue, a page
  /// that was mid-present — accepting the stale row hands Dart somebody
  /// else's result while the controller keeps waiting on a generation
  /// nothing will answer. Generation, not cardId, is the discriminator:
  /// error acks legitimately carry no card.
  public present(payloadJson: string, side: string): Promise<RenderAck> {
    const controller: webview.WebviewController | undefined = this.web;
    if (controller === undefined) {
      return Promise.resolve(failedAck(ACK_TYPE_RENDER_ERROR, 'REVIEWER_WEB_ABSENT'));
    }
    this.answerShown = side === SIDE_ANSWER;
    let typedVisible: boolean = false;
    let cardId: number = 0;
    let generation: number = 0;
    let theme: string = this.chromeTheme;
    let progressIndex: number = this.chromeProgressIndex;
    let progressTotal: number = this.chromeProgressTotal;
    let debug: boolean = this.chromeDebug;
    let mediaNames: Array<string> = [];
    try {
      const parsed: ReviewerPresentPayload = JSON.parse(payloadJson) as ReviewerPresentPayload;
      typedVisible = parsed.typedVisible === true;
      const parsedCard: number | undefined = parsed.cardId;
      if (parsedCard !== undefined) {
        cardId = parsedCard;
      }
      const parsedGeneration: number | undefined = parsed.generation;
      if (parsedGeneration !== undefined) {
        generation = parsedGeneration;
      }
      const parsedTheme: string | undefined = parsed.theme;
      if (parsedTheme !== undefined && parsedTheme.length > 0) {
        theme = parsedTheme;
      }
      const parsedIndex: number | undefined = parsed.progressIndex;
      if (parsedIndex !== undefined) {
        progressIndex = parsedIndex;
      }
      const parsedTotal: number | undefined = parsed.progressTotal;
      if (parsedTotal !== undefined) {
        progressTotal = parsedTotal;
      }
      debug = parsed.debug === true;
      const parsedNames: Array<string> | undefined = parsed.mediaNames;
      if (parsedNames !== undefined) {
        mediaNames = parsedNames;
      }
    } catch (e) {
      typedVisible = false;
      cardId = 0;
      generation = 0;
    }
    this.chromeTheme = theme;
    this.chromeProgressIndex = progressIndex;
    this.chromeProgressTotal = progressTotal;
    this.chromeDebug = debug;
    // P1: the arriving card's media replaces everyone else's. Dart has
    // already pushed these names; everything still cached belongs to the
    // previous card and is dead weight from here on.
    this.server.evictExcept(mediaNames);
    this.bridge.setTypedVisible(typedVisible);
    // B4: the chrome learns the answer face landed only from the ack below.
    // Announcing it here is exactly the defect the work list recorded — the
    // rating row appeared while the answer was still crossing the channel,
    // and a quick tap scored the card against the question still on screen.
    this.notifyChrome(chromeState(
      true,
      false,
      typedVisible,
      cardId,
      theme,
      progressIndex,
      progressTotal,
      debug,
    ));
    const expression: string =
      'window.OfficialReviewer.present(' + payloadJson + ',' + JSON.stringify(side) + ')';
    return new Promise<RenderAck>((resolve) => {
      let settled: boolean = false;
      const finish = (ack: RenderAck): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (ack.type === ACK_TYPE_RENDER_ERROR) {
          this.notifyChrome(chromeState(
            false,
            false,
            typedVisible,
            cardId,
            theme,
            progressIndex,
            progressTotal,
            debug,
          ));
          this.notifyFailure(ack.stableCode ?? RENDER_ERROR);
        } else {
          this.notifyChrome(chromeState(
            false,
            this.answerShown,
            typedVisible,
            cardId,
            theme,
            progressIndex,
            progressTotal,
            debug,
          ));
        }
        resolve(ack);
      };
      const deadline: number = Date.now() + PRESENT_TIMEOUT_MS;
      const poll = (): void => {
        controller
          .runJavaScript(POLL_EXPRESSION)
          .then((value: string): void => {
            const raw: string = unwrapEvalString(value);
            if (raw.length > 0) {
              const type: string = raw.split('|')[0] ?? '';
              if (type === ACK_TYPE_RENDER_COMPLETE || type === ACK_TYPE_RENDER_ERROR) {
                const ack: RenderAck = parseAck(raw);
                const ackGeneration: number | undefined = ack.generation;
                if (ackGeneration === undefined || ackGeneration === generation) {
                  finish(ack);
                  return;
                }
                // A stale generation: the published row belongs to an
                // earlier payload — keep polling.
              }
              // `cardAccepted` / `frameReady` are mid-present and must not
              // settle anything, same as on Android; keep polling.
            }
            if (Date.now() >= deadline) {
              finish(failedAck(ACK_TYPE_RENDER_ERROR, RENDER_TIMEOUT));
              return;
            }
            setTimeout(poll, POLL_DELAY_MS);
          })
          .catch((e: BusinessError): void => {
            finish(failedAck(ACK_TYPE_RENDER_ERROR, 'POLL_FAILED_' + String(e.code)));
          });
      };
      controller
        .runJavaScript(expression)
        .catch((e: BusinessError): void => {
          finish(failedAck(ACK_TYPE_RENDER_ERROR, 'RUN_JAVASCRIPT_FAILED_' + String(e.code)));
        });
      setTimeout(poll, POLL_DELAY_MS);
    });
  }

  /// The `[[type:…]]` placeholder is rendered by the frame, and whether this
  /// card has one at all is a property of the card, not of the platform — so the
  /// page asks Dart rather than guessing from the HTML.
  public setTypedVisible(visible: boolean): void {
    this.bridge.setTypedVisible(visible);
  }
}

export function interceptFor(
  session: AnkiReviewerSession,
): (event: OnInterceptRequestEvent) => WebResourceResponse {
  return (event: OnInterceptRequestEvent): WebResourceResponse => {
    const url: string = event.request.getRequestUrl();
    if (!url.startsWith(ORIGIN_PREFIX) && !isShellUrl(url)) {
      // Never null: null means "let the kernel load it", and `anki.local` does
      // not resolve, so that turns a policy decision into a DNS failure.
      const refused: WebResourceResponse = new WebResourceResponse();
      refused.setResponseMimeType('text/plain');
      refused.setResponseEncoding('utf-8');
      refused.setResponseData('');
      refused.setResponseCode(403);
      refused.setReasonMessage('foreign_origin');
      return refused;
    }
    return session.origin().respond(
      url,
      event.request.getRequestMethod(),
      event.request.getRequestHeader(),
    );
  };
}

export { SHELL_URL };