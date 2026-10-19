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
  CHROME_DARK,
  CHROME_HIGH_CONTRAST_DARK,
  CHROME_HIGH_CONTRAST_LIGHT,
  RATING_AGAIN,
  RATING_GOOD,
  THEME_NIGHT,
} from './AnkiReviewerProtocol';

export const EXIT_CONFIRM_WINDOW_MS: number = 2000;

/// UI-16: how long the native completion row stays on screen before it hands
/// the summary back to Flutter's `UnifiedReviewCompletion` (the component
/// Android shows).
///
/// Not zero: the ability vanishing the instant the last card is graded reads
/// as a crash. Not long: past ~1 s the learner starts reading a summary that
/// is about to be replaced, which is the two-completion-screens problem this
/// fixes.
export const COMPLETION_HANDOFF_MS: number = 600;

/// Brand chrome (UI-1/UI-5): Turna's peacock tokens mirrored from
/// `lib/core/theme.dart` — brandTeal #1F727E, brandSky #4A95A8, error
/// #E74C3C. The sky token paints the source badge, not a rating.
export const COLOR_AGAIN: string = '#E74C3C';
export const COLOR_GOOD: string = '#1F727E';
export const COLOR_SOURCE_BADGE: string = '#4A95A8';

/// Tint + edge pair for the two rating buttons, mirroring Android's
/// `_RecallButton`: one hue drives both, at 12% fill and 35% border. Written as
/// ARGB literals because ArkTS has no alpha helper that keeps the base hex
/// readable next to it. When the base token changes these must move with it.
export const COLOR_AGAIN_TINT: string = '#1FE74C3C';
export const COLOR_AGAIN_EDGE: string = '#59E74C3C';
export const COLOR_GOOD_TINT: string = '#1F1F727E';
export const COLOR_GOOD_EDGE: string = '#591F727E';

/// The progress track behind the header bar, drawn in brandTeal at 15% — the
/// same pair Android's `ReviewProgressHeader` passes to its
/// `LinearProgressIndicator` (`brandTeal.withValues(alpha: 0.15)` on a
/// `brandTeal` value color). On the dark palette a neutral divider reads as a
/// dead grey line next to the teal fill instead of an unfilled remainder.
export const COLOR_GOOD_TRACK: string = '#261F727E';

/// True for the palettes whose surfaces are dark. Drives the system bar glyph
/// color: white glyphs on a dark bar, black glyphs on a light one.
export function isDarkTheme(themeName: string): boolean {
  return themeName === CHROME_DARK ||
    themeName === CHROME_HIGH_CONTRAST_DARK ||
    themeName === THEME_NIGHT;
}

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

/// Night chrome, taken from the app's own dark tokens rather than invented.
///
/// Night is a **neutral black ramp**, not a green one. The page is
/// `TurnaTheme.darkScaffold` (`#000000`), raised surfaces are `cardBg`
/// (`#141414`), rules are `dividerBg` (`#2A2A2A`), and the error tint matches
/// Flutter's `dangerSurface`. Brand hue stays in the accents.
///
/// History: these four used to be `#10181B` / `#1A2327` / `#2A3438` /
/// `#A5B4B7` — a blue-grey family that existed nowhere in
/// `lib/core/theme.dart`, so the reviewer's night mode was a different colour
/// from every page around it. They were then aligned to the old green-tinted
/// tokens and are now aligned to the neutral black ramp in one move.
export function nightPalette(): AnkiChromePalette {
  const palette: AnkiChromePalette = {
    bg: '#000000',
    surface: '#141414',
    textPrimary: '#E9F2EC',
    textSecondary: '#B9CCC0',
    textHint: '#84998C',
    divider: '#2A2A2A',
    errorTint: '#1A1212',
  };
  return palette;
}

/// UI-15: high-contrast light. Values mirror
/// `TurnaTheme._buildHighContrastLight` — pure white surfaces, pure black
/// text, and the same 54%-black divider the Flutter theme uses. Before this
/// the native chrome had two palettes, so turning on 高对比度 changed every
/// screen except the reviewer.
export function highContrastLightPalette(): AnkiChromePalette {
  const palette: AnkiChromePalette = {
    bg: '#FFFFFF',
    surface: '#FFFFFF',
    textPrimary: '#000000',
    textSecondary: '#1A1A2E',
    textHint: '#2D2D44',
    divider: '#8A000000',
    errorTint: '#FFE0DC',
  };
  return palette;
}

/// UI-15: high-contrast dark. Values mirror
/// `TurnaTheme._buildHighContrastDark` — pure black surfaces, pure white
/// text, white-38% divider.
export function highContrastDarkPalette(): AnkiChromePalette {
  const palette: AnkiChromePalette = {
    bg: '#000000',
    surface: '#000000',
    textPrimary: '#FFFFFF',
    textSecondary: '#E6E6E6',
    textHint: '#CCCCCC',
    divider: '#61FFFFFF',
    errorTint: '#3A2321',
  };
  return palette;
}

