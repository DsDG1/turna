// Copyright (c) 2024 Turna. All rights reserved.
//
// The seam between the probe page and the ability that launched it.
//
// `windowStage.loadContent` takes a path, not an instance, so the page cannot
// be handed the origin server or a completion callback by parameter. Everything
// that has to cross that boundary goes through here instead: one module-level
// instance, armed by the ability before it loads the page, read by the page
// while it intercepts requests, and answered by whoever armed it.
//
// The server lives here rather than in the page so that the transcript the
// ability reports is the *same* object the page's `onInterceptRequest` wrote to.
// If the ability kept its own copy, the cross-check between the page's claim
// and what the kernel actually requested would be checking two different things.

import { hilog } from '@kit.PerformanceAnalysisKit';
import { AnkiOriginServerProbe } from './AnkiOriginServerProbe';

const TAG: string = 'AnkiReviewerProbe';

export class AnkiProbeReport {
  private static sink: ((text: string) => void) | undefined = undefined;
  private static origin: AnkiOriginServerProbe = new AnkiOriginServerProbe();
  private static reported: boolean = false;

  /// Called by the ability before `loadContent`. The sink receives the final
  /// verdict string; the ability turns it into a `MethodResult`.
  public static arm(sink: (text: string) => void): void {
    AnkiProbeReport.sink = sink;
    AnkiProbeReport.reported = false;
    AnkiProbeReport.origin = new AnkiOriginServerProbe();
  }

  /// The one interception handler for this probe run. The page's
  /// `onInterceptRequest` and the ability's transcript must be the same object.
  public static server(): AnkiOriginServerProbe {
    return AnkiProbeReport.origin;
  }

  public static pageReported(): boolean {
    return AnkiProbeReport.reported;
  }

  /// Called by the page once its JS has run out of things to test. Carries
  /// both witnesses — what the page believes and what the server recorded — so
  /// the reader can see the two disagree rather than being handed a summary.
  public static submit(pageJson: string): void {
    AnkiProbeReport.reported = true;
    const origin: AnkiOriginServerProbe = AnkiProbeReport.origin;
    const text: string = 'page={' + pageJson + '} ' + origin.transcript();
    hilog.info(0x0000, TAG, 'verdict %{public}s', text);
    const sink = AnkiProbeReport.sink;
    if (sink === undefined) {
      hilog.warn(0x0000, TAG, 'probe reported with no ability attached; dropping verdict');
      return;
    }
    sink(text);
  }

  /// The instance the injected JS proxy registers. Kept as its own class
  /// because ArkTS exposes only the listed public methods of this object to
  /// the page, and the ability must not be reachable from page script.
  public report(pageJson: string): void {
    AnkiProbeReport.submit(pageJson);
  }
}
