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
import { reviewerSession } from '../anki/AnkiReviewerSessionStore';
import {
  AnkiChromePalette,
  AnkiReviewerBottomBar,
  AnkiReviewerHeaderBar,
  AnkiReviewerSettlement,
  AnkiReviewerStatusArea,
  AnkiReviewerTypedBar,
  EXIT_CONFIRM_WINDOW_MS,
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
  @State private settleTotal: number = -1;
  @State private settleRemembered: number = -1;
  @State private settleForgotten: number = -1;
  @State private settleSeconds: number = -1;
  @State private settleXp: number = -1;
  @State private bottomAvoid: number = 0;

  private alive: boolean = true;
  private bootAttempts: number = 0;
  private booted: boolean = false;
  private exitDeadline: number = 0;
  private lastRating: string = '';
  private typedTimer: number = -1;

  /// P4: keystrokes are debounced before crossing the MethodChannel — the
  /// comparison needs the text only when the answer is requested, and a
  /// message per keypress made fast typing a channel flood.
  private static readonly TYPED_DEBOUNCE_MS: number = 150;

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.theme);
  }

  aboutToAppear(): void {
    this.ackBridge.attach((row: string): void => {
      const session: AnkiReviewerSession | undefined = reviewerSession();
      if (session === undefined) {
        return;
      }
      session.acceptPushedAck(row);
    });
    this.measureBottomAvoid();
    this.bootWhenSessionArrives();
  }

  /// UI-2: keep the action rows clear of the navigation indicator. The page
  /// itself does not expand into the safe area, so without this the bottom
  /// margin sat under the system gesture bar on gesture-nav devices.
  private measureBottomAvoid(): void {
    window
      .getLastWindow(getContext(this) as common.UIAbilityContext)
      .then((win: window.Window): void => {
        const area: window.AvoidArea =
          win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        try {
          this.bottomAvoid = this.getUIContext().px2vp(area.bottomRect.height);
        } catch (e) {
          // Prebuilt page before attach: the default margin stays — the
          // avoid area only refines spacing, it never gates the layout.
        }
      })
      .catch((_e: Object): void => {
        // Best-effort layout refinement only; the default margin is usable.
      });
  }

  /// Belt to `aboutToAppear`: the page can be prebuilt before the ability
  /// creates the session, and a prebuilt page's `aboutToAppear` may have given
  /// up before the session existed. `booted` keeps the two triggers from
  /// double-booting.
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
  private bootWhenSessionArrives(): void {
    if (!this.alive || this.booted) {
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
    this.booted = true;
    session.setChromeListener((state: ReviewerChromeState): void => {
      if (state.cardId !== this.seenCard) {
        this.seenCard = state.cardId;
        this.typed = '';
        this.typedFrozen = false;
      }
      this.presentPending = state.presentPending;
      this.answerLanded = state.answerLanded;
      this.typedVisible = state.typedVisible;
      this.theme = state.theme;
      this.progressIndex = state.progressIndex;
      this.progressTotal = state.progressTotal;
      this.debugChrome = state.debug;
      this.textZoom = state.textZoom;
      this.previewOnly = state.previewOnly;
      this.hasAudio = state.hasAudio;
      this.avHint = state.avHint;
      if (!state.presentPending) {
        this.errorCode = '';
        this.errorFatal = false;
        this.status = '';
      }
      this.ratingSent = false;
    });
    session.setFailureListener((code: string): void => {
      this.showError(code, FATAL_CODES.indexOf(code) >= 0);
    });
    session
      .start(getContext(this) as common.UIAbilityContext, this.controller)
      .then((): void => {
        this.status = '';
      })
      .catch((e: Error) => {
        this.showError('start failed: ' + e.message, false);
      });
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.cancelTypedFlush();
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session !== undefined) {
      session.setChromeListener(undefined);
      session.setFailureListener(undefined);
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
    if (session === undefined) {
      return;
    }
    this.status = '';
    this.errorCode = '';
    this.errorFatal = false;
    this.advanceStuck = false;
    this.ratingSent = true;
    this.lastRating = rating;
    session.channel().rate(rating, (code: string): void => {
      this.onRateReceipt(code);
    });
  }

  private onRateReceipt(code: string): void {
    if (code === RECEIPT_OK || code === RECEIPT_OK_COMPLETE) {
      if (code === RECEIPT_OK_COMPLETE) {
        this.complete = true;
        this.fetchSettlement();
      }
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
      this.advanceStuck = true;
      this.showError('已评分，但进入下一张失败', false);
      return;
    }
    this.showError('评分失败：' + (code.length > 0 ? code : '无回执'), false);
  }

  private onRetryAdvance(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    this.status = '';
    session.channel().retryAdvance(this.lastRating, (code: string): void => {
      this.onRateReceipt(code);
    });
  }

  private onUndo(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    this.status = '正在撤销…';
    session.channel().requestUndo();
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
    });
  }

  private endReview(verdict: string): void {
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
        advanceStuck: this.advanceStuck,
        onReplayAudio: (): void => {
          this.onReplayAudio();
        },
        onUndo: (): void => {
          this.onUndo();
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
        .borderRadius(12)
        .clip(true)
        .margin({ left: 12, right: 12 })
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
    .padding({ bottom: this.bottomAvoid })
  }
}
