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
// Mirrors `AnkiProbeBridge`, with one addition that the probe did not need: the
// typed answer. The probe had no button that meant anything to Dart; the
// reviewer has three — show answer, rate, and the text field — and each one is a
// message Dart has to act on, so each gets a method rather than a stringly-typed
// event channel.

import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import type Any from '@ohos/flutter_ohos/src/main/ets/plugin/common/Any';

let outbound: MethodChannel | null = null;

export function attachReviewerOutbound(channel: MethodChannel | null): void {
  outbound = channel;
}

export class AnkiReviewerBridge {
  private handler: ((kind: string, raw: string) => void) | undefined = undefined;
  private typedVisible: boolean = false;

  public attach(handler: (kind: string, raw: string) => void): void {
    this.handler = handler;
  }

  public setTypedVisible(visible: boolean): void {
    this.typedVisible = visible;
  }

  public isTypedVisible(): boolean {
    return this.typedVisible;
  }

  private emit(kind: string, payload: string): void {
    const handler: ((kind: string, raw: string) => void) | undefined = this.handler;
    if (handler === undefined) {
      return;
    }
    handler(kind, payload);
  }

  /// The learner tapped "show answer". `typed` is whatever the native field
  /// held, sent as an opaque string: comparing it is the official engine's job
  /// on the Dart side, and doing any normalisation here would put a second
  /// opinion about spelling next to the one that has the dictionary.
  public showAnswer(typed: string): void {
    this.emit('showAnswer', typed);
    this.callDart('showAnswer', typed);
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
    this.emit('rate', rating);
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
    channel.invokeMethod('rate', rating, receiver);
  }

  /// Every keystroke, mirroring the Flutter `TextField`'s `onChanged`. Sent on
  /// change rather than on submit because the comparison needs the text while
  /// the answer is still hidden: the learner must be able to see the diff
  /// against what they actually typed, not against a value reconstructed at
  /// submit time.
  public typedChanged(text: string): void {
    this.emit('typedChanged', text);
    this.callDart('typedChanged', text);
  }

  private callDart(method: string, payload: string): void {
    const channel: MethodChannel | null = outbound;
    if (channel === null) {
      return;
    }
    channel.invokeMethod(method, payload);
  }
}