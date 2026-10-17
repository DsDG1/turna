// Copyright (c) 2024 Turna. All rights reserved.
//
// Reusable ArkUI chrome components, theme palette tokens, and rating/settlement
// helpers for the HarmonyOS Official Anki reviewer page (R2 split from
// `pages/AnkiReviewerPage.ets`).
//
// Keeping the visual chrome and sub-bars in their own module leaves
// `AnkiReviewerPage.ets` focused on ability lifecycle, session boot, and
// MethodChannel action dispatch.

import {
  RATING_AGAIN,
  RATING_EASY,
  RATING_GOOD,
  RATING_HARD,
  THEME_NIGHT,
} from './AnkiReviewerProtocol';

export const EXIT_CONFIRM_WINDOW_MS: number = 2000;

/// Brand chrome (UI-1/UI-5): Turna's peacock tokens mirrored from
/// `lib/core/theme.dart` — brandTeal #1F727E, brandSky #4A95A8, error
/// #E74C3C. `hard` has no brand token and uses a neutral orange.
export const COLOR_AGAIN: string = '#E74C3C';
export const COLOR_HARD: string = '#E67E22';
export const COLOR_GOOD: string = '#1F727E';
export const COLOR_EASY: string = '#4A95A8';

/// Tint + edge pair for the two rating buttons, mirroring Android's
/// `_RecallButton`: one hue drives both, at 12% fill and 35% border. Written as
/// ARGB literals because ArkTS has no alpha helper that keeps the base hex
/// readable next to it. When the base token changes these must move with it.
export const COLOR_AGAIN_TINT: string = '#1FE74C3C';
export const COLOR_AGAIN_EDGE: string = '#59E74C3C';
export const COLOR_GOOD_TINT: string = '#1F1F727E';
export const COLOR_GOOD_EDGE: string = '#591F727E';

export interface AnkiChromePalette {
  bg: string;
  surface: string;
  textPrimary: string;
  textSecondary: string;
  textHint: string;
  divider: string;
  errorTint: string;
}

