// Copyright (c) 2024 Turna. All rights reserved.
//
// ADR 0050 §6 step 5b — can the reviewer ability read its own assets at runtime?
//
// This is the question that decides the reviewer's whole asset architecture, and
// it is asked here rather than reasoned about because three separate facts make
// reasoning unreliable:
//
//  1. The reviewer is a **separate ability** from `EntryAbility`. The probe page's
//     own comment records that a separate ability has no `FlutterAssetManager`,
//     so "the assets are in the hap" is not by itself a reason a second ability
//     can read them — only a read proves it.
//  2. `AudioPlugin` records that the *promise* form of the platform read
//     (`getRawFileContent`) never settles on Mate 90 Pro Max / API 26, and had to
//     be replaced by the synchronous form. If that still holds, a reviewer built
//     on the promise form is a reviewer whose media never loads and whose
//     failure mode is silence.
//  3. The largest file is 2.27 MB of MathJax. A synchronous read of that on the
//     platform thread is a real cost, so "sync works" and "sync is acceptable"
//     are separate questions and only the first is answered by a read.
//
// The third asset path — bytes over the MethodChannel from Dart's `rootBundle`,
// which is what `AudioPlugin.stageBytes` fell back to — needs no probe: it is
// always available, because Dart is on the other end of the channel either way.
// It is simply the expensive option for 2.27 MB, so it stays the fallback rather
// than the answer.
//
// R1 (2026-10-17) moved this file out of `ets/anki/` into `ets/probe/`, and
// deleted its private copy of the asset list in favour of the production
// server's — see [probeReviewerAssetsSync] for why that copy was dangerous.
// This file remains reachable from the production plugin on purpose: the two
// `probeReviewer*` channel methods are the diagnostics that answer "can the
// reviewer ability read its own assets at runtime", and there is no other
// caller for them.

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { REVIEWER_ASSET_NAMES, REVIEWER_ASSET_ROOT } from '../anki/AnkiOriginServer';

/// Reads all eight synchronously and reports `name=bytes` or `name!err<code>`.
/// A miss is named rather than skipped: "every asset failed" and "MathJax alone
/// failed" call for different responses, and a summary line would collapse them.
///
/// The eight are [REVIEWER_ASSET_NAMES] — the production server's own list,
/// imported rather than re-declared. It used to carry a private copy, and the
/// copy was the dangerous part: a file added to one side and not the other
/// produced no build error and no warning, only a blank card in the field. A
/// probe reading a list the server does not serve would also have been
/// measuring something other than what ADR 0050 §3.3 recorded.
///
/// `REVIEWER_ASSET_ROOT` is imported for the same reason: the `flutter_assets/`
/// prefix is the engine's convention hanging off `AudioPlugin`'s, and dropping
/// `assets/` from it makes every lookup miss with `9001005` — which on a phone
/// is indistinguishable from "the reviewer is broken".
export function probeReviewerAssetsSync(context: common.UIAbilityContext): string {
  const parts: Array<string> = [];
  for (const name of REVIEWER_ASSET_NAMES) {
    const raw: string = REVIEWER_ASSET_ROOT + '/' + name;
    try {
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync(raw);
      parts.push(name + '=' + String(bytes.length));
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      parts.push(name + '!err' + String(err.code));
    }
  }
  return 'sync[' + parts.join(' ') + ']';
}

/// Whether the promise form settles at all, within [capMs].
///
/// `AudioPlugin` recorded it as never settling. That is worth re-asking rather
/// than inheriting, because the two forms differ in more than timing: if the
/// promise form works, the 2.27 MB MathJax read stops being a platform-thread
/// stall, and that changes the reviewer's design rather than just its speed.
export function probeReviewerAssetPromise(
  context: common.UIAbilityContext,
  capMs: number,
): Promise<string> {
  return new Promise<string>((resolve) => {
    let settled: boolean = false;
    const timer: number = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      resolve('promise=timeout');
    }, capMs);
    context.resourceManager
      .getRawFileContent(REVIEWER_ASSET_ROOT + '/reviewer.html')
      .then((bytes: Uint8Array) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve('promise=ok:' + String(bytes.length));
      })
      .catch((e: BusinessError) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve('promise=err:' + String(e.code));
      });
  });
}

/// Both forms in one string, so one channel call answers the whole question.
/// The promise probe runs after the synchronous one so the sync answer is not
/// held up by it.
export function probeReviewerAssets(context: common.UIAbilityContext): Promise<string> {
  const syncAnswer: string = probeReviewerAssetsSync(context);
  return probeReviewerAssetPromise(context, 4000).then((promiseAnswer: string) => {
    return syncAnswer + ' ' + promiseAnswer;
  });
}