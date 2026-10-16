// Copyright (c) 2024 Turna. All rights reserved.
//
// The HarmonyOS reviewer page — the visible half of ADR 0050 §6 step 5b.
//
// Layout is the whole interaction design here, so it is worth stating: the
// `Web` holds the card (question or answer, never both), the typed-answer
// field sits under it while the question is showing, and the bottom row is
// either one "show answer" button, the four rating buttons, or — once the
// queue finishes — the completion row with its stats. ADR 0047 estimated
// 5–8 person-days against an embedded PlatformView, which would have kept
// the Flutter chrome; route E gives that chrome up and puts it here, and the
// visible cost is losing the scrolling card list — every card is its own
// present.
//
// The typed answer is native, and that is the architecture rather than a
// HarmonyOS accommodation: `card-frame.js`'s `applyTyped` renders `[[type:…]]`
// as an empty placeholder span, so the frame never held an input to begin
// with. Every platform's input has always been native; route E moved the
// card, not the field.
//
// B8: the system back gesture has a defined meaning — a two-step confirm
// that ends the ability with `verdict=early_exit`, which the Flutter page
// settles on. Before this, back destroyed-or-backgrounded the ability by
// system default and the exposed Flutter page had a spinner where the card
// was and toolbar actions that presented into a closed ability.
//
// UI: brand chrome mirrors the Turna palette (`lib/core/theme.dart` — the
// peacock teal family) instead of default controls, follows the card's
// day/night theme, and keeps a 16 vp page margin with the navigation bar
// explicitly avoided. The four rating buttons carry Anki's semantics
// (again red / hard orange / good the brand-filled hero / easy sky) with
// Chinese labels.

import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  AnkiReviewerSession,
  ReviewerChromeState,
  interceptFor,
} from '../anki/AnkiReviewerSession';
import { reviewerSession } from '../anki/AnkiReviewerSessionStore';

const RATINGS: Array<string> = ['again', 'hard', 'good', 'easy'];

/// Failure codes the controller classifies as fatal: retrying the present
/// cannot help (the card itself is unrenderable), so the banner offers exit
/// only. Mirrors the fatal set in `OfficialAnkiReviewerUi.fatalCodes`.
const FATAL_CODES: Array<string> = [
  'UNRENDERABLE_CARD',
  'UNRENDERABLE_TEMPLATE',
  'CARD_NOT_FOUND',
  'FATAL_RENDER_ERROR',
];

const EXIT_CONFIRM_WINDOW_MS: number = 2000;

/// Brand chrome (UI-1/UI-5): Turna's peacock tokens mirrored from
/// `lib/core/theme.dart` — brandTeal #1F727E, brandSky #4A95A8, error
/// #E74C3C. `hard` has no brand token and uses a neutral orange.
const COLOR_AGAIN: string = '#E74C3C';
const COLOR_HARD: string = '#E67E22';
const COLOR_GOOD: string = '#1F727E';
const COLOR_EASY: string = '#4A95A8';

interface ChromePalette {
  bg: string;
  surface: string;
  textPrimary: string;
  textSecondary: string;
  textHint: string;
  divider: string;
  errorTint: string;
}

function dayPalette(): ChromePalette {
  const palette: ChromePalette = {
    bg: '#F4F7F7',
    surface: '#FFFFFF',
    textPrimary: '#1C2B2E',
    textSecondary: '#5A6B6E',
    textHint: '#8A9A9D',
    divider: '#E1E8E9',
    errorTint: '#FDEDEB',
  };
  return palette;
}

function nightPalette(): ChromePalette {
  const palette: ChromePalette = {
    bg: '#10181B',
    surface: '#1A2327',
    textPrimary: '#E6EDEE',
    textSecondary: '#A5B4B7',
    textHint: '#71807F',
    divider: '#2A3438',
    errorTint: '#3A2321',
  };
  return palette;
}

function ratingLabel(rating: string): string {
  if (rating === 'again') {
    return '重来';
  }
  if (rating === 'hard') {
    return '困难';
  }
  if (rating === 'good') {
    return '良好';
  }
  return '简单';
}

