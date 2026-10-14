// Copyright (c) 2024 Turna. All rights reserved.
//
// ADR 0050 §6 step 5b — the probe page.
//
// A `Web` and nothing else. There is no card UI here on purpose: this page
// exists to answer one question (can ArkUI `Web` satisfy the reviewer's CSP +
// custom scheme + media Range) before anyone builds a reviewer on top of the
// answer. Every visible affordance is diagnostic.
//
// The `Web` is driven from two sides at once. `onInterceptRequest` answers the
// synthetic `https://anki.local` origin, and a JavaScript proxy carries the
// page's own account of what happened back out. Neither is trusted alone: the
// page's claims are cross-checked against the request transcript in
// `AnkiOriginServerProbe`, because a page that failed to load anything still
// executes and can still say "everything worked".

import { webview } from '@kit.ArkWeb';
import { AnkiOriginServerProbe } from '../anki/AnkiOriginServerProbe';
import { AnkiProbeBridge } from '../anki/AnkiProbeBridge';
import { AnkiProbeReport } from '../anki/AnkiProbeReport';

const SHELL_URL: string = 'https://anki.local/assets/shell.html';

interface AnkiProbePageVerdict {
  shellSubresource: string;
  frame: string;
  cspConnect: string;
  audioState: string;
  seekPhase: string;
  seekPlaying?: boolean;
  seekReadBack?: number;
}

@Entry
@Component
struct AnkiReviewerProbePage {
  private probeWeb: webview.WebviewController = new webview.WebviewController();
  private bridge: AnkiProbeBridge = new AnkiProbeBridge();
  @State probeSrc: string = SHELL_URL;
  @State probeVerdict: string = 'running';
  @State probeTranscript: string = '';
  @State probeDetail: string = '';

  aboutToAppear(): void {
    this.probeVerdict = 'running';
    this.probeTranscript = '';
    this.probeDetail = '';
    this.bridge.attach((raw: string): void => {
      this.probeVerdict = raw;
      this.probeTranscript = AnkiProbeReport.server().transcript();
      this.probeDetail = this.summarise(raw);
      AnkiProbeReport.submit(raw);
    });
  }

  private handleIntercept(event: OnInterceptRequestEvent): WebResourceResponse {
    const server: AnkiOriginServerProbe = AnkiProbeReport.server();
    return server.respond(
      event.request.getRequestUrl(),
      event.request.getRequestMethod(),
      event.request.getRequestHeader(),
    );
  }

  /// Turns the raw JSON into the four one-word answers the receipt needs.
  /// Kept separate from the raw text so a reader who only skims this page
  /// still cannot mistake "the page said so" for "the kernel agreed".
  private summarise(raw: string): string {
    try {
      const verdict: AnkiProbePageVerdict = JSON.parse(raw) as AnkiProbePageVerdict;
      const server: AnkiOriginServerProbe = AnkiProbeReport.server();
      const scheme: string = verdict.shellSubresource === 'loaded' && server.servedShell() ? 'ok' : 'FAIL';
      const frame: string = verdict.frame === 'loaded' ? 'ok' : 'FAIL';
      const csp: string = verdict.cspConnect === 'blocked' && server.cspFetchBlocked() ? 'ok' : 'FAIL';
      const seekTime: number = verdict.seekReadBack ?? -1;
      const range: string = verdict.audioState === 'ready' && verdict.seekPhase === 'done' &&
        verdict.seekPlaying === true && seekTime >= 1 && seekTime <= 2.5 &&
        server.mediaRangeVerified() ? 'ok' : 'FAIL';
      return 'scheme=' + scheme + ' frame=' + frame + ' csp=' + csp + ' range=' + range;
    } catch (error) {
      return 'scheme=FAIL frame=FAIL csp=FAIL range=FAIL invalid_json';
    }
  }

  build() {
    Column() {
      Text('Anki reviewer probe — ADR 0050 step 5b')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
      Text(this.probeDetail.length > 0 ? this.probeDetail : this.probeVerdict)
        .fontSize(14)
        .width('100%')
        .margin({ top: 6 })
      Button('PLAY + SEEK')
        .fontSize(13)
        .width('100%')
        .margin({ top: 6 })
        .onClick((): void => {
          // Phase 4b needs a real user gesture. ArkUI `Web` on this SDK has no
          // autoplay attribute, so `play()` from script is refused — which
          // makes a tap the only way to ask whether a *playing* element will
          // seek. Without it the answer would be "a paused element did not
          // seek", which is not the question.
          this.probeWeb
            .runJavaScript('(function(){ return window.__probeSeek ? window.__probeSeek() : "absent"; })()')
            .catch(() => {
              this.probeDetail = 'runJavaScript failed';
            });
        })
      Text(this.probeTranscript)
        .fontSize(11)
        .width('100%')
        .margin({ top: 6 })
      Web({ src: this.probeSrc, controller: this.probeWeb })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .fileAccess(false)
        .javaScriptProxy({
          object: this.bridge,
          name: 'AnkiProbeNative',
          methodList: ['report'],
          controller: this.probeWeb
        })
        .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse => {
          return this.handleIntercept(event);
        })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
  }
}
