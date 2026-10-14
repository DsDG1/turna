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

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { beginReviewerSession } from '../anki/AnkiReviewerSessionStore';

const TAG: string = 'AnkiReviewerAbility';
const DOMAIN: number = 0xA700;

export default class AnkiReviewerAbility extends UIAbility {
  private mediaRoot: string = '';

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

  onWindowStageCreate(windowStage: window.WindowStage): void {
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
    beginReviewerSession(this.mediaRoot);
    windowStage.loadContent('pages/AnkiReviewerPage', (err) => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'loadContent failed [%{public}d] %{public}s', err.code, err.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'reviewer session opened, mediaRoot=%{public}s', this.mediaRoot);
    });
  }
}