function ratingColor(rating: string): string {
  if (rating === 'again') {
    return COLOR_AGAIN;
  }
  if (rating === 'hard') {
    return COLOR_HARD;
  }
  if (rating === 'good') {
    return COLOR_GOOD;
  }
  return COLOR_EASY;
}

interface ReviewerSettlement {
  total?: number;
  remembered?: number;
  forgotten?: number;
  seconds?: number;
  xp?: number;
}

function settlementSecondsText(seconds: number): string {
  const minutes: number = Math.floor(seconds / 60);
  const rest: number = seconds % 60;
  const minuteText: string = minutes > 0 ? String(minutes) + '分' : '';
  return minuteText + String(rest) + '秒';
}

@Entry
@Component
struct AnkiReviewerPage {
  private controller: webview.WebviewController = new webview.WebviewController();
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
  @State private theme: string = 'day';
  @State private progressIndex: number = 0;
  @State private progressTotal: number = 0;
  @State private debugChrome: boolean = false;
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

  private palette(): ChromePalette {
    return this.theme === 'night' ? nightPalette() : dayPalette();
  }

  aboutToAppear(): void {
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
      this.endReview('early_exit');
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

  /// Boots chrome and the asset preload the moment the session exists. Called
  /// from `aboutToAppear`, i.e. before the Web builds and asks the origin for
  /// the shell, so the preload has its head start over the kernel-driven
  /// initial load (the Web's `src` is the shell URL; no `loadUrl` is ever
  /// issued from here — every explicit-load timing tried on device lost a race
  /// to the initial navigation). A short poll covers the prebuild gap; past
  /// it, the error banner says so and offers a retry that re-polls (S4) —
  /// the pre-fix page just printed a line and had no way out.
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
      if (!state.presentPending) {
        // A present landing resolves whatever the previous face left behind:
        // the loading hint, a retryable status, and an error banner whose
        // retry already succeeded. Fresh failures are reported by the failure
        // listener AFTER this call, so nothing set here can erase them.
        this.errorCode = '';
        this.errorFatal = false;
        this.status = '';
      }
      // Every present re-arms the rating row: the interlock that disables the
      // buttons on tap only ever lifts for a present or a retryable receipt,
      // never for time. Without this the second tap of a double-tap reaches
      // Dart inside the card-switch window and is rejected as not ready.
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

  /// Resolves the session when the kernel asks, not when the page builds:
  /// `interceptFor(session)` captures its argument, and a build that happens
  /// before the session exists would freeze an undefined handle into the Web's
  /// request path. A thrown interceptor escapes a native callback and takes the
  /// process down as a RuntimeError, so absence becomes a 503 instead.
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
    // The flip carries the full text; whatever the debounce still holds is
    // redundant from here on.
    this.cancelTypedFlush();
    this.presentPending = true;
    session.channel().showAnswer(this.typed);
  }

