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

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/// `AudioPlugin`'s prefix is `flutter_assets/assets`; the reviewer's directory
/// hangs off it. `assets/` being part of the path is the engine's convention, not
/// ours, and dropping it makes every lookup miss with `9001005` — which on a
/// phone is indistinguishable from "the reviewer is broken".
export const REVIEWER_ASSET_ROOT: string = 'flutter_assets/assets/anki_reviewer';

/// Every file the shell and the card frame request, in load order. Kept
/// explicit rather than derived from a directory listing: a reviewer that
/// silently stops serving MathJax would otherwise look identical to a reviewer
/// that correctly declines to serve a card with no maths on it.
export const REVIEWER_ASSETS: Array<string> = [
  'reviewer.html',
  'reviewer.js',
  'reviewer.css',
  'card-frame.html',
  'card-frame.js',
  'mathjax-config.js',
  'manifest.json',
  'mathjax/tex-svg-full.js',
];

/// Reads all eight synchronously and reports `name=bytes` or `name!err<code>`.
/// A miss is named rather than skipped: "every asset failed" and "MathJax alone
/// failed" call for different responses, and a summary line would collapse them.
export function probeReviewerAssetsSync(context: common.UIAbilityContext): string {
  const parts: Array<string> = [];
  for (const name of REVIEWER_ASSETS) {
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