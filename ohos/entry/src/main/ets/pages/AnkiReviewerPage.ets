// Copyright (c) 2024 Turna. All rights reserved.
//
// The HarmonyOS reviewer page — the visible half of ADR 0050 §6 step 5b.
//
// Layout is the whole interaction design here, so it is worth stating: the
// `Web` holds the card (question or answer, never both), the typed-answer
// field sits under it while the question is showing, and the bottom row is
// either one "show answer" button, the two rating buttons (forget / remember,
// matching Android's binary recall bar), the two preview buttons, or — once the
// queue finishes — the completion row with its stats.
//
// R2: visual chrome tokens, palette helpers, and the header/status/typed/bottom
// subcomponents live in `../anki/AnkiReviewerChrome.ets` so this page stays
// focused on ability lifecycle, session boot, and MethodChannel orchestration.

import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  AnkiReviewerAckBridge,
  AnkiReviewerSession,
  ReviewerChromeState,
  interceptFor,
} from '../anki/AnkiReviewerSession';
import { reviewerSession, consumePendingReviewerCancel } from '../anki/AnkiReviewerSessionStore';
import {
  AnkiChromePalette,
  AnkiReviewerBottomBar,
  AnkiReviewerHeaderBar,
  AnkiReviewerSettlement,
  AnkiReviewerStatusArea,
  AnkiReviewerTypedBar,
  COMPLETION_HANDOFF_MS,
  EXIT_CONFIRM_WINDOW_MS,
  isDarkTheme,
  paletteForTheme,
} from '../anki/AnkiReviewerChrome';
import {
  FATAL_CODES,
  RECEIPT_ADVANCE_FAILED,
  RECEIPT_ANSWER_NOT_READY,
  RECEIPT_OK,
  RECEIPT_OK_COMPLETE,
  RECEIPT_SCHEDULER_BUSY,
  THEME_DAY,
  VERDICT_COMPLETED,
  VERDICT_EARLY_EXIT,
  VERDICT_WARM_CANCELED,
} from '../anki/AnkiReviewerProtocol';

