// Copyright (c) 2024 Turna. All rights reserved.
//
// The reviewer's ability. A separate ability rather than another entry in
// `main_pages.json`: `@ohos.router` is deprecated from API 18 and this hap
// declares 5.1.0(18), which is what pushed the reviewer across an ability
// boundary in the first place (see ADR 0047 §5.7).
//
// Its whole job is to turn a Want into a session. The session is handed over
// through a process-wide handle in `AnkiReviewerPage`, because the Dart side
// reaches the page through the plugin in `EntryAbility` — a different ability —
// and ArkUI abilities in one hap share a process.
//
// The `mediaRoot` arrives on the Want because only Dart knows where the
// collection put its media folder, and a reviewer that guessed would either
// serve nothing or serve from the wrong collection.
//
// B6: the ability is declared `singleton` (the platform default, now stated
// explicitly). A relaunch onto the living instance routes through
// `onNewWant` instead of `onCreate`, and without this handler the new Want —
// and its `mediaRoot` — was silently dropped, leaving the page serving the
// previous collection's media from the background. The handler rebuilds the
// session and reloads the page: a fresh page re-runs `onPageEnd`, which is
// what marks the (new) session shell-ready.

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AnkiReviewerSession } from '../anki/AnkiReviewerSession';
import {
  beginReviewerSession,
  endReviewerSession,
} from '../anki/AnkiReviewerSessionStore';

const TAG: string = 'AnkiReviewerAbility';
const DOMAIN: number = 0xA700;

export default class AnkiReviewerAbility extends UIAbility {
  private mediaRoot: string = '';
  private session: AnkiReviewerSession | undefined = undefined;
  private windowStage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const given: string | undefined = want.parameters?.mediaRoot as string | undefined;
    if (given === undefined || given.length === 0) {
      // Refusing loudly beats starting a reviewer that answers every media
      // request with 403: the first looks like a broken app and the second
      // looks like broken cards.
      hilog.error(DOMAIN, TAG, 'mediaRoot missing from want');
      return;
    }
    this.mediaRoot = given;
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const given: string | undefined = want.parameters?.mediaRoot as string | undefined;
    if (given === undefined || given.length === 0) {
      // Keep the live session rather than half-rebuilding one: an empty root
      // would answer every media request with 403, which is worse than the
      // previous collection's (valid) media.
      hilog.error(DOMAIN, TAG, 'mediaRoot missing from new want; keeping the live session');
      return;
    }
    if (this.windowStage === undefined) {
      // The instance is alive before its window: fall back to storing the
      // root; onWindowStageCreate will build the session from it.
      this.mediaRoot = given;
      return;
    }
    hilog.info(DOMAIN, TAG, 'relaunching reviewer session, mediaRoot=%{public}s', given);
    this.mediaRoot = given;
    this.session = beginReviewerSession(given);
    this.loadReviewerPage();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    if (this.mediaRoot.length === 0) {
      // onCreate already refused the want; loading the page anyway would build
      // a reviewer whose every media answer is a lie, so stop here instead.
      hilog.error(DOMAIN, TAG, 'no mediaRoot on want; refusing to load the reviewer page');
      return;
    }
    // The session has to exist before loadContent, not in its callback: the
    // page's build — and the Web's first request interception — run while the
    // content is still loading, while this callback fires only after it. With
    // the session created in the callback the interceptor captured an undefined
    // handle and the run died on "Cannot read property origin of undefined".
    this.session = beginReviewerSession(this.mediaRoot);
    this.loadReviewerPage();
  }

  private loadReviewerPage(): void {
    const stage: window.WindowStage | undefined = this.windowStage;
    if (stage === undefined) {
      return;
    }
    stage.loadContent('pages/AnkiReviewerPage', (err) => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'loadContent failed [%{public}d] %{public}s', err.code, err.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'reviewer session opened, mediaRoot=%{public}s', this.mediaRoot);
    });
  }

  onDestroy(): void {
    // B3: a store that only ever overwrites kept serving the destroyed
    // session to the next launch's `awaitReviewerReady` poll — which then
    // presented onto this page's dead Web controller.
    const session: AnkiReviewerSession | undefined = this.session;
    if (session !== undefined) {
      endReviewerSession(session);
      this.session = undefined;
    }
  }
}
