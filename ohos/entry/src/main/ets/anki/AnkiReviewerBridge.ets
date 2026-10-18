// Copyright (c) 2024 Turna. All rights reserved.
//
// The ArkTS object injected into the reviewer page as the host.
//
// Its own type rather than a field on the page, because ArkUI hands a page only
// the public methods listed in `methodList` — anything else stays unreachable
// from page script, which is the point. The page's own script is card-authored
// and therefore untrusted input even though this build assembled the frame, so
// the boundary is drawn where it is drawn.
//
// Mirrors `AnkiProbeBridge` in `ets/probe/`, which keeps the shape for a reason
// that does not apply here. The probe's `attach`/`emit` pair is a stringly-typed
// event channel: the page hands the object a callback and every method mirrors
// itself into it. Production never attaches one — `attachReviewerOutbound` is
// the only wiring this file has — so all seven mirrored calls went nowhere and
// the channel was a second, silent path to the same seven methods. R1 removed it;
// every method below now reaches Dart exactly once, through `outbound`.
//
// What the probe did not need and the reviewer has is the typed answer, plus
// receipts: show answer, rate and the text field are three messages Dart has to
// act on, and `rate` additionally has to report back what Dart decided.

import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import type Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';
import {
  METHOD_RATE,
  METHOD_REPLAY_AUDIO,
  METHOD_RETRY_ADVANCE,
  METHOD_RETRY_PRESENT,
  METHOD_REVIEW_SETTLEMENT,
  METHOD_SHOW_ANSWER,
  METHOD_SHOW_QUESTION,
  METHOD_TYPED_CHANGED,
} from './AnkiReviewerProtocol';

let outbound: MethodChannel | null = null;

export function attachReviewerOutbound(channel: MethodChannel | null): void {
  outbound = channel;
}

export class AnkiReviewerBridge {
  private typedVisible: boolean = false;

  public setTypedVisible(visible: boolean): void {
    this.typedVisible = visible;
  }

  public isTypedVisible(): boolean {
    return this.typedVisible;
  }

  /// The learner tapped "show answer". `typed` is whatever the native field
  /// held, sent as an opaque string: comparing it is the official engine's job
  /// on the Dart side, and doing any normalisation here would put a second
  /// opinion about spelling next to the one that has the dictionary.
  public showAnswer(typed: string): void {
    this.callDart(METHOD_SHOW_ANSWER, typed);
  }

  /// Preview mode's flip-back control: asks Dart to re-present the question
  /// face without writing any grade or scheduler state.
  public showQuestion(): void {
    this.callDart(METHOD_SHOW_QUESTION, '');
  }

  /// One of Anki's four buttons. `rating` arrives as the button's own label so
  /// the mapping to a scheduler value stays in Dart, where the buttons and the
  /// intervals they produce are defined together.
  ///
  /// Unlike `showAnswer`, this call carries its verdict back: `onResult` gets
  /// the receipt code ('ok' | 'ok_complete' | 'answer_not_ready' |
  /// 'scheduler_busy' | hard-failure codes). The page disables the four
  /// buttons the moment one is tapped and decides from this code whether to
  /// re-enable them — without the receipt, a refusal on the Dart side is
  /// indistinguishable from a button that does nothing.
  public rate(rating: string, onResult: (code: string) => void): void {
    const channel: MethodChannel | null = outbound;
    if (channel === null) {
      onResult('bridge_detached');
      return;
    }
    const receiver: MethodResult = {
      success: (result: Any): void => {
        onResult(result === null || result === undefined ? '' : String(result));
      },
      error: (code: string): void => {
        onResult('channel_error_' + code);
      },
      notImplemented: (): void => {
        onResult('not_implemented');
      },
    };
    channel.invokeMethod(METHOD_RATE, rating, receiver);
  }

  /// The page's "retry the advance" entry after an `advance_failed` receipt:
  /// the rating itself already committed in the scheduler, so only the
  /// advance re-runs. Carries its receipt back for the same reason `rate`
  /// does — a retry that nothing answers reads as a dead button.
  public retryAdvance(rating: string, onResult: (code: string) => void): void {
    const channel: MethodChannel | null = outbound;
    if (channel === null) {
      onResult('bridge_detached');
      return;
    }
    const receiver: MethodResult = {
      success: (result: Any): void => {
        onResult(result === null || result === undefined ? '' : String(result));
      },
      error: (code: string): void => {
        onResult('channel_error_' + code);
      },
      notImplemented: (): void => {
        onResult('not_implemented');
      },
    };
    channel.invokeMethod(METHOD_RETRY_ADVANCE, rating, receiver);
  }

  /// The error banner's retry: asks Dart to re-present the failed face. No
  /// receipt — the present that follows (or the next failure banner) is the
  /// visible outcome.
  public retryPresent(): void {
    this.callDart(METHOD_RETRY_PRESENT, '');
  }

  /// The completion row's statistics (UI-7). `onResult` receives the JSON
  /// the Flutter settlement produced, or an empty string when Dart had
  /// nothing to report — the page then keeps its plain completion row.
  public settlement(onResult: (json: string) => void): void {
    const channel: MethodChannel | null = outbound;
    if (channel === null) {
      onResult('');
      return;
    }
    const receiver: MethodResult = {
      success: (result: Any): void => {
        onResult(result === null || result === undefined ? '' : String(result));
      },
      error: (): void => {
        onResult('');
      },
      notImplemented: (): void => {
        onResult('');
      },
    };
    channel.invokeMethod(METHOD_REVIEW_SETTLEMENT, '', receiver);
  }

  /// Manual audio replay for the current face. `onResult` receives any
  /// non-fatal AV hint (missing media file, TTS fallback notice) returned by
  /// the Dart coordinator after playback settles.
  public replayAudio(onResult?: (hint: string) => void): void {
    const channel: MethodChannel | null = outbound;
    if (channel === null) {
      if (onResult !== undefined) {
        onResult('');
      }
      return;
    }
    const receiver: MethodResult = {
      success: (result: Any): void => {
        if (onResult !== undefined) {
          onResult(result === null || result === undefined ? '' : String(result));
        }
      },
      error: (): void => {
        if (onResult !== undefined) {
          onResult('');
        }
      },
      notImplemented: (): void => {
        if (onResult !== undefined) {
          onResult('');
        }
      },
    };
    channel.invokeMethod(METHOD_REPLAY_AUDIO, '', receiver);
  }

  /// Every keystroke, mirroring the Flutter `TextField`'s `onChanged`. Sent on
  /// change rather than on submit because the comparison needs the text while
  /// the answer is still hidden: the learner must be able to see the diff
  /// against what they actually typed, not against a value reconstructed at
  /// submit time.
  public typedChanged(text: string): void {
    this.callDart(METHOD_TYPED_CHANGED, text);
  }

  private callDart(method: string, payload: string): void {
    const channel: MethodChannel | null = outbound;
    if (channel === null) {
      return;
    }
    channel.invokeMethod(method, payload);
  }
}