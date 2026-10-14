// Copyright (c) 2024 Turna. All rights reserved.
//
// ADR 0050 §6 step 5b — the ability that hosts the probe page.
//
// Route E replaced an embedded PlatformView with a full native page, which
// means something ADR 0050 never listed as an assumption became load-bearing:
// **that a Flutter plugin can put a native page on screen and get an answer
// back**. That is receipt R0, and it is not free — `@ohos.router` has been
// deprecated since API 18, so the page is reached through
// `startAbilityForResult` instead, which is a different mechanism than the one
// the original route assumed. If this ability never returns, route E has no
// proven delivery and the reviewer cannot be built on it.
//
// The ability owns the outcome. The page reports what it can; this decides
// when the run is over, and reports a verdict even when the page never
// reported at all — a silent probe and a probe that failed are different
// findings and must not look the same.

import { AbilityConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AnkiProbeReport } from '../anki/AnkiProbeReport';

const TAG: string = 'AnkiReviewerProbeAbility';
const PAGE: string = 'pages/AnkiReviewerProbePage';

/// Long enough for the whole run: the page's own 30 s "nobody tapped the seek
/// button" fallback sits just inside this, so an unattended run still reports
/// the three automatic answers instead of dying on the ability timeout. A
/// shorter value here would silently replace the page's verdict — which names
/// which check never settled — with an opaque one.
const PROBE_TIMEOUT_MS: number = 40000;

export default class AnkiReviewerProbeAbility extends UIAbility {
  private finished: boolean = false;
  private timer: number = -1;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    hilog.info(0x0000, TAG, 'probe ability created');
    AnkiProbeReport.arm((text: string): void => {
      this.finish(text);
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    super.onWindowStageCreate(windowStage);
    this.timer = setTimeout((): void => {
      this.finish(this.timeoutVerdict());
    }, PROBE_TIMEOUT_MS);
    windowStage.loadContent(PAGE, (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'loadContent failed, code: %{public}d', err.code);
        this.finish('loadContent_failed code=' + String(err.code) + ' msg=' + err.message);
      }
    });
  }

  onWindowStageDestroy(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    super.onWindowStageDestroy();
  }

  /// The page never called back. Say so in the same shape as a normal verdict
  /// so the two can be compared without special-casing the reader.
  private timeoutVerdict(): string {
    const reported: boolean = AnkiProbeReport.pageReported();
    const transcript: string = AnkiProbeReport.server().transcript();
    return 'page={} timedOut=true pageReported=' + String(reported) + ' ' + transcript;
  }

  private finish(verdict: string): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    hilog.info(0x0000, TAG, 'verdict %{public}s', verdict);
    const result: Record<string, Object> = { 'verdict': verdict };
    const want: Want = { parameters: result };
    const outcome: common.AbilityResult = { resultCode: 0, want: want };
    this.context
      .terminateSelfWithResult(outcome)
      .catch((error: Error) => {
        hilog.error(0x0000, TAG, 'terminateSelfWithResult failed: %{public}s', error.message);
      });
  }
}
