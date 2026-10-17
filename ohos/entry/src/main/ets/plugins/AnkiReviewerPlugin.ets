// Copyright (c) 2024 Turna. All rights reserved.
//
// The Official Anki reviewer's MethodChannel on HarmonyOS.
//
// Route E (ADR 0050 §3.1): the reviewer is a native page, not a PlatformView,
// because Dart cannot reference `Ohos*` under the official SDK and vendoring the
// framework to reach it is not a cost anyone accepts. What is left on this side
// of the channel is small — open the page, hand it a card, take a rating back —
// and all of it is here rather than in Dart, which is the whole reason the
// card HTML never has to cross into page script.
//
// Registered by hand in `EntryAbility` for the same reason as the other four:
// nothing in `pubspec.yaml` declares it, so `GeneratedPluginRegistrant` is
// regenerated from that list and would drop it on the next `pub get`.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Want, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { probeReviewerAssets } from '../probe/AnkiReviewerAssetProbe';
import { AnkiReviewerSession, RenderAck } from '../anki/AnkiReviewerSession';
import {
  reviewerSession,
  reviewerSessionEpoch,
  shellReadyAfter,
  subscribeShellReady,
} from '../anki/AnkiReviewerSessionStore';
import { attachReviewerOutbound } from '../anki/AnkiReviewerBridge';
import {
  ARG_BASE64,
  ARG_MEDIA_ROOT,
  ARG_NAME,
  ARG_PAYLOAD_JSON,
  ARG_SIDE,
  CHANNEL_NAME,
  METHOD_AWAIT_REVIEWER_READY,
  METHOD_CACHE_REVIEWER_MEDIA,
  METHOD_NOTIFY_REVIEWER_FAILURE,
  METHOD_OPEN_REVIEWER,
  METHOD_PRESENT_REVIEWER,
  METHOD_PROBE_REVIEWER_ASSETS,
  METHOD_PROBE_REVIEWER_CAPABILITIES,
  RENDER_ERROR,
} from '../anki/AnkiReviewerProtocol';
import hilog from '@ohos.hilog';

const TAG = "AnkiReviewerPlugin";

/// Shell load budget. One timer, not a poll: `markShellReady` wakes waiters.
const REVIEWER_READY_TIMEOUT_MS: number = 8000;

// The probe's ability. Renamed with the probe when step 5b lands the real
// reviewer; the Dart-visible channel name is already the final one so this
// rename stays invisible to Dart.
const PROBE_ABILITY = "AnkiReviewerProbeAbility";

// The reviewer. Distinct from the probe ability on purpose: the probe is a
// diagnostic that opens a synthetic page, and this one is the product's card
// surface. Keeping them apart means a reviewer regression cannot be mistaken
// for the probe failing — they have different code, different origins and
// different failure modes.
const REVIEWER_ABILITY = "AnkiReviewerAbility";