/// Pick the palette for a theme token.
///
/// Accepts both vocabularies on purpose: `day`/`night` are the card frame's
/// tokens and arrive on the first present before Dart has sent a
/// `chromeTheme`, while `light`/`dark`/`highContrast*` are the four Flutter
/// variants. An unknown token falls back to day, never to a crash.
export function paletteForTheme(themeName: string): AnkiChromePalette {
  if (themeName === CHROME_HIGH_CONTRAST_LIGHT) {
    return highContrastLightPalette();
  }
  if (themeName === CHROME_HIGH_CONTRAST_DARK) {
    return highContrastDarkPalette();
  }
  if (themeName === CHROME_DARK || themeName === THEME_NIGHT) {
    return nightPalette();
  }
  return dayPalette();
}

/// Label wording follows Android's `AppStrings.reviewBinaryForgotten` /
/// `reviewBinaryRemembered`. The bottom bar only offers again and good.
/// Anything else has no label.
export function ratingLabel(rating: string): string {
  if (rating === RATING_AGAIN) {
    return '忘记';
  }
  if (rating === RATING_GOOD) {
    return '记住';
  }
  return '';
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

  /// UI-15: the Review All badge text (`3/5 · deckName`), empty outside
  /// Review All. Same string the Android `_AnkiSessionToolbar` renders.
  @Prop sourceProgress: string = '';

  onReplayAudio: () => void = (): void => {};
  onRequestExit: () => void = (): void => {};

  private palette(): AnkiChromePalette {
    return paletteForTheme(this.themeName);
  }

  build() {
    Column() {
      // Same single-row shape as Android's `ReviewProgressHeader`: close on the
      // left, the bar taking the whole middle, the count on the right. The
      // previous layout stacked a 3 vp bar above a row, which on a phone put
      // the bar hard against the status bar and left the count and the close
      // key floating on their own line — a header that was 2/3 empty and read
      // as a stray teal dash rather than progress.
      Row() {
        Button('✕')
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .fontSize(17)
          .fontColor(this.palette().textSecondary)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.onRequestExit();
          })

        Progress({
          value: this.progressTotal > 0 ? this.progressIndex : 0,
          total: this.progressTotal > 0 ? this.progressTotal : 1,
          type: ProgressType.Linear,
        })
          .color(COLOR_GOOD)
          .backgroundColor(COLOR_GOOD_TRACK)
          .height(6)
          .borderRadius(3)
          .clip(true)
          .layoutWeight(1)

        Text(this.previewOnly
          ? '预览'
          : (this.progressTotal > 0
            ? String(this.progressIndex) + ' / ' + String(this.progressTotal)
            : '—'))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().textSecondary)
          .margin({ left: 12 })

        if (this.hasAudio) {
          Button('重播')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8, right: 8 })
            .height(32)
            .margin({ left: 4 })
            .enabled(this.booted && !this.presentPending && !this.isComplete)
            .onClick((): void => {
              this.onReplayAudio();
            })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 12 })
      .alignItems(VerticalAlign.Center)

      // UI-15: the Review All source badge keeps the strip Android's
      // `_AnkiSessionToolbar` gives it. The four queue mutations that used to
      // share this row (undo / redo / bury / suspend) were removed; the badge
      // renders only when Dart sent one, so a single-deck session has no
      // empty strip.
      //
      // Restyled to Android's chip (`softTint(brandSky, 0.12)`, radius 12,
      // hairline border, sky-coloured bold label): the old full-width grey
      // pill used `textPrimary` on `divider`, which at night was the brightest
      // object on the screen and outweighed the card itself.
      if (!this.previewOnly && this.sourceProgress.length > 0) {
        Row() {
          Text(this.sourceProgress)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_SOURCE_BADGE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '100%' })
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(12)
            .backgroundColor('#1F4A95A8')
            .border({ width: 1, color: '#334A95A8' })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.Start)
        .margin({ bottom: 6 })
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
  /// UI-16: single-source session — the completion row hands the summary back
  /// to Flutter instead of showing its own and waiting for a tap.
  @Prop autoComplete: boolean = false;
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
          if (this.autoComplete) {
            // UI-16: the authoritative summary is Flutter's
            // `UnifiedReviewCompletion` — the same component Android shows,
            // already rendered underneath this ability. Repeating the numbers
            // here would be two summaries and a visible second screen; this
            // row is only the hand-off beat before the timer closes us.
            Text('正在打开结算…')
              .fontSize(13)
              .fontColor(this.palette().textSecondary)
              .margin({ top: 6 })
          } else if (this.settleTotal >= 0) {
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
          // Review All keeps the explicit button: its next source reuses this
          // ability, so only Dart may decide when to close.
          if (!this.autoComplete) {
            Button('完成')
              .width('100%')
              .height(50)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(COLOR_GOOD)
              .fontColor(Color.White)
              .borderRadius(16)
              .margin({ top: 12, bottom: 16 })
              .onClick((): void => {
                this.onFinishComplete();
              })
          }
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
              .borderRadius(16)
              .margin({ right: 6 })
              .onClick((): void => {
                this.onRetryAdvance();
              })
            Button('结束复习')
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .fontColor(this.palette().textSecondary)
              .borderRadius(16)
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
          .borderRadius(16)
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
            .borderRadius(16)
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
            .borderRadius(16)
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
          .borderRadius(16)
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
