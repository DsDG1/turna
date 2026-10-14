// Copyright (c) 2024 Turna. All rights reserved.
//
// The HarmonyOS reviewer page — the visible half of ADR 0050 §6 step 5b.
//
// Layout is the whole interaction design here, so it is worth stating: the `Web`
// holds the card (question or answer, never both), the typed-answer field sits
// under it while the question is showing, and the bottom row is either one
// "show answer" button or the four rating buttons. ADR 0047 estimated 5–8
// person-days against an embedded PlatformView, which would have kept the
// Flutter chrome; route E gives that chrome up and puts it here, and the visible
// cost is losing the scrolling card list — every card is its own present.
//
// The typed answer is native, and that is the architecture rather than a
// HarmonyOS accommodation: `card-frame.js`'s `applyTyped` renders `[[type:…]]` as
// an empty placeholder span, so the frame never held an input to begin with.
// Every platform's input has always been native; route E moved the card, not the
// field.

import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { AnkiReviewerSession, interceptFor } from '../anki/AnkiReviewerSession';
import { reviewerSession } from '../anki/AnkiReviewerSessionStore';

const RATINGS: Array<string> = ['again', 'hard', 'good', 'easy'];

@Entry
@Component
struct AnkiReviewerPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private ready: boolean = false;
  @State private answerShown: boolean = false;
  @State private typedVisible: boolean = false;
  @State private typed: string = '';
  @State private typedFrozen: boolean = false;
  @State private seenCard: number = -1;
  @State private status: string = '';

  private alive: boolean = true;
  private bootAttempts: number = 0;
  private booted: boolean = false;

  aboutToAppear(): void {
    this.bootWhenSessionArrives();
  }

  /// Belt to `aboutToAppear`: the page can be prebuilt before the ability
  /// creates the session, and a prebuilt page's `aboutToAppear` may have given
  /// up before the session existed. `booted` keeps the two triggers from
  /// double-booting.
  onPageShow(): void {
    this.bootWhenSessionArrives();
  }

  /// Boots chrome and the asset preload the moment the session exists. Called
  /// from `aboutToAppear`, i.e. before the Web builds and asks the origin for
  /// the shell, so the preload has its head start over the kernel-driven
  /// initial load (the Web's `src` is the shell URL; no `loadUrl` is ever
  /// issued from here — every explicit-load timing tried on device lost a race
  /// to the initial navigation). A short poll covers the prebuild gap; past it,
  /// the status says so loudly rather than opening a reviewer that ignores
  /// every command.
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
      this.status = 'reviewer session missing';
      return;
    }
    this.booted = true;
    session.setChromeListener((answerShown: boolean, typedVisible: boolean, cardId: number): void => {
      if (cardId !== this.seenCard) {
        this.seenCard = cardId;
        this.typed = '';
        this.typedFrozen = false;
      }
      this.answerShown = answerShown;
      this.typedVisible = typedVisible;
    });
    session
      .start(getContext(this) as common.UIAbilityContext, this.controller)
      .then((report: string) => {
        this.ready = true;
        this.status = report;
      })
      .catch((e: Error) => {
        this.status = 'start failed: ' + e.message;
      });
  }

  aboutToDisappear(): void {
    this.alive = false;
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session !== undefined) {
      session.setChromeListener(undefined);
    }
  }

  private session(): AnkiReviewerSession | undefined {
    return reviewerSession();
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

  private onShowAnswer(): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    this.typedFrozen = true;
    session.channel().showAnswer(this.typed);
  }

  private onRate(rating: string): void {
    const session: AnkiReviewerSession | undefined = this.session();
    if (session === undefined) {
      return;
    }
    session.channel().rate(rating);
  }

  build() {
    Column() {
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

      if (this.typedVisible && !this.answerShown) {
        TextInput({ text: this.typed, placeholder: 'type your answer' })
          .enabled(!this.typedFrozen)
          .onChange((value: string) => {
            this.typed = value;
            const session: AnkiReviewerSession | undefined = this.session();
            if (session !== undefined) {
              session.channel().typedChanged(value);
            }
          })
          .width('100%')
          .margin({ top: 8, left: 12, right: 12 })
      }

      if (!this.answerShown) {
        Button('Show answer')
          .width('100%')
          .margin({ top: 8, left: 12, right: 12, bottom: 12 })
          .onClick(() => {
            this.onShowAnswer();
          })
      } else {
        Row() {
          ForEach(RATINGS, (rating: string) => {
            Button(rating)
              .layoutWeight(1)
              .margin({ right: rating === 'easy' ? 12 : 4 })
              .onClick(() => {
                this.onRate(rating);
              })
          }, (rating: string) => rating)
        }
        .width('100%')
        .padding({ left: 12 })
        .margin({ top: 8, bottom: 12 })
      }

      if (!this.ready) {
        Text(this.status).fontSize(11).margin({ left: 12, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