export default class AnkiReviewerPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  // Injected rather than discovered: `startAbilityForResult` needs a real
  // UIAbilityContext, and a FlutterPluginBinding only hands out an
  // ApplicationContext. Same reason `FilePickerPlugin` takes one.
  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return "AnkiReviewerPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    attachReviewerOutbound(this.channel);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        // An if/else chain over the protocol constants rather than a switch:
        // the method names are the wire contract, so they come from
        // AnkiReviewerProtocol.ets, whose mirror the protocol guard test
        // pins against the Dart side.
        if (call.method === METHOD_PROBE_REVIEWER_CAPABILITIES) {
          this.probeReviewerCapabilities(result);
        } else if (call.method === METHOD_PROBE_REVIEWER_ASSETS) {
          this.probeReviewerAssets(result);
        } else if (call.method === METHOD_OPEN_REVIEWER) {
          this.openReviewer(result, call);
        } else if (call.method === METHOD_PRESENT_REVIEWER) {
          this.presentReviewer(result, call);
        } else if (call.method === METHOD_CACHE_REVIEWER_MEDIA) {
          this.cacheReviewerMedia(result, call);
        } else if (call.method === METHOD_AWAIT_REVIEWER_READY) {
          this.awaitReviewerReady(result);
        } else if (call.method === METHOD_NOTIFY_REVIEWER_FAILURE) {
          this.notifyReviewerFailure(result, call);
        } else {
          result.notImplemented();
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    attachReviewerOutbound(null);
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  // Receipt R0 for step 5b: a Flutter plugin can put a native page on screen
  // and get an answer back out. Returns the ability's verdict verbatim — no
  // interpretation here, because the reader needs the raw transcript and not a
  // summary this file chose the terms of.
  private probeReviewerCapabilities(result: MethodResult): void {
    // The Want mirrors exactly what `aa start -a … -b … -m …` puts on the wire.
    // Naming only `abilityName` answers `16000001 "The specified ability does
    // not exist"` for an ability the system has registered — verified on device
    // against `bm dump`, which listed it while the launch still failed, and
    // `aa start` with all three fields succeeded on the same build. So the
    // declaration was never in question; the addressing was.
    const info = this.context.abilityInfo;
    const want: Want = {
      bundleName: info.bundleName,
      moduleName: info.moduleName,
      abilityName: PROBE_ABILITY,
    };
    this.context
      .startAbilityForResult(want)
      .then((abilityResult: common.AbilityResult): void => {
        result.success(extractVerdict(abilityResult));
      })
      .catch((error: BusinessError): void => {
        // The code, not the message: it is the only thing that distinguishes a
        // bad address from a refused launch. Echoed through the Dart error
        // because this app's ArkTS hilog does not reach the device log.
        result.error(
          'PROBE_LAUNCH_FAILED',
          'want=' + String(want.bundleName) + '/' + String(want.moduleName) + '/' +
            String(want.abilityName) + ' code=' + String(error.code) + ' ' + error.message,
          null,
        );
      });
  }

  /**
   * Whether the reviewer ability's asset source actually reads on this platform.
   *
   * Separate from `probeReviewerCapabilities` because it answers a different
   * question and needs no screen: the capabilities probe says the `Web` component
   * can host the CSP-pinned card frame, this says whether the bytes that frame
   * asks for can be produced at all. A reviewer built on a wrong answer here
   * renders an empty page and no amount of `Web` capability compensates.
   *
   * The answer comes back raw — per-asset `name=bytes` or `name!err<code>` —
   * because the reader has to tell "everything is missing" apart from "only the
   * 2.27 MB MathJax is missing", and a summary chosen here would erase that.
   */
  private probeReviewerAssets(result: MethodResult): void {
    probeReviewerAssets(this.context)
      .then((report: string) => {
        result.success(report);
      })
      .catch((error: BusinessError): void => {
        result.error(
          'ASSET_PROBE_FAILED',
          'code=' + String(error.code) + ' ' + error.message,
          null,
        );
      });
  }

  /**
   * Opens the reviewer, carrying `mediaRoot` on the Want.
   *
   * The Want is the whole delivery mechanism for it, and that is deliberate:
   * the media folder is Dart's to know, and routing it through a process-wide
   * setter would mean a reviewer could come up pointing at the previous
   * collection's media.
   */
  private openReviewer(result: MethodResult, call: MethodCall): void {
    const mediaRoot: string = call.argument(ARG_MEDIA_ROOT) as string;
    if (!mediaRoot) {
      result.error('MEDIA_ROOT_MISSING', 'mediaRoot argument absent', null);
      return;
    }
    const info = this.context.abilityInfo;
    const want: Want = {
      bundleName: info.bundleName,
      moduleName: info.moduleName,
      abilityName: REVIEWER_ABILITY,
      parameters: { mediaRoot: mediaRoot },
    };
    this.context
      .startAbilityForResult(want)
      .then((abilityResult: common.AbilityResult): void => {
        result.success(extractVerdict(abilityResult));
      })
      .catch((error: BusinessError): void => {
        result.error(
          'REVIEWER_LAUNCH_FAILED',
          'code=' + String(error.code) + ' ' + error.message,
          null,
        );
      });
  }

  /**
   * One card, one side. Resolves with the frame's own ack, which is what lets
   * Dart tell "the card drew" from "the card gave up" — the difference between
   * showing the answer and advancing past a card that never rendered.
   */
  private presentReviewer(result: MethodResult, call: MethodCall): void {
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session === undefined) {
      result.error('REVIEWER_NOT_OPEN', 'no reviewer session in this process', null);
      return;
    }
    const payloadJson: string = call.argument(ARG_PAYLOAD_JSON) as string;
    const side: string = call.argument(ARG_SIDE) as string;
    if (!payloadJson || !side) {
      result.error('PRESENT_ARGS_MISSING', 'payloadJson/side absent', null);
      return;
    }
    session
      .present(payloadJson, side)
      .then((ack: RenderAck) => {
        result.success(JSON.stringify(ack));
      })
      .catch((e: Error) => {
        result.error('PRESENT_FAILED', e.message, null);
      });
  }

  /// Dart pushes the current card's small media here, base64, before `present`.
  ///
  /// Files at or under 256 KB are served from this cache. Larger files, and
  /// names Dart did not push, are read in `AnkiOriginServer.readFileSlice`
  /// because `onInterceptRequest` cannot await a MethodChannel round-trip.
  /// A failed read is `MEDIA_READ_FAILED`. It is not reported as a cache miss.
  private cacheReviewerMedia(result: MethodResult, call: MethodCall): void {
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session === undefined) {
      result.error('REVIEWER_NOT_OPEN', 'no reviewer session in this process', null);
      return;
    }
    const name: string = call.argument(ARG_NAME) as string;
    const base64: string = call.argument(ARG_BASE64) as string;
    if (!name || !base64) {
      result.error('MEDIA_ARGS_MISSING', 'name/base64 absent', null);
      return;
    }
    session.origin().cacheMedia(name, base64);
    result.success('');
  }

  /// Resolves when the reviewer shell has loaded, or after 8 seconds.
  ///
  /// [openReviewer] cannot be this signal: it resolves only when the learner
  /// closes the ability. Presenting before the shell's script exists runs
  /// `OfficialReviewer.present` against a document that does not have it.
  ///
  /// B3: only a session BEGUN AFTER this call counts. The previous
  /// session used to satisfy the wait — destroyed ability, stale store entry,
  /// `shellReady` still true — and Dart then presented onto a dead Web
  /// controller as the "second review opens broken" bug. The epoch is
  /// captured at entry, which is safe here by construction: this call is
  /// issued milliseconds after `openReviewer`, while the ability still has a
  /// whole page (and its Web) to load before any new session can be ready.
  private awaitReviewerReady(result: MethodResult): void {
    const wantEpoch: number = reviewerSessionEpoch();
    let settled: boolean = false;
    let unsubscribe: () => void = (): void => {};
    let timer: number = -1;
    const succeed = (): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      unsubscribe();
      result.success('ready');
    };
    timer = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      unsubscribe();
      result.error('REVIEWER_NOT_READY', 'reviewer shell did not load', null);
    }, REVIEWER_READY_TIMEOUT_MS);
    unsubscribe = subscribeShellReady((): void => {
      if (shellReadyAfter(wantEpoch)) {
        succeed();
      }
    });
    if (shellReadyAfter(wantEpoch)) {
      succeed();
    }
  }

  /// Dart-side render failures land on the page's error banner (B2): the
  /// `present` promise only carries acks the ArkTS side produced itself, so
  /// a media-push exception or a controller error would otherwise leave the
  /// page on its shell with no card and no explanation.
  private notifyReviewerFailure(result: MethodResult, call: MethodCall): void {
    const session: AnkiReviewerSession | undefined = reviewerSession();
    if (session === undefined) {
      // Nowhere to show it; answering success keeps the best-effort contract
      // (Dart logs the drop on its side if the invoke itself fails).
      result.success('');
      return;
    }
    // `call.args` (the raw arguments field), not `argument(key)`: Dart sends
    // the failure code as the whole argument of this call, not as a map.
    // `arguments` does not exist on the fork SDK's MethodCall and never
    // compiled — this line predates R0 and had not seen a hap build.
    const code: string = (call.args as string) ?? '';
    session.notifyFailure(code.length > 0 ? code : RENDER_ERROR);
    result.success('');
  }
}

// `want` and `parameters` are both optional, and the verdict is untyped
// `Object` because that is what `Want` carries across the ability boundary.
// Reading it defensively matters more than usual here: a launch that fails
// part-way is exactly the case this probe exists to surface, and it must not
// surface as a null dereference.
function extractVerdict(abilityResult: common.AbilityResult): string {
  const want: Want | undefined = abilityResult.want;
  if (want === undefined || want.parameters === undefined) {
    return 'verdict=missing resultCode=' + String(abilityResult.resultCode);
  }
  const raw: Object = want.parameters['verdict'];
  if (raw === undefined) {
    return 'verdict=missing resultCode=' + String(abilityResult.resultCode);
  }
  return String(raw);
}