export function dayPalette(): AnkiChromePalette {
  const palette: AnkiChromePalette = {
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

export function nightPalette(): AnkiChromePalette {
  const palette: AnkiChromePalette = {
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

export function paletteForTheme(themeName: string): AnkiChromePalette {
  return themeName === THEME_NIGHT ? nightPalette() : dayPalette();
}

/// Label wording follows Android's `AppStrings.reviewBinaryForgotten` /
/// `reviewBinaryRemembered` for the two ratings that are offered. The `hard` /
/// `easy` branches are unreachable from the UI and kept only so a future
/// four-rating surface cannot silently inherit the wrong word.
export function ratingLabel(rating: string): string {
  if (rating === RATING_AGAIN) {
    return '忘记';
  }
  if (rating === RATING_HARD) {
    return '困难';
  }
  if (rating === RATING_GOOD) {
    return '记住';
  }
  return '简单';
}

/// Hue for one rating token. The two-rating bottom bar no longer calls this —
/// it uses the explicit `COLOR_AGAIN*` / `COLOR_GOOD*` pairs — but the mapping
/// stays because a four-rating surface would need exactly this and nothing else
/// in the file knows the engine's four tokens map onto these four hues.
export function ratingColor(rating: string): string {
  if (rating === RATING_AGAIN) {
    return COLOR_AGAIN;
  }
  if (rating === RATING_HARD) {
    return COLOR_HARD;
  }
  if (rating === RATING_GOOD) {
    return COLOR_GOOD;
  }
  return COLOR_EASY;
}

export interface AnkiReviewerSettlement {
  total?: number;
  remembered?: number;
  forgotten?: number;
  seconds?: number;
  xp?: number;
}

export function settlementSecondsText(seconds: number): string {
  const minutes: number = Math.floor(seconds / 60);
  const rest: number = seconds % 60;
  const minuteText: string = minutes > 0 ? String(minutes) + '分' : '';
  return minuteText + String(rest) + '秒';
}

@Component
export struct AnkiReviewerHeaderBar {
  @Prop themeName: string = 'day';
  @Prop progressIndex: number = 0;
  @Prop progressTotal: number = 0;
  @Prop previewOnly: boolean = false;
  @Prop hasAudio: boolean = false;
  @Prop booted: boolean = false;
  @Prop presentPending: boolean = false;
  @Prop isComplete: boolean = false;
  @Prop advanceStuck: boolean = false;

  /// D8: a redo / bury / suspend is in flight. Kept separate from
  /// `presentPending` because they answer different questions — that one means
  /// "a card is rendering", this one means "the queue is being mutated".
  @Prop mutating: boolean = false;
  onReplayAudio: () => void = (): void => {};
  onUndo: () => void = (): void => {};
  onRedo: () => void = (): void => {};
  onBury: () => void = (): void => {};
  onSuspend: () => void = (): void => {};
  onRequestExit: () => void = (): void => {};

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.themeName);
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
        Text(this.previewOnly
          ? '预览'
          : (this.progressTotal > 0
            ? String(this.progressIndex) + '/' + String(this.progressTotal)
            : '—'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textSecondary)
        Blank()
        if (this.hasAudio) {
          Button('重播')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(32)
            .enabled(this.booted && !this.presentPending && !this.isComplete)
            .onClick((): void => {
              this.onReplayAudio();
            })
        }
        if (!this.previewOnly) {
          Button('撤销')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(32)
            .enabled(this.booted && !this.isComplete && !this.advanceStuck)
            .onClick((): void => {
              this.onUndo();
            })
        }
        Button('✕')
          .fontSize(15)
          .fontColor(this.palette().textSecondary)
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 8 })
          .height(32)
          .onClick((): void => {
            this.onRequestExit();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8 })
      .margin({ top: 4, bottom: 2 })

      // D8: the three queue mutations Android puts in its session toolbar
      // (`_AnkiSessionToolbar`), in its position — a strip above the card,
      // right-aligned, plain text at the same weight as the rest of the
      // chrome. Undo stays up in the count row because that is also where
      // Android keeps it (`ReviewProgressHeader`); the split is deliberate,
      // not an oversight.
      //
      // Hidden in preview: a preview has no session to mutate, and the
      // receipts would all come back "not available".
      if (!this.previewOnly) {
        Row() {
          Blank()
          Button('重做')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(30)
            .enabled(this.booted && !this.isComplete && !this.mutating && !this.presentPending)
            .onClick((): void => {
              this.onRedo();
            })
          Button('搁置')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(30)
            .enabled(this.booted && !this.isComplete && !this.mutating && !this.presentPending)
            .onClick((): void => {
              this.onBury();
            })
          Button('暂停')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(30)
            .enabled(this.booted && !this.isComplete && !this.mutating && !this.presentPending)
            .onClick((): void => {
              this.onSuspend();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 8 })
        .margin({ bottom: 2 })
      }
    }
    .width('100%')
  }
}

@Component
export struct AnkiReviewerStatusArea {
  @Prop themeName: string = 'day';
  @Prop presentPending: boolean = false;
  @Prop isComplete: boolean = false;
  @Prop confirmExit: boolean = false;
  @Prop previewOnly: boolean = false;
  @Prop avHint: string = '';
  @Prop errorCode: string = '';
  @Prop errorFatal: boolean = false;
  @Prop statusText: string = '';
  @Prop debugChrome: boolean = false;
  @Prop advanceStuck: boolean = false;
  @Prop booted: boolean = false;

  /// D9: cards still owed, counted the same way Android's
  /// `ReviewSessionController.remainingCount` counts them — the current card
  /// included, because it is still unanswered.
  @Prop remainingCount: number = 0;
  onRetryOrReconnect: () => void = (): void => {};
  onExitEarly: () => void = (): void => {};

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.themeName);
  }

  build() {
    Column() {
      if (this.presentPending && !this.isComplete && this.errorCode.length === 0) {
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

      if (this.confirmExit && !this.isComplete) {
        // D9: the count is the point. Android's exit dialog says how much is
        // left (`reviewExitConfirmBody(remaining)`); a confirmation that only
        // says "are you sure" asks the learner to price a decision without
        // telling them what it costs. The mechanism hint stays because the
        // shape here is a two-step tap, not a dialog.
        Text(this.previewOnly
          ? '再按一次返回或 ✕ 结束预览'
          : (this.remainingCount > 0
            ? '还剩 ' + String(this.remainingCount) +
              ' 张未完成，再按一次返回或 ✕ 结束复习（已评分的卡片会保留）'
            : '再按一次返回或 ✕ 结束复习（已评分的卡片会保留）'))
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }

      if (this.avHint.length > 0 && this.errorCode.length === 0) {
        Text(this.avHint)
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
      }

      if (this.errorCode.length > 0) {
        Column() {
          Text(this.statusText)
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
                  .onClick((): void => {
                    this.onRetryOrReconnect();
                  })
              }
              Button('退出复习')
                .fontSize(14)
                .fontColor(this.palette().textSecondary)
                .backgroundColor(Color.Transparent)
                .borderRadius(8)
                .height(36)
                .layoutWeight(1)
                .onClick((): void => {
                  this.onExitEarly();
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
      } else if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.palette().textHint)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }
    }
    .width('100%')
  }
}

