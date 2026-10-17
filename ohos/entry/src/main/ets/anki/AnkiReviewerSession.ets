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
  PRESENT_PAYLOAD_INVALID,
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
  textZoom?: number;
  previewOnly?: boolean;
  hasAudio?: boolean;
  avHint?: string;
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
  textZoom: number;
  previewOnly: boolean;
  hasAudio: boolean;
  avHint: string;
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
  textZoom: number,
  previewOnly: boolean,
  hasAudio: boolean,
  avHint: string,
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
    textZoom: textZoom,
    previewOnly: previewOnly,
    hasAudio: hasAudio,
    avHint: avHint,
  };
  return state;
}

function failedAck(type: string, stableCode: string): RenderAck {
  const ack: RenderAck = { ok: false, type: type, stableCode: stableCode };
  return ack;
}

/// One-shot read of `__turnaLastRender` as a `|`-joined scalar row rather than
/// as JSON. `runJavaScript` resolves with the JSON encoding of the script's
/// value, and a JSON string full of escaped quotes cannot be unescaped here —
/// ArkTS `replace` substitutes only the first match, so the ported-from-Android
/// unwrap left most escapes in place and every read failed to parse what the
/// frame had plainly published (12 s timeouts on faces that were on screen).
/// None of the seven fields can contain `|`, quotes or backslashes, so the
/// encoded result carries nothing but its outer quotes.
///
/// The live path is the `TurnaOhosReviewer.onAck` push. This expression runs
/// only when that push has not settled the present by the timeout.
const READ_ACK_EXPRESSION: string =
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
  const generationText: string = parts[1] ?? '';
  if (generationText.length > 0) {
    const generation = Number(generationText);
    if (!Number.isNaN(generation)) {
      ack.generation = generation;
    }
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

/// Returns the payload only when it is JSON and names a numeric generation.
///
/// A missing or non-numeric generation used to fall through as 0, and the
/// poll then treated an ack with no generation as this present. The body is
/// not injected in that case.
function parsePresentPayload(payloadJson: string): ReviewerPresentPayload | undefined {
  try {
    const parsed: ReviewerPresentPayload = JSON.parse(payloadJson) as ReviewerPresentPayload;
    const generation: number | undefined = parsed.generation;
    if (generation === undefined || Number.isNaN(generation)) {
      return undefined;
    }
    return parsed;
  } catch (e) {
    // A corrupt channel body is refused before it reaches the frame.
    return undefined;
  }
}

export class AnkiReviewerSession {
  private server: AnkiOriginServer;
  private bridge: AnkiReviewerBridge;
  private web: webview.WebviewController | undefined = undefined;
  private answerShown: boolean = false;
  private shellReady: boolean = false;
  private chrome: ChromeListener | undefined = undefined;
  private failure: FailureListener | undefined = undefined;
  private cancel: (() => void) | undefined = undefined;
  private chromeTheme: string = THEME_DAY;
  private chromeProgressIndex: number = 0;
  private chromeProgressTotal: number = 0;
  private chromeDebug: boolean = false;
  private chromeTextZoom: number = 100;
  private chromePreviewOnly: boolean = false;
  private shellReadyHook: (() => void) | undefined = undefined;
  private pushedAck: ((row: string) => void) | undefined = undefined;
  private ackSerial: number = 0;

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

  public setShellReadyHook(hook: () => void): void {
    this.shellReadyHook = hook;
  }

  public markShellReady(): void {
    this.shellReady = true;
    // Pre-build the card iframe before the first present arrives. Issued before
    // `hook()` on purpose: the hook releases Dart's `waitUntilReady`, which
    // presents immediately, and ArkWeb runs `runJavaScript` calls in issue
    // order — warming afterwards would let the present's injection queue ahead
    // of the warm-up it is supposed to benefit from.
    //
    // Best-effort by design. An older shell has no `warmFrame`, and a failed
    // warm-up only means the first card pays the cold iframe load it paid
    // before this existed.
    this.web?.runJavaScript(
      'window.OfficialReviewer && window.OfficialReviewer.warmFrame && window.OfficialReviewer.warmFrame()'
    ).catch((_e: BusinessError): void => {
      // No shell method or no window: documented fallback, never a failure.
    });
    const hook: (() => void) | undefined = this.shellReadyHook;
    if (hook !== undefined) {
      hook();
    }
  }

  /// Terminal ack pushed by `reviewer.js` through `TurnaOhosReviewer.onAck`.
  /// Ignored when no present is waiting, or when the row's generation is not
  /// the one this present injected.
  public acceptPushedAck(row: string): void {
    const listener: ((row: string) => void) | undefined = this.pushedAck;
    if (listener === undefined) {
      return;
    }
    listener(row);
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

  /// P0-1: the page installs this so a warm-up can be abandoned before any
  /// card arrives. No listener means no page to close — the request is then
  /// dropped, which is the honest outcome.
  public setCancelListener(listener: (() => void) | undefined): void {
    this.cancel = listener;
  }

  public requestCancel(): void {
    const listener: (() => void) | undefined = this.cancel;
    if (listener !== undefined) {
      listener();
    }
  }

  /// A present body that cannot name its generation never reaches the frame.
  private refusePayload(): Promise<RenderAck> {
    this.notifyChrome(chromeState(
      false,
      false,
      false,
      0,
      this.chromeTheme,
      this.chromeProgressIndex,
      this.chromeProgressTotal,
      this.chromeDebug,
      this.chromeTextZoom,
      this.chromePreviewOnly,
      false,
      '',
    ));
    this.notifyFailure(PRESENT_PAYLOAD_INVALID);
    return Promise.resolve(failedAck(ACK_TYPE_RENDER_ERROR, PRESENT_PAYLOAD_INVALID));
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
  /// The ack is pushed: `reviewer.js` still writes `window.__turnaLastRender`
  /// (Android polls that field) and, when `TurnaOhosReviewer.onAck` exists,
  /// calls it once with the terminal row. An earlier draft waited for a bridge
  /// message nothing sent, and every present ended in RENDER_TIMEOUT while the
  /// card sat drawn on screen. If the push never arrives, the timeout reads
  /// `__turnaLastRender` once and then gives up — it does not loop.
  ///
  /// A present only settles on an ack whose `generation` equals this payload's
  /// (B7). An ack with no generation does not match: an empty field used to
  /// parse as 0, and a payload that failed to parse used to present anyway
  /// with generation 0, so the previous card's row could settle this one.
  /// Generation, not cardId, is the discriminator: error acks legitimately
  /// carry no card.
  public present(payloadJson: string, side: string): Promise<RenderAck> {
    const controller: webview.WebviewController | undefined = this.web;
    if (controller === undefined) {
      return Promise.resolve(failedAck(ACK_TYPE_RENDER_ERROR, 'REVIEWER_WEB_ABSENT'));
    }
    const parsed: ReviewerPresentPayload | undefined = parsePresentPayload(payloadJson);
    if (parsed === undefined) {
      return this.refusePayload();
    }
    const generationValue: number | undefined = parsed.generation;
    if (generationValue === undefined || Number.isNaN(generationValue)) {
      return this.refusePayload();
    }
    const generation: number = generationValue;
    this.answerShown = side === SIDE_ANSWER;
    let typedVisible: boolean = false;
    let cardId: number = 0;
    let theme: string = this.chromeTheme;
    let progressIndex: number = this.chromeProgressIndex;
    let progressTotal: number = this.chromeProgressTotal;
    let debug: boolean = this.chromeDebug;
    let textZoom: number = this.chromeTextZoom;
    let previewOnly: boolean = this.chromePreviewOnly;
    let hasAudio: boolean = false;
    let avHint: string = '';
    let mediaNames: Array<string> = [];
    typedVisible = parsed.typedVisible === true;
    const parsedCard: number | undefined = parsed.cardId;
    if (parsedCard !== undefined) {
      cardId = parsedCard;
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
    const parsedZoom: number | undefined = parsed.textZoom;
    if (parsedZoom !== undefined && parsedZoom > 0) {
      textZoom = parsedZoom;
    }
    previewOnly = parsed.previewOnly === true;
    hasAudio = parsed.hasAudio === true;
    const parsedHint: string | undefined = parsed.avHint;
    if (parsedHint !== undefined) {
      avHint = parsedHint;
    }
    this.chromeTheme = theme;
    this.chromeProgressIndex = progressIndex;
    this.chromeProgressTotal = progressTotal;
    this.chromeDebug = debug;
    this.chromeTextZoom = textZoom;
    this.chromePreviewOnly = previewOnly;
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
      textZoom,
      previewOnly,
      hasAudio,
      avHint,
    ));
    const expression: string =
      'window.OfficialReviewer.present(' + payloadJson + ',' + JSON.stringify(side) + ')';
    return new Promise<RenderAck>((resolve) => {
      let settled: boolean = false;
      let timeoutId: number = -1;
      this.ackSerial += 1;
      const serial: number = this.ackSerial;
      const finish = (ack: RenderAck): void => {
        if (settled) {
          return;
        }
        settled = true;
        if (this.ackSerial === serial) {
          this.pushedAck = undefined;
        }
        clearTimeout(timeoutId);
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
            textZoom,
            previewOnly,
            hasAudio,
            avHint,
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
            textZoom,
            previewOnly,
            hasAudio,
            avHint,
          ));
        }
        resolve(ack);
      };
      const consider = (raw: string): boolean => {
        if (raw.length === 0) {
          return false;
        }
        const type: string = raw.split('|')[0] ?? '';
        if (type !== ACK_TYPE_RENDER_COMPLETE && type !== ACK_TYPE_RENDER_ERROR) {
          return false;
        }
        const ack: RenderAck = parseAck(raw);
        const ackGeneration: number | undefined = ack.generation;
        if (ackGeneration !== undefined && ackGeneration === generation) {
          finish(ack);
          return true;
        }
        // A stale generation belongs to an earlier payload. Leave this
        // present waiting for its own row.
        return false;
      };
      this.pushedAck = (row: string): void => {
        if (this.ackSerial !== serial) {
          return;
        }
        consider(row);
      };
      timeoutId = setTimeout((): void => {
        controller
          .runJavaScript(READ_ACK_EXPRESSION)
          .then((value: string): void => {
            if (settled) {
              return;
            }
            const raw: string = unwrapEvalString(value);
            if (!consider(raw)) {
              finish(failedAck(ACK_TYPE_RENDER_ERROR, RENDER_TIMEOUT));
            }
          })
          .catch((e: BusinessError): void => {
            finish(failedAck(ACK_TYPE_RENDER_ERROR, 'POLL_FAILED_' + String(e.code)));
          });
      }, PRESENT_TIMEOUT_MS);
      controller
        .runJavaScript(expression)
        .catch((e: BusinessError): void => {
          finish(failedAck(ACK_TYPE_RENDER_ERROR, 'RUN_JAVASCRIPT_FAILED_' + String(e.code)));
        });
    });
  }

  /// The `[[type:…]]` placeholder is rendered by the frame, and whether this
  /// card has one at all is a property of the card, not of the platform — so the
  /// page asks Dart rather than guessing from the HTML.
  public setTypedVisible(visible: boolean): void {
    this.bridge.setTypedVisible(visible);
  }
}

/// Object injected into the reviewer shell as `TurnaOhosReviewer`.
///
/// Its own type, same reason as `AnkiProbeBridge`: ArkTS hands page script
/// only the methods listed in `methodList`. The handler forwards the scalar
/// row into the session the plugin's `present` is waiting on.
export class AnkiReviewerAckBridge {
  private handler: ((row: string) => void) | undefined = undefined;

  public attach(handler: (row: string) => void): void {
    this.handler = handler;
  }

  public onAck(row: string): void {
    const handler: ((row: string) => void) | undefined = this.handler;
    if (handler === undefined) {
      return;
    }
    handler(row);
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