  /// Disables the row the instant a button is tapped, then waits for Dart's
  /// receipt. The receipt is the only thing that distinguishes "committed,
  /// next card coming" from "refused" — before it existed, every refusal
  /// looked exactly like a button that does nothing.
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
    if (code === 'ok' || code === 'ok_complete') {
      // Stay disabled: the next present (or, on ok_complete, the completion
      // row below) is what re-arms the page.
      if (code === 'ok_complete') {
        this.complete = true;
        this.fetchSettlement();
      }
      return;
    }
    if (code === 'answer_not_ready' || code === 'scheduler_busy') {
      // Retryable. answer_not_ready also means Dart is flipping the card back
      // to the question face (reveal state that survived a card switch); the
      // present that follows swaps this row for "Show answer".
      this.ratingSent = false;
      this.status = code === 'scheduler_busy'
        ? '调度器忙，请再点一次'
        : '答案面未就绪，正在翻回问题面';
      return;
    }
    if (code === 'advance_failed') {
      // The rating committed; only the move to the next card failed. The
      // four buttons must NOT come back (a re-rate would double-answer) —
      // the explicit retry-advance entry below is the only way forward.
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

  /// UI-7: the completion row's statistics. An empty or malformed reply
  /// keeps the plain completion row — the Flutter completion screen behind
  /// the ability still holds the full summary.
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
        const parsed: ReviewerSettlement = JSON.parse(json) as ReviewerSettlement;
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
        // Still leave the page even when the verdict could not be carried.
        context.terminateSelf().catch((e2: BusinessError): void => {
          this.showError('close failed: ' + e2.message, false);
        });
      });
  }

  private onClose(): void {
    this.endReview(this.complete ? 'completed' : 'early_exit');
  }

  build() {
    Column() {
      Progress({
        value: this.progressTotal > 0 ? this.progressIndex : 0,
        total: this.progressTotal > 0 ? this.progressTotal : 1,
        type: ProgressType.Linear,
      })
        .color(COLOR_GOOD)
        .backgroundColor(this.palette().divider)
        .height(3)
        .margin({ left: 16, right: 16, top: 8 })
        .width('100%')

      Row() {
        Text(this.progressTotal > 0
          ? String(this.progressIndex) + '/' + String(this.progressTotal)
          : '—')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textSecondary)
        Blank()
        Button('撤销')
          .fontSize(13)
          .fontColor(this.palette().textSecondary)
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 8 })
          .height(32)
          .enabled(this.booted && !this.complete && !this.advanceStuck)
          .onClick(() => {
            this.onUndo();
          })
        Button('✕')
          .fontSize(15)
          .fontColor(this.palette().textSecondary)
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 8 })
          .height(32)
          .onClick(() => {
            this.requestExit();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8 })
      .margin({ top: 4, bottom: 2 })

      Web({ src: 'https://anki.local/assets/reviewer.html', controller: this.controller })
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

      if (this.presentPending && !this.complete && this.errorCode.length === 0) {
        Row() {
          LoadingProgress().width(16).height(16).color(this.palette().textHint)
          Text('正在加载…')
            .fontSize(12)
            .fontColor(this.palette().textHint)
            .margin({ left: 6 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8 })
      }

      if (this.confirmExit && !this.complete) {
        Text('再按一次返回或 ✕ 结束复习（已评分的卡片会保留）')
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }

      if (this.errorCode.length > 0) {
        Column() {
          Text(this.status)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_AGAIN)
            .width('100%')
          if (this.debugChrome && this.errorCode.length > 0) {
            Text(this.errorCode)
              .fontSize(11)
              .fontColor(this.palette().textHint)
              .width('100%')
              .margin({ top: 2 })
          }
          if (
            !this.advanceStuck &&
            (this.booted || this.errorCode === 'reviewer session missing')
          ) {
            Row() {
              if (!this.errorFatal) {
                Button(this.booted ? '重试' : '重新连接')
                  .fontSize(14)
                  .fontColor(COLOR_GOOD)
                  .backgroundColor(Color.Transparent)
                  .borderRadius(8)
                  .height(36)
                  .layoutWeight(1)
                  .onClick(() => {
                    if (this.booted) {
                      this.retryRender();
                    } else {
                      this.retryBoot();
                    }
                  })
              }
              Button('退出复习')
                .fontSize(14)
                .fontColor(this.palette().textSecondary)
                .backgroundColor(Color.Transparent)
                .borderRadius(8)
                .height(36)
                .layoutWeight(1)
                .onClick(() => {
                  this.endReview('early_exit');
                })
            }
            .width('100%')
            .margin({ top: 6 })
          }
        }
        .width('100%')
        .padding(12)
        .margin({ left: 16, right: 16, top: 8 })
        .borderRadius(10)
        .backgroundColor(this.palette().errorTint)
      } else if (this.status.length > 0) {
        Text(this.status)
          .fontSize(12)
          .fontColor(this.palette().textHint)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }

      if (this.typedVisible && !this.answerLanded && !this.complete) {
        Column() {
          Divider()
            .color(this.palette().divider)
            .margin({ left: 16, right: 16 })
          TextInput({ text: this.typed, placeholder: '输入你的答案' })
            .enabled(!this.typedFrozen && !this.presentPending)
            .enterKeyType(EnterKeyType.Done)
            .onSubmit(() => {
              if (!this.typedFrozen) {
                this.onShowAnswer();
              }
            })
            .onChange((value: string) => {
              this.typed = value;
              this.scheduleTypedFlush();
            })
            .backgroundColor(this.palette().surface)
            .borderRadius(10)
            .height(44)
            .margin({ left: 16, right: 16, top: 10 })
        }
        .width('100%')
      }

      if (this.complete) {
        Column() {
          Text('复习完成')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().textPrimary)
            .margin({ top: 14 })
          if (this.settleTotal >= 0) {
            Text('共 ' + String(this.settleTotal) + ' 张 · 记住 '
              + String(this.settleRemembered) + ' · 忘记 '
              + String(this.settleForgotten))
              .fontSize(13)
              .fontColor(this.palette().textSecondary)
              .margin({ top: 6 })
            Text('用时 ' + settlementSecondsText(this.settleSeconds)
              + (this.settleXp > 0 ? ' · +' + String(this.settleXp) + ' XP' : ''))
              .fontSize(13)
              .fontColor(this.palette().textSecondary)
              .margin({ top: 2 })
          }
          Button('完成')
            .width('100%')
            .height(50)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(COLOR_GOOD)
            .fontColor(Color.White)
            .borderRadius(12)
            .margin({ top: 12, bottom: 16 })
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      } else if (this.advanceStuck) {
        Column() {
          Text(this.status)
            .fontSize(12)
            .fontColor(this.palette().textSecondary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 6 })
          Row() {
            Button('重试进入下一张')
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .backgroundColor(COLOR_GOOD)
              .fontColor(Color.White)
              .borderRadius(12)
              .margin({ right: 6 })
              .onClick(() => {
                this.onRetryAdvance();
              })
            Button('结束复习')
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .fontColor(this.palette().textSecondary)
              .borderRadius(12)
              .border({ width: 1, color: this.palette().divider })
              .margin({ left: 6 })
              .onClick(() => {
                this.endReview('early_exit');
              })
          }
          .width('100%')
          .margin({ top: 10, bottom: 16 })
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
      } else if (!this.answerLanded) {
        Button(this.presentPending ? '正在显示答案…' : '显示答案')
          .width('100%')
          .height(52)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.presentPending ? this.palette().divider : COLOR_GOOD)
          .fontColor(this.presentPending ? this.palette().textHint : Color.White)
          .borderRadius(12)
          .animation({ duration: 150, curve: Curve.EaseOut })
          .margin({ left: 16, right: 16, top: 10, bottom: 16 })
          .enabled(!this.presentPending)
          .onClick(() => {
            this.onShowAnswer();
          })
      } else if (this.ratingSent) {
        // UI-8: one honest "submitted, loading" state instead of four dead
        // buttons that give no reason.
        Button('已提交，加载中…')
          .width('100%')
          .height(50)
          .fontSize(15)
          .fontColor(this.palette().textHint)
          .backgroundColor(this.palette().divider)
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 10, bottom: 16 })
          .enabled(false)
      } else {
        Row() {
          ForEach(RATINGS, (rating: string) => {
            Button(ratingLabel(rating))
              .layoutWeight(rating === 'good' ? 1.25 : 1)
              .height(rating === 'good' ? 50 : 46)
              .fontSize(rating === 'good' ? 15 : 14)
              .fontWeight(rating === 'good' ? FontWeight.Medium : FontWeight.Normal)
              .backgroundColor(rating === 'good'
                ? ratingColor(rating)
                : Color.Transparent)
              .fontColor(rating === 'good'
                ? Color.White
                : ratingColor(rating))
              .borderRadius(12)
              .border({
                width: 1,
                color: rating === 'good' ? ratingColor(rating) : this.palette().divider,
              })
              .margin({ right: 8 })
              .animation({ duration: 150, curve: Curve.EaseOut })
              .onClick(() => {
                this.onRate(rating);
              })
          }, (rating: string) => rating)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 8 })
        .margin({ top: 10, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().bg)
    .padding({ bottom: this.bottomAvoid })
  }
}