@Component
export struct AnkiReviewerTypedBar {
  @Prop themeName: string = 'day';
  @Prop typedText: string = '';
  @Prop typedFrozen: boolean = false;
  @Prop presentPending: boolean = false;
  @Prop textZoom: number = 100;
  onTypedChange: (nextText: string) => void = (_nextText: string): void => {};
  onSubmitAnswer: () => void = (): void => {};

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.themeName);
  }

  build() {
    Column() {
      Divider()
        .color(this.palette().divider)
        .margin({ left: 16, right: 16 })
      TextInput({ text: this.typedText, placeholder: '输入你的答案' })
        .enabled(!this.typedFrozen && !this.presentPending)
        .fontSize(Math.round(15 * this.textZoom / 100))
        .enterKeyType(EnterKeyType.Done)
        .onSubmit((): void => {
          if (!this.typedFrozen) {
            this.onSubmitAnswer();
          }
        })
        .onChange((nextText: string): void => {
          this.onTypedChange(nextText);
        })
        .backgroundColor(this.palette().surface)
        .borderRadius(10)
        .height(44)
        .margin({ left: 16, right: 16, top: 10 })
    }
    .width('100%')
  }
}

@Component
export struct AnkiReviewerBottomBar {
  @Prop themeName: string = 'day';
  @Prop isComplete: boolean = false;
  @Prop advanceStuck: boolean = false;
  @Prop answerLanded: boolean = false;
  @Prop previewOnly: boolean = false;
  @Prop ratingSent: boolean = false;
  @Prop presentPending: boolean = false;
  @Prop statusText: string = '';
  @Prop settleTotal: number = -1;
  @Prop settleRemembered: number = -1;
  @Prop settleForgotten: number = -1;
  @Prop settleSeconds: number = -1;
  @Prop settleXp: number = -1;
  onShowAnswer: () => void = (): void => {};
  onShowQuestion: () => void = (): void => {};
  onRate: (rating: string) => void = (_rating: string): void => {};
  onRetryAdvance: () => void = (): void => {};
  onFinishComplete: () => void = (): void => {};
  onExitEarly: () => void = (): void => {};

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.themeName);
  }

  build() {
    Column() {
      if (this.isComplete) {
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
            .onClick((): void => {
              this.onFinishComplete();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      } else if (this.advanceStuck) {
        Column() {
          Text(this.statusText)
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
              .onClick((): void => {
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
              .onClick((): void => {
                this.onExitEarly();
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
          .onClick((): void => {
            this.onShowAnswer();
          })
      } else if (this.previewOnly) {
        Row() {
          Button(this.presentPending ? '正在翻回…' : '显示正面')
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor(this.palette().textPrimary)
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .border({ width: 1, color: this.palette().divider })
            .margin({ right: 6 })
            .enabled(!this.presentPending)
            .onClick((): void => {
              this.onShowQuestion();
            })
          Button('完成预览')
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(COLOR_GOOD)
            .fontColor(Color.White)
            .borderRadius(12)
            .margin({ left: 6 })
            .onClick((): void => {
              this.onFinishComplete();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
        .margin({ top: 10, bottom: 16 })
      } else if (this.ratingSent) {
        // UI-8: one honest "submitted, loading" state instead of inert rating
        // buttons that give no reason. Same height as the rating row so the
        // swap does not shift the layout under the learner's finger.
        Button('已提交，加载中…')
          .width('100%')
          .height(52)
          .fontSize(15)
          .fontColor(this.palette().textHint)
          .backgroundColor(this.palette().divider)
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 10, bottom: 16 })
          .enabled(false)
      } else {
        // Two ratings, matching Android's `BinaryRecallBar`: both are a tinted
        // fill with a same-hue border, neither is promoted. The four-button row
        // made `good` the hero (wider, filled, taller) — with only two choices
        // that hierarchy has nothing to contrast against and reads as an
        // uneven, misaligned pair.
        Row() {
          Button(ratingLabel(RATING_AGAIN))
            .layoutWeight(1)
            .height(52)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(COLOR_AGAIN_TINT)
            .fontColor(COLOR_AGAIN)
            .borderRadius(16)
            .border({ width: 1.5, color: COLOR_AGAIN_EDGE })
            .margin({ right: 6 })
            .animation({ duration: 150, curve: Curve.EaseOut })
            .onClick((): void => {
              this.onRate(RATING_AGAIN);
            })
          Button(ratingLabel(RATING_GOOD))
            .layoutWeight(1)
            .height(52)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(COLOR_GOOD_TINT)
            .fontColor(COLOR_GOOD)
            .borderRadius(16)
            .border({ width: 1.5, color: COLOR_GOOD_EDGE })
            .margin({ left: 6 })
            .animation({ duration: 150, curve: Curve.EaseOut })
            .onClick((): void => {
              this.onRate(RATING_GOOD);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
        .margin({ top: 10, bottom: 16 })
      }
    }
    .width('100%')
  }
}