@Entry
@Component
struct AnkiReviewerPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  private ackBridge: AnkiReviewerAckBridge = new AnkiReviewerAckBridge();
  @State private answerLanded: boolean = false;
  @State private presentPending: boolean = false;
  @State private typedVisible: boolean = false;
  @State private typed: string = '';
  @State private typedFrozen: boolean = false;
  @State private seenCard: number = -1;
  @State private status: string = '';
  @State private errorCode: string = '';
  @State private errorFatal: boolean = false;
  @State private ratingSent: boolean = false;
  @State private advanceStuck: boolean = false;

  @State private complete: boolean = false;
  @State private confirmExit: boolean = false;
  @State private theme: string = THEME_DAY;
  @State private progressIndex: number = 0;
  @State private progressTotal: number = 0;
  @State private debugChrome: boolean = false;
  @State private textZoom: number = 100;
  @State private previewOnly: boolean = false;
  @State private hasAudio: boolean = false;
  @State private avHint: string = '';
  /// UI-15: chrome state Dart sends because the native page holds no
  /// controller — the Review All badge. The undo / redo / mutate predicates
  /// were only read by the header's queue-mutation entries and left with them.
  @State private sourceProgress: string = '';
  /// UI-16: single-source session — the completion row closes itself and hands
  /// the summary over to Flutter's `UnifiedReviewCompletion`. False under
  /// Review All, where the next source reuses this same ability.
  @State private autoComplete: boolean = false;
  @State private settleTotal: number = -1;
  @State private settleRemembered: number = -1;
  @State private settleForgotten: number = -1;
  @State private settleSeconds: number = -1;
  @State private settleXp: number = -1;
  /// Insets the edge-to-edge window overlaps, measured in vp.
  @State private topAvoid: number = 0;
  @State private bottomAvoid: number = 0;

  private alive: boolean = true;
  private bootAttempts: number = 0;
  private booted: boolean = false;

  /// UI-16: the completion hand-off timer is armed at most once per session,
  /// and `terminating` keeps `endReview` idempotent — the auto-close and the
  /// learner's own tap can race, and two `terminateSelfWithResult` calls on a
  /// dying ability only produce noise.
  private autoCloseScheduled: boolean = false;
  private terminating: boolean = false;

  /// The session object this page installed its listeners on. See
  /// [bootWhenSessionArrives] for why identity matters here.
  private boundSession: AnkiReviewerSession | undefined = undefined;

  private exitDeadline: number = 0;
  private lastRating: string = '';
  private typedTimer: number = -1;

  /// UI-8 follow-up: `ok` deliberately does not release the rating interlock
  /// (releasing it there let one card be rated twice), so the release comes
  /// from the next question face instead. This timer is the net under that:
  /// if the present never lands — a scheduler desync, a closed ability, a
  /// frame that gave up before its own ack — the learner would be parked on
  /// "已提交，加载中…" with no entry at all.
  private ratingTimer: number = -1;

  /// D8/UI-8: one `retryAdvance` at a time. The entry only appears after an
  /// `advance_failed` receipt, and a double tap would race two advances
  /// against one queue.
  private advancePending: boolean = false;

  /// P4: keystrokes are debounced before crossing the MethodChannel — the
  /// comparison needs the text only when the answer is requested, and a
  /// message per keypress made fast typing a channel flood.
  private static readonly TYPED_DEBOUNCE_MS: number = 150;

  /// How long a committed rating may go without a new question face before the
  /// page stops believing one is coming.
  ///
  /// 20 s covers the whole legal path: the engine commit, the scheduler
  /// advance (up to eight re-renders in the P0-2 window), the media push, and
  /// the present's own 12 s ack timeout. Shorter trips on a cold collection
  /// with large audio; longer leaves the learner on a dead button.
  private static readonly RATING_STALL_MS: number = 20000;

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.theme);
  }

  aboutToAppear(): void {
    // `aboutToDisappear` clears this; a page that is shown again (the ability
    // was backgrounded, not destroyed) must be able to boot. Leaving it false
    // made `onPageShow`'s re-boot a permanent no-op.
    this.alive = true;
    this.ackBridge.attach((row: string): void => {
      const session: AnkiReviewerSession | undefined = this.boundSession;
      if (session === undefined) {
        return;
      }
      session.acceptPushedAck(row);
    });
    this.configureWindowChrome();
    this.bootWhenSessionArrives();
  }

  /// Take the window edge to edge, then hand the safe-area insets to the page.
  ///
  /// Measured on device (CMM-AL10 / HarmonyOS 7.0.0.109): `statusBarColor` is
  /// honoured, `navigationBarColor` is not — the navigation strip stayed white
  /// under a black page no matter what was sent. So the fix cannot be "paint
  /// both bars"; the window has to reach underneath the strip and let the
  /// page's own background show through, with the inset handed back as
  /// padding. Same conclusion the Flutter side reached long before: content
  /// lives inside the safe area, decoration lives outside it.
  ///
  /// Glyphs still come from the theme, because a white-on-white status bar is
  /// unreadable even when the fill is right. Re-applied on every `chromeTheme`
  /// change: the first present of a session arrives before Dart has said
  /// whether this is day or night.
  ///
  /// Best-effort throughout: a window that is not there yet must not break the
  /// page, and the layout runs fine on whatever insets it has.
  private configureWindowChrome(): void {
    window
      .getLastWindow(getContext(this) as common.UIAbilityContext)
      .then((win: window.Window): void => {
        win
          .setWindowLayoutFullScreen(true)
          .catch((_e: BusinessError): void => {
            // Inset layout still works; only the two bands come back.
          })
          .then((): void => {
            this.applySystemBars(win);
            this.measureSafeAreas(win);
          });
      })
      .catch((_e: Object): void => {
        // A missing window is a launch-timing fact, not a page failure.
      });
  }

  /// Transparent bars + theme-matched glyphs. See [configureWindowChrome] for
  /// why the fill is transparent rather than a colour.
  private applySystemBars(win: window.Window): void {
    const dark: boolean = isDarkTheme(this.theme);
    // `statusBarContentColor` is the glyph colour and `isStatusBarLightIcon`
    // the older boolean for the same thing; both are sent because they were
    // introduced in different API levels and some devices honour only one.
    const glyph: string = dark ? '#FFFFFF' : '#000000';
    const props: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      statusBarContentColor: glyph,
      isStatusBarLightIcon: dark,
      navigationBarColor: '#00000000',
      navigationBarContentColor: glyph,
      isNavigationBarLightIcon: dark,
    };
    win.setWindowSystemBarProperties(props).catch((_e: BusinessError): void => {
      // Cosmetic only — the page stays usable with system defaults.
    });
  }

  /// Repaint the glyphs after a theme flip, against the live window.
  private refreshSystemBarGlyphs(): void {
    window
      .getLastWindow(getContext(this) as common.UIAbilityContext)
      .then((win: window.Window): void => {
        this.applySystemBars(win);
      })
      .catch((_e: Object): void => {
        // Next theme change retries.
      });
  }

  /// UI-2: read the insets the edge-to-edge window now overlaps.
  ///
  /// The status bar height was never needed before (the platform inset the
  /// content for us); now that the window fills the screen it does. The bottom
  /// is the larger of the two reports on purpose: gesture navigation publishes
  /// `TYPE_NAVIGATION_INDICATOR`, three-button navigation publishes the same
  /// strip under `TYPE_SYSTEM`, and taking the max clears both without needing
  /// to know which mode the device is in.
  private measureSafeAreas(win: window.Window): void {
    try {
      const system: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const bottom: number = Math.max(
        system.bottomRect.height,
        indicator.bottomRect.height,
      );
      const context = this.getUIContext();
      this.topAvoid = context.px2vp(system.topRect.height);
      this.bottomAvoid = context.px2vp(bottom);
    } catch (e) {
      // Prebuilt page before attach: the defaults stay — the avoid area only
      // refines spacing, it never gates the layout.
    }
  }

  /// Belt to `aboutToAppear`: the page can be prebuilt before the ability
  /// creates the session, and a prebuilt page's `aboutToAppear` may have given
  /// up before the session existed. `booted` keeps the two triggers from
  /// booting the same session twice; a *different* session still boots, which
  /// is what catches an `onNewWant` swap that landed while this page was
  /// hidden.
  onPageShow(): void {
    this.bootWhenSessionArrives();
  }

  /// Two-step exit (B8): the first back press asks, the second inside the
  /// window ends the review with `early_exit`. Returning true consumes the
  /// gesture — the system default (destroy-or-background, verdict-less) is
  /// exactly the path that used to strand the Flutter page.
  onBackPress(): boolean {
    this.requestExit();
    return true;
  }

  private requestExit(): void {
    if (this.confirmExit) {
      this.endReview(VERDICT_EARLY_EXIT);
      return;
    }
    this.confirmExit = true;
    this.exitDeadline = Date.now() + EXIT_CONFIRM_WINDOW_MS;
    this.scheduleConfirmReset();
  }

  private scheduleConfirmReset(): void {
    setTimeout((): void => {
      if (Date.now() >= this.exitDeadline) {
        this.confirmExit = false;
      }
    }, EXIT_CONFIRM_WINDOW_MS + 50);
  }

  /// Boots chrome and the asset preload the moment the session exists.
  ///
  /// Binds to the session *object*, not to whatever `reviewerSession()` returns
  /// later. `onNewWant` can replace the store's session while this page is
  /// alive (a different media root), and a page still bound to the previous
  /// object receives neither presents nor chrome updates: the card stays on
  /// screen, nothing on it responds, and a rating looks submitted forever.
  /// [onPageShow] re-runs this precisely to notice that swap.
  private bootWhenSessionArrives(): void {
    if (!this.alive) {
      return;
    }
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session === undefined) {
      if (this.bootAttempts < 50) {
        this.bootAttempts += 1;
        setTimeout((): void => {
          this.bootWhenSessionArrives();
        }, 100);
        return;
      }
      this.showError('reviewer session missing', false);
      return;
    }
    const previous: AnkiReviewerSession | undefined = this.boundSession;
    if (this.booted && previous === session) {
      return;
    }
    if (previous !== undefined && previous !== session) {
      // Unbind the object this page bound, never the one currently in the
      // store: that one belongs to the replacement page, and clearing its
      // listeners would silence a live reviewer.
      this.unbindSession(previous);
      this.resetSessionState();
    }
    this.booted = true;
    this.bootAttempts = 0;
    this.boundSession = session;
    session.setChromeListener((state: ReviewerChromeState): void => {
      if (this.boundSession !== session) {
        return;
      }
      if (state.cardId !== this.seenCard) {
        this.seenCard = state.cardId;
        this.typed = '';
        this.typedFrozen = false;
      }
      this.presentPending = state.presentPending;
      this.answerLanded = state.answerLanded;
      this.typedVisible = state.typedVisible;
      if (state.theme !== this.theme) {
        this.theme = state.theme;
        // Day/night changes what the system bars have to be painted with —
        // the bars follow the page, so a theme flip that skipped this left a
        // light-theme bar over a dark page until the ability was rebuilt.
        this.refreshSystemBarGlyphs();
      }
      this.progressIndex = state.progressIndex;
      this.progressTotal = state.progressTotal;
      this.debugChrome = state.debug;
      this.textZoom = state.textZoom;
      this.previewOnly = state.previewOnly;
      this.hasAudio = state.hasAudio;
      this.avHint = state.avHint;
      this.sourceProgress = state.sourceProgress;
      this.autoComplete = state.autoComplete;
      if (!state.presentPending) {
        this.errorCode = '';
        this.errorFatal = false;
        this.status = '';
      }
      // Only an answerable question face proves the rating round-trip is over.
      // This used to clear unconditionally, which meant the present-start
      // notification (presentPending=true, answerLanded=false) released the
      // interlock while the receipt was still in flight — and once that
      // present finished, the rating row was back on a card that had already
      // been graded, so a second tap graded it again.
      if (!state.presentPending && !state.answerLanded) {
        this.ratingSent = false;
        this.advanceStuck = false;
        this.disarmRatingWatchdog();
      }
    });
    session.setFailureListener((code: string): void => {
      if (this.boundSession !== session) {
        return;
      }
      this.showError(code, FATAL_CODES.indexOf(code) >= 0);
    });
    session.setCancelListener((): void => {
      if (this.boundSession !== session) {
        return;
      }
      // P0-1: a speculative open that was abandoned before any card arrived.
      this.endReview(VERDICT_WARM_CANCELED);
    });
    if (session.consumeCancelRequest() || consumePendingReviewerCancel()) {
      // The cancel landed before this page existed (the warm-up had not got
      // here yet), or before this page's listener was installed. Honour it now
      // rather than booting a page nobody wants.
      this.endReview(VERDICT_WARM_CANCELED);
      return;
    }
    session
      .start(getContext(this) as common.UIAbilityContext, this.controller)
      .then((): void => {
        this.status = '';
      })
      .catch((e: Error) => {
        this.showError('start failed: ' + e.message, false);
      });
  }

  /// Detaches this page's listeners from one session object. Identity-checked
  /// by the caller; never called with `reviewerSession()`.
  private unbindSession(session: AnkiReviewerSession): void {
    session.setChromeListener(undefined);
    session.setFailureListener(undefined);
    session.setCancelListener(undefined);
  }

  /// Clears everything that described the previous session's card. A new
  /// session starts at card 0 with no faces: inheriting `answerLanded` or
  /// `ratingSent` would render a rating row for a card that is not there.
  private resetSessionState(): void {
    this.seenCard = -1;
    this.presentPending = false;
    this.answerLanded = false;
    this.typedVisible = false;
    this.typed = '';
    this.typedFrozen = false;
    this.ratingSent = false;
    this.advanceStuck = false;
    this.complete = false;
    this.previewOnly = false;
    this.hasAudio = false;
    this.avHint = '';
    this.sourceProgress = '';
    this.autoComplete = false;
    this.progressIndex = 0;
    this.progressTotal = 0;
    this.status = '';
    this.errorCode = '';
    this.errorFatal = false;
    this.settleTotal = -1;
    this.settleRemembered = -1;
    this.settleForgotten = -1;
    this.settleSeconds = -1;
    this.settleXp = -1;
    // UI-16: a new session may arm its own hand-off. `terminating` is
    // deliberately NOT reset — it guards the ability, not the session, and a
    // page that is closing must never close twice.
    this.autoCloseScheduled = false;
    this.disarmRatingWatchdog();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.cancelTypedFlush();
    this.disarmRatingWatchdog();
    const bound: AnkiReviewerSession | undefined = this.boundSession;
    this.boundSession = undefined;
    if (bound !== undefined) {
      this.unbindSession(bound);
    }
  }

  private session(): AnkiReviewerSession | undefined {
    return reviewerSession();
  }

  private showError(code: string, fatal: boolean): void {
    this.errorCode = code;
    this.errorFatal = fatal;
    this.status = fatal ? '无法显示这张卡片' : '卡片加载失败，可重试';
  }

  private retryBoot(): void {
    this.errorCode = '';
    this.errorFatal = false;
    this.status = '';
    this.bootAttempts = 0;
    this.booted = false;
    this.boundSession = undefined;
    this.bootWhenSessionArrives();
  }

  private retryRender(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    this.errorCode = '';
    this.errorFatal = false;
    this.status = '';
    session.channel().retryPresent();
  }

  private intercept(event: OnInterceptRequestEvent): WebResourceResponse {
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session === undefined) {
      const refused: WebResourceResponse = new WebResourceResponse();
      refused.setResponseMimeType('text/plain');
      refused.setResponseEncoding('utf-8');
      refused.setResponseData('');
      refused.setResponseCode(503);
      refused.setReasonMessage('reviewer_not_open');
      return refused;
    }
    return interceptFor(session)(event);
  }

  private scheduleTypedFlush(): void {
    if (this.typedTimer >= 0) {
      clearTimeout(this.typedTimer);
    }
    this.typedTimer = setTimeout((): void => {
      this.typedTimer = -1;
      const session: AnkiReviewerSession | undefined = this.session();
      if (session !== undefined) {
        session.channel().typedChanged(this.typed);
      }
    }, AnkiReviewerPage.TYPED_DEBOUNCE_MS);
  }

  private cancelTypedFlush(): void {
    if (this.typedTimer >= 0) {
      clearTimeout(this.typedTimer);
      this.typedTimer = -1;
    }
  }

  private onShowAnswer(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    this.typedFrozen = true;
    this.cancelTypedFlush();
    this.presentPending = true;
    session.channel().showAnswer(this.typed);
  }

  private onShowQuestion(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    this.typedFrozen = false;
    this.presentPending = true;
    session.channel().showQuestion();
  }

  private onReplayAudio(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    session.channel().replayAudio((hint: string): void => {
      if (hint.length > 0) {
        this.avHint = hint;
      }
    });
  }

  private onRate(rating: string): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined || this.ratingSent) {
      return;
    }
    this.status = '';
    this.errorCode = '';
    this.errorFatal = false;
    this.advanceStuck = false;
    this.ratingSent = true;
    this.lastRating = rating;
    this.armRatingWatchdog();
    session.channel().rate(rating, (code: string): void => {
      this.onRateReceipt(code);
    });
  }

  /// One receipt, one decision. The page's whole rating interlock lives here,
  /// and the two branches that keep `ratingSent` true are the ones where the
  /// commit already happened: releasing it would let the same card be graded
  /// a second time.
  private onRateReceipt(code: string): void {
    this.disarmRatingWatchdog();
    if (code === RECEIPT_OK || code === RECEIPT_OK_COMPLETE) {
      // A previous advance failure is resolved by this receipt: `ok` means the
      // session moved on. Leaving `advanceStuck` set here parked the bottom
      // bar on "重试进入下一张" for the rest of the review.
      this.advanceStuck = false;
      if (code === RECEIPT_OK_COMPLETE) {
        this.complete = true;
        this.fetchSettlement();
        return;
      }
      // The next card is still on its way (media push + present). The chrome
      // listener releases the interlock when its question face lands, and the
      // watchdog covers a present that never does.
      this.armRatingWatchdog();
      return;
    }
    if (code === RECEIPT_ANSWER_NOT_READY || code === RECEIPT_SCHEDULER_BUSY) {
      this.ratingSent = false;
      this.status = code === RECEIPT_SCHEDULER_BUSY
        ? '调度器忙，请再点一次'
        : '答案面未就绪，正在翻回问题面';
      return;
    }
    if (code === RECEIPT_ADVANCE_FAILED) {
      // The rating is in the scheduler; only the advance failed. Re-arming the
      // row would submit the same card again, so the retry entry is the only
      // way forward.
      this.advanceStuck = true;
      this.errorCode = 'advance_failed';
      this.errorFatal = false;
      this.status = '已评分，但进入下一张失败';
      return;
    }
    // Everything else means no commit happened — a committed failure always
    // surfaces as `advance_failed` — so the row must be armed again. Leaving
    // `ratingSent` true here is exactly the "已提交，加载中…" deadlock: the
    // button is disabled and nothing will ever flip it back.
    this.ratingSent = false;
    this.errorCode = code.length > 0 ? code : 'rating_failed';
    this.errorFatal = false;
    this.status = '评分失败：' + (code.length > 0 ? code : '无回执');
  }

  private onRetryAdvance(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined || this.advancePending) {
      return;
    }
    this.advancePending = true;
    this.status = '';
    session.channel().retryAdvance(this.lastRating, (code: string): void => {
      this.advancePending = false;
      this.onRateReceipt(code);
    });
  }

  /// Turns a silent stall into the same retry/exit row an `advance_failed`
  /// receipt produces. See [RATING_STALL_MS] for the window.
  private armRatingWatchdog(): void {
    this.disarmRatingWatchdog();
    this.ratingTimer = setTimeout((): void => {
      this.ratingTimer = -1;
      if (!this.ratingSent || this.complete) {
        return;
      }
      if (this.presentPending) {
        // A present is in flight and carries its own 12 s ack timeout: a card
        // that is still rendering is not a stall. Give it one more window.
        this.armRatingWatchdog();
        return;
      }
      this.advanceStuck = true;
      this.errorCode = 'rating_stalled';
      this.errorFatal = false;
      this.status = '评分已提交，但下一张卡片没有到达';
    }, AnkiReviewerPage.RATING_STALL_MS);
  }

  private disarmRatingWatchdog(): void {
    if (this.ratingTimer >= 0) {
      clearTimeout(this.ratingTimer);
      this.ratingTimer = -1;
    }
  }

  /// D9: cards still owed, matching Android's `remainingCount` shape — the
  /// current card counts, because it is still unanswered. `progressIndex` is
  /// `answered + 1` (clamped) and `progressTotal` is `answered + owed`, so the
  /// owed count is `total - (index - 1)`. Guarded at 0 rather than trusting
  /// the arithmetic: during boot both fields are 0, and a negative "还剩" line
  /// is worse than no line.
  private remainingCards(): number {
    if (this.progressTotal <= 0) {
      return 0;
    }
    const owed: number = this.progressTotal - this.progressIndex + 1;
    return owed > 0 ? owed : 0;
  }

  private fetchSettlement(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    session.channel().settlement((json: string): void => {
      if (json.length === 0) {
        return;
      }
      try {
        const parsed: AnkiReviewerSettlement = JSON.parse(json) as AnkiReviewerSettlement;
        this.settleTotal = parsed.total ?? 0;
        this.settleRemembered = parsed.remembered ?? 0;
        this.settleForgotten = parsed.forgotten ?? 0;
        this.settleSeconds = parsed.seconds ?? 0;
        this.settleXp = parsed.xp ?? 0;
      } catch (e) {
        // Stats are cosmetic here; the authoritative summary is the Flutter
        // completion screen this row hands back to.
      }
      this.scheduleAutoClose();
    });
  }

  /// UI-16: hand the completion screen back to Flutter.
  ///
  /// Before this the native row was the only summary the learner ever saw:
  /// tapping 「完成」 closed the ability, and Dart's `_onNativeAbilityClosed`
  /// immediately popped the page — so `UnifiedReviewCompletion`, which is
  /// already rendered underneath the ability the moment the queue finishes
  /// (and is the exact component Android shows), was torn down before it was
  /// ever visible.
  ///
  /// Only single-source sessions arm this. Under Review All the next source
  /// re-attaches to this same ability (same `mediaRoot` → `onNewWant` reuses
  /// the session), and a timer armed by the finished source would close the
  /// page the next source is already using. Review All keeps the explicit
  /// button and lets Dart decide.
  ///
  /// The button stays as a fallback: if the ability is not in the foreground
  /// when the timer fires (`alive` false, or the window already went away),
  /// the learner still has a way out.
  private scheduleAutoClose(): void {
    if (!this.autoComplete || this.autoCloseScheduled) {
      return;
    }
    this.autoCloseScheduled = true;
    setTimeout((): void => {
      // `complete` is reset when a new session binds, so a source hand-off in
      // the meantime disarms this timer without any extra bookkeeping.
      if (!this.alive || !this.complete) {
        return;
      }
      this.endReview(VERDICT_COMPLETED);
    }, COMPLETION_HANDOFF_MS);
  }

  private endReview(verdict: string): void {
    if (this.terminating) {
      return;
    }
    this.terminating = true;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const want: Want = { parameters: { verdict: verdict } };
    const result: common.AbilityResult = {
      resultCode: 0,
      want: want,
    };
    context
      .terminateSelfWithResult(result)
      .catch((): void => {
        context.terminateSelf().catch((e2: BusinessError): void => {
          this.terminating = false;
          this.showError('close failed: ' + e2.message, false);
        });
      });
  }

  private onClose(): void {
    this.endReview(this.complete ? VERDICT_COMPLETED : VERDICT_EARLY_EXIT);
  }

  build() {
    Column() {
      AnkiReviewerHeaderBar({
        themeName: this.theme,
        progressIndex: this.progressIndex,
        progressTotal: this.progressTotal,
        previewOnly: this.previewOnly,
        hasAudio: this.hasAudio,
        booted: this.booted,
        presentPending: this.presentPending,
        isComplete: this.complete,
        sourceProgress: this.sourceProgress,
        onReplayAudio: (): void => {
          this.onReplayAudio();
        },
        onRequestExit: (): void => {
          this.requestExit();
        },
      })

      Web({ src: 'https://anki.local/assets/reviewer.html', controller: this.controller })
        .javaScriptProxy({
          object: this.ackBridge,
          name: 'TurnaOhosReviewer',
          methodList: ['onAck'],
          controller: this.controller,
        })
        .textZoomRatio(this.textZoom)
        .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse => this.intercept(event))
        .onPageEnd((event: OnPageEndEvent) => {
          if (event.url.indexOf('reviewer.html') >= 0) {
            const current: AnkiReviewerSession | undefined = this.session();
            if (current !== undefined) {
              current.markShellReady();
            }
          }
        })
        .layoutWeight(1)
        .width('100%')
        .borderRadius(16)
        .clip(true)
        .margin({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.palette().surface)

      AnkiReviewerStatusArea({
        themeName: this.theme,
        presentPending: this.presentPending,
        isComplete: this.complete,
        confirmExit: this.confirmExit,
        previewOnly: this.previewOnly,
        avHint: this.avHint,
        errorCode: this.errorCode,
        errorFatal: this.errorFatal,
        statusText: this.status,
        debugChrome: this.debugChrome,
        advanceStuck: this.advanceStuck,
        booted: this.booted,
        remainingCount: this.remainingCards(),
        onRetryOrReconnect: (): void => {
          if (this.booted) {
            this.retryRender();
          } else {
            this.retryBoot();
          }
        },
        onExitEarly: (): void => {
          this.endReview(VERDICT_EARLY_EXIT);
        },
      })

      if (this.typedVisible && !this.answerLanded && !this.complete) {
        AnkiReviewerTypedBar({
          themeName: this.theme,
          typedText: this.typed,
          typedFrozen: this.typedFrozen,
          presentPending: this.presentPending,
          textZoom: this.textZoom,
          onTypedChange: (nextText: string): void => {
            this.typed = nextText;
            this.scheduleTypedFlush();
          },
          onSubmitAnswer: (): void => {
            this.onShowAnswer();
          },
        })
      }

      AnkiReviewerBottomBar({
        themeName: this.theme,
        isComplete: this.complete,
        autoComplete: this.autoComplete,
        advanceStuck: this.advanceStuck,
        answerLanded: this.answerLanded,
        previewOnly: this.previewOnly,
        ratingSent: this.ratingSent,
        presentPending: this.presentPending,
        statusText: this.status,
        settleTotal: this.settleTotal,
        settleRemembered: this.settleRemembered,
        settleForgotten: this.settleForgotten,
        settleSeconds: this.settleSeconds,
        settleXp: this.settleXp,
        onShowAnswer: (): void => {
          this.onShowAnswer();
        },
        onShowQuestion: (): void => {
          this.onShowQuestion();
        },
        onRate: (rating: string): void => {
          this.onRate(rating);
        },
        onRetryAdvance: (): void => {
          this.onRetryAdvance();
        },
        onFinishComplete: (): void => {
          this.onClose();
        },
        onExitEarly: (): void => {
          this.endReview(VERDICT_EARLY_EXIT);
        },
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().bg)
    .padding({ top: this.topAvoid, bottom: this.bottomAvoid })
  }
}
