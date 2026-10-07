// Copyright (c) 2024 Turna. All rights reserved.
// Audio playback for HarmonyOS — bridges @kit.MediaKit AVPlayer to Flutter via
// MethodChannel.
//
// `audioplayers` has no OpenHarmony implementation and the dependency ratchet
// (ADR 0047 §5.5) forbids overriding it, so the companion build drives AVPlayer
// directly. Two logical players are kept because the Dart side needs them: sound
// effects must not cut off speech and vice versa.
//
// Two source shapes, deliberately not unified:
//   - a bundled asset (short error / level-up cues) lives inside the hap under
//     `resources/rawfile/flutter_assets/…` and has no filesystem path, so it is
//     copied into cacheDir once and then played by URL;
//   - a media file (course pack, Anki deck media) already exists in the sandbox
//     and is played in place. Copying it would be pure waste and would double the
//     disk cost of a deck.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import hilog from '@ohos.hilog';

const TAG = "AudioPlugin";
const CHANNEL = "me.dsdogs.turna/audio";
const DOMAIN = 0xA700;

// The engine serves Flutter assets out of the hap's rawfile directory. The
// prefix is the engine's, not ours: the same bundle read by a different engine
// build would use a different one, which is why a wrong guess here shows up as
// "every effect is silent" rather than a build error.
//
// `assets/` is part of the path and not something the caller sends: Dart
// normalises `assets/sounds/x.mp3` down to `sounds/x.mp3` for the player APIs,
// and dropping the prefix from the bundle path too made every lookup miss —
// `GetRawFileContent` answers `9001005` for a path that does not exist, which
// on a phone is indistinguishable from "the sound effect is broken".
const ASSET_ROOT = 'flutter_assets/assets';

// Subdirectory of cacheDir, so a staged import (FilePickerPlugin) and a cached
// sound asset can never collide on a name.
const CACHE_SUBDIR = 'turna_audio';

const KEY_EFFECTS = 'effects';
const KEY_SPEECH = 'speech';

// How long a clip may run before "it never finished" is reported as such.
// Comfortably longer than any bundled effect, short enough that a stuck player
// does not hold the probe open.
const _completionWaitMs: number = 8000;

export default class AudioPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  // One live AVPlayer per logical player. A player is created per playback and
  // released afterwards rather than being reset and reused: the AVPlayer state
  // machine only accepts a new source in `idle`, and getting back there from
  // `playing` costs a reset whose failure modes are silent (a player stuck in
  // `initialized` swallows the next play). Playback here is one short clip, so
  // the create/release cost is irrelevant next to that risk.
  private effectPlayer: media.AVPlayer | null = null;
  private speechPlayer: media.AVPlayer | null = null;

  // The `File` handle backing each slot's fd source. It has to outlive the
  // playback: closing it early truncates the clip silently, which is the same
  // "no error, no sound" shape this plugin keeps having to rule out.
  private openHandles: Map<string, fs.File> = new Map();

  // Absolute path of each asset already copied out of the hap, so a repeated
  // play does not re-read the bundle.
  private cachedAssets: Map<string, string> = new Map();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    hilog.warn(DOMAIN, TAG, 'AudioPlugin constructed');
  }

  getUniqueClassName(): string {
    return "AudioPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    hilog.warn(DOMAIN, TAG, 'AudioPlugin attaching to engine');
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    hilog.warn(DOMAIN, TAG, 'AudioPlugin channel created for %{public}s', CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        // The dispatcher is wrapped because an exception thrown anywhere below
        // leaves the `MethodResult` unanswered, and an unanswered result is
        // indistinguishable on the Dart side from a slow platform: the future
        // simply never completes. A device run produced exactly that — correct
        // plugin, correct assets, no hilog line of any kind, and Dart blocked
        // until its own timeout — so the one thing this handler must never do
        // is fail to reply. Anything thrown becomes a named error instead.
        try {
          this.dispatch(call, result);
        } catch (e) {
          const err = e as BusinessError;
          hilog.error(DOMAIN, TAG,
            'dispatch threw for %{public}s: [%{public}d] %{public}s',
            call.method, err.code, err.message);
          result.error('DISPATCH_ERROR',
            `${call.method} 处理异常: [${err.code}] ${err.message}`, null);
        }
      }
    });
  }

  private dispatch(call: MethodCall, result: MethodResult): void {
    hilog.warn(DOMAIN, TAG, 'dispatch %{public}s', call.method);
    switch (call.method) {
      case 'ping':
        // Trivial round trip used to tell "the channel has no handler" apart
        // from "the handler is busy". On this embedding a channel with no ArkTS
        // handler does not answer at all, so the Dart side cannot distinguish
        // the two by exception type — only by whether anything comes back.
        result.success(true);
        break;
      case 'stageBytes':
        this.stageBytes(call, result);
        break;
      case 'playAsset':
        this.playAsset(call, result);
        break;
      case 'playFile':
        this.playFile(call, result);
        break;
      case 'stop':
        this.stop(call, result);
        break;
      case 'release':
        this.release(call, result);
        break;
      case 'reportDiagnostic':
        // Mirrors a Dart-side outcome into the platform log. The Dart logger
        // does not reach hilog on this embedding, so without this echo a probe
        // outcome is only observable as the *absence* of a line — and this log
        // buffer has already been observed to evict app-domain lines, which
        // makes absence worthless as evidence.
        hilog.warn(DOMAIN, TAG, 'dart: %{public}s',
          call.argument('message') as string);
        result.success(null);
        break;
      case 'awaitCompletion':
        this.awaitCompletion(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.releaseSlot(KEY_EFFECTS);
    this.releaseSlot(KEY_SPEECH);
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  // ── method handlers ──────────────────────────────────────────────

  /**
   * Decodes bytes the Dart side read from the asset bundle and writes them into
   * the cache directory, answering with the absolute path.
   *
   * Staging is a separate round trip from playback on purpose. Two reasons, and
   * the second is why this method exists at all:
   *
   * 1. An asset is staged once and played many times, so the base64 transfer
   *    does not repeat and the cache lookup is not re-done.
   * 2. Progress has to be observable. This plugin's own hilog output does not
   *    reach the device log, so when a stage-and-play call hung there was no way
   *    to tell which half was stuck — two wrong conclusions came out of that
   *    silence. Answering from a short method puts each half's outcome in the
   *    Dart transparency log, which is the one channel that has been reliable.
   *
   * The bytes come from Dart's `rootBundle` rather than
   * `resourceManager.getRawFileContent`: neither the promise nor the synchronous
   * form of the platform read was observed to answer on Mate 90 Pro Max / API 26.
   * base64 because this embedding's standard codec has no byte-array mapping,
   * the same reason the RDB bridge base64s BLOB parameters.
   */
  private stageBytes(call: MethodCall, result: MethodResult): void {
    const name = call.argument('name') as string;
    const data = call.argument('data') as string;
    if (!name || !data) {
      result.error('BAD_ARGS', 'name and data are required', null);
      return;
    }
    const cached = this.cachedAssets.get(name);
    if (cached !== undefined && fs.accessSync(cached)) {
      result.success(cached);
      return;
    }
    let bytes: Uint8Array;
    try {
      const decoder: util.Base64Helper = new util.Base64Helper();
      bytes = decoder.decodeSync(data);
    } catch (e) {
      const err = e as BusinessError;
      result.error('DECODE_ERROR',
        `无法解码音频数据 ${name}: [${err.code}] ${err.message}`, null);
      return;
    }
    try {
      result.success(this.stageAsset(name, bytes));
    } catch (e) {
      const err = e as BusinessError;
      result.error('STAGE_ERROR',
        `无法暂存音频 ${name}: [${err.code}] ${err.message}`, null);
    }
  }

  private playAsset(call: MethodCall, result: MethodResult): void {
    const key = playerKeyOf(call.argument('player'));
    const path = call.argument('path') as string;
    if (!key || !path) {
      result.error('BAD_ARGS', 'player and path are required', null);
      return;
    }
    this.assetPath(path)
      .then((absolute: string) => {
        this.playUrl(key, absolute, result);
      })
      .catch((e: BusinessError) => {
        result.error('ASSET_ERROR',
          `无法读取内置音频 ${path}: [${e.code}] ${e.message}`, null);
      });
  }

  private playFile(call: MethodCall, result: MethodResult): void {
    const key = playerKeyOf(call.argument('player'));
    const path = call.argument('path') as string;
    if (!key || !path) {
      result.error('BAD_ARGS', 'player and path are required', null);
      return;
    }
    // Existence is checked here rather than left to `prepare()`: the Dart side
    // treats "playback started" as true and stops looking for a fallback voice,
    // so a missing file has to fail loudly at this point instead of as a
    // silence later.
    if (!fs.accessSync(path)) {
      result.error('NO_FILE', `音频文件不存在: ${path}`, null);
      return;
    }
    this.playUrl(key, path, result);
  }

  private stop(call: MethodCall, result: MethodResult): void {
    const key = playerKeyOf(call.argument('player'));
    if (!key) {
      result.error('BAD_ARGS', 'player is required', null);
      return;
    }
    this.stopSlot(key);
    result.success(null);
  }

  private release(call: MethodCall, result: MethodResult): void {
    const key = playerKeyOf(call.argument('player'));
    if (!key) {
      result.error('BAD_ARGS', 'player is required', null);
      return;
    }
    this.releaseSlot(key);
    result.success(null);
  }

  // ── playback ─────────────────────────────────────────────────────

  /**
   * Answers only once the clip has reached `completed`, or names why it never
   * did.
   *
   * `result.success` from the play path means the player *accepted* the
   * command, and the probe that released immediately after it proved the
   * difference the hard way: the state machine reached `playing` and was cut
   * off 50 ms later by its own teardown. "It started" and "it played" are
   * different claims and only the second one is worth anything.
   *
   * Bounded on purpose, same rule as the Dart-side timeouts: a clip that never
   * completes has to become a named failure, because silence teaches nothing.
   */
  private awaitCompletion(call: MethodCall, result: MethodResult): void {
    const key = playerKeyOf(call.argument('player'));
    if (!key) {
      result.error('BAD_ARGS', 'player is required', null);
      return;
    }
    const player = this.slotOf(key);
    if (!player) {
      result.error('NO_PLAYER', `slot ${key} holds no player`, null);
      return;
    }
    let settled: boolean = false;
    const finish = (ok: boolean, note: string): void => {
      if (settled) {
        return;
      }
      settled = true;
      hilog.warn(DOMAIN, TAG, 'completion %{public}s: %{public}s', key, note);
      if (ok) {
        result.success(note);
      } else {
        result.error('NOT_COMPLETED', note, null);
      }
    };
    player.on('stateChange', (state: string, reason: number) => {
      if (state === 'completed') {
        finish(true, 'reached completed');
      }
    });
    setTimeout(() => {
      finish(false, `no completed state within ${_completionWaitMs}ms`);
    }, _completionWaitMs);
  }

  private playUrl(key: string, absolutePath: string, result: MethodResult): void {
    // Whatever was playing in this slot is cancelled first: the Dart side
    // always `stop()`s before a new source, but a play that arrives without one
    // (a rapid second tap) must still not overlap two clips.
    this.stopSlot(key);

    let descriptor: media.AVFileDescriptor | undefined;
    let sourceKind: string = '';
    try {
      // A file descriptor, not a `file://` URL. The URL form produced a source
      // the player accepted and then played nothing at all — `play()` resolved,
      // no error was raised, and no sound came out. An fd is what the SDK's own
      // samples use for local media, and it cannot be defeated by a path the
      // player decides to treat as a URI to resolve.
      const handle = fs.openSync(absolutePath, fs.OpenMode.READ_ONLY);
      const length = fs.statSync(absolutePath).size;
      descriptor = {
        fd: handle.fd,
        offset: 0,
        length: length,
      };
      sourceKind = 'fd';
      this.openHandles.set(key, handle);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'fd source failed for %{public}s: [%{public}d]',
        absolutePath, err.code);
      // The `url` property is the fallback shape; `setMediaSource` is not used
      // anywhere in this method any more (see the createAVPlayer block below).
      sourceKind = 'url';
    }
    hilog.warn(DOMAIN, TAG, 'play %{public}s via %{public}s (%{public}s)',
      key, sourceKind, absolutePath);

    // The reply must be sent exactly once. A later event can still fire an
    // error after the success; answering twice crashes the channel with
    // "Reply already submitted".
    let settled: boolean = false;
    const succeed = (): void => {
      if (!settled) {
        settled = true;
        result.success(true);
      }
    };
    const fail = (code: string, message: string): void => {
      if (!settled) {
        settled = true;
        result.error(code, message, null);
      }
    };

    // `createAVPlayer` is called in its callback form, not its promise form.
    // The promise overload is declared in the same d.ts, but on Mate 90 Pro Max
    // / API 26 it hands back `undefined` — `Cannot read property then of
    // undefined` — so every play died before a player existed. The callback form
    // is what the SDK documents first and what the official samples use, and a
    // device run confirms it fires.
    media.createAVPlayer((createErr: BusinessError, player: media.AVPlayer) => {
      hilog.warn(DOMAIN, TAG, 'createAVPlayer callback fired for %{public}s', key);
      if (createErr) {
        this.dropSlot(key, null);
        fail('PLAYER_ERROR', `无法创建播放器: [${createErr.code}] ${createErr.message}`);
        return;
      }
      player.on('error', (err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'AVPlayer error %{public}d: %{public}s',
          err.code, err.message);
        this.dropSlot(key, player);
        // Reported even after `succeed()`: the Dart side logs it, and a
        // silently broken clip is exactly the failure this whole plugin
        // exists to eliminate.
        hilog.error(DOMAIN, TAG, 'playback failed for %{public}s', absolutePath);
      });

      // State-driven, and deliberately free of awaited promises.
      //
      // A device run on this exact platform showed `setMediaSource()` neither
      // resolving nor advancing the state machine: no `stateChange`, no
      // `error`, no exception, three plays out of three. Since this platform
      // has already turned four other promise-returning accessors into
      // silence (`getRawFileContent`, `ResultSet.getColumnNames`,
      // `getColumnTypeSync` outside a row, and `createAVPlayer`'s promise
      // overload), a prepare chain built out of them is a chain of places to
      // hang without a word. So: assign `fdSrc` — the synchronous route into
      // `initialized` — and let the state machine be the only clock. This is
      // also the shape the SDK's own AVPlayer sample uses.
      player.on('stateChange', (state: string, reason: number) => {
        hilog.warn(DOMAIN, TAG, 'stateChange %{public}s %{public}s (%{public}d)',
          key, state, reason);
        if (state === 'initialized') {
          this.keepSlot(key, player);
          // Not awaited: `prepare()` is another candidate for never settling,
          // and `prepared` is the signal that actually carries the meaning.
          player.prepare().catch((e: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'prepare rejected for %{public}s: [%{public}d]',
              key, e.code);
            this.dropSlot(key, player);
            fail('PREPARE_ERROR', `准备失败: [${e.code}] ${e.message}`);
          });
        } else if (state === 'prepared') {
          // Reached without awaiting anything above. Reported, not gated: the
          // old code refused to play on zero tracks, but reading tracks is a
          // promise-returning accessor too, and blocking playback on it is how
          // a diagnostic turned into the outage it was meant to catch. The count
          // goes to the log; it does not decide whether sound comes out.
          player.getTrackDescription().then((tracks: Array<media.MediaDescription>) => {
            hilog.warn(DOMAIN, TAG, 'tracks for %{public}s: %{public}d',
              absolutePath, tracks.length);
          }).catch(() => {
            hilog.warn(DOMAIN, TAG, 'track description unavailable for %{public}s', absolutePath);
          });
          player.play().catch((e: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'play rejected for %{public}s: [%{public}d]',
              key, e.code);
            this.dropSlot(key, player);
            fail('PLAY_ERROR', `播放失败: [${e.code}] ${e.message}`);
          });
          succeed();
        }
      });

      if (descriptor !== undefined) {
        player.fdSrc = descriptor;
        hilog.warn(DOMAIN, TAG, 'fdSrc assigned for %{public}s', key);
      } else {
        player.url = `file://${absolutePath}`;
        hilog.warn(DOMAIN, TAG, 'url assigned for %{public}s', key);
      }
    });
  }

  // ── asset staging ────────────────────────────────────────────────

  /**
   * Absolute path of a bundled asset, copying it out of the hap on first use.
   *
   * The bytes are read through `resourceManager.getRawFileContent` and written
   * to cacheDir rather than played from a raw-file descriptor. Both routes are
   * documented, but a descriptor obtained from the hap stays the app's
   * responsibility for the whole playback, and releasing it early is a silent
   * truncation rather than an error. The copy is a few dozen kilobytes, once
   * per asset, in a directory the OS is free to reclaim.
   */
  private assetPath(relative: string): Promise<string> {
    const known: string | undefined = this.cachedAssets.get(relative);
    if (known !== undefined && fs.accessSync(known)) {
      return Promise.resolve(known);
    }

    const rawName = `${ASSET_ROOT}/${relative}`;
    // The *synchronous* form of the read, on purpose. The promise form
    // (`getRawFileContent`) never settles on Mate 90 Pro Max / API 26: the Dart
    // future stayed open until its own 10s timeout, the cache subdirectory was
    // never created, and the plugin wrote no hilog line at all — so a port whose
    // only job is to make a sound produced exactly the same silence as a port
    // that was never called. Same API family, same bytes, `@since 10`; a bad
    // path comes back as a thrown `BusinessError 9001005` instead of a promise
    // that never lands.
    //
    // Synchronous is acceptable here for the same reason the write already was:
    // a few dozen kilobytes, once per asset, on the platform thread.
    //
    // Wrapped in a Promise so the caller's existing `.catch` keeps turning a
    // read failure into `ASSET_ERROR` rather than into a synchronous throw that
    // the method-call dispatcher would swallow unanswered.
    return new Promise<string>((resolve, reject) => {
      let bytes: Uint8Array;
      hilog.warn(DOMAIN, TAG, 'reading rawfile %{public}s', rawName);
      try {
        bytes = this.context.resourceManager.getRawFileContentSync(rawName);
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'rawfile read failed [%{public}d] %{public}s',
          err.code, err.message);
        reject(err);
        return;
      }
      hilog.warn(DOMAIN, TAG, 'rawfile read ok (%{public}d bytes)', bytes.length);
      try {
        resolve(this.stageAsset(relative, bytes));
      } catch (e) {
        reject(e as BusinessError);
      }
    });
  }

  /**
   * Copies [bytes] into the app's cache directory and returns the absolute path.
   *
   * Synchronous on purpose: a few dozen kilobytes, once per asset, and the async
   * form would need its own error path for a step whose failure is already fatal
   * to the playback it belongs to.
   */
  private stageAsset(relative: string, bytes: Uint8Array): string {
    const dir = `${this.context.cacheDir}/${CACHE_SUBDIR}`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
    const dest = `${dir}/${fileNameOf(relative)}`;
    const handle = fs.openSync(
      dest,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(handle.fd, bytes.buffer);
    } finally {
      fs.closeSync(handle);
    }
    hilog.warn(DOMAIN, TAG, 'staged asset %{public}s (%{public}d bytes)',
      dest, bytes.length);
    this.cachedAssets.set(relative, dest);
    return dest;
  }

  // ── slot bookkeeping ─────────────────────────────────────────────

  private keepSlot(key: string, player: media.AVPlayer): void {
    if (key === KEY_EFFECTS) {
      this.effectPlayer = player;
    } else {
      this.speechPlayer = player;
    }
  }

  private slotOf(key: string): media.AVPlayer | null {
    return key === KEY_EFFECTS ? this.effectPlayer : this.speechPlayer;
  }

  private clearSlot(key: string): media.AVPlayer | null {
    const current = this.slotOf(key);
    if (key === KEY_EFFECTS) {
      this.effectPlayer = null;
    } else {
      this.speechPlayer = null;
    }
    this.closeHandle(key);
    return current;
  }

  private closeHandle(key: string): void {
    const handle = this.openHandles.get(key);
    if (!handle) return;
    this.openHandles.delete(key);
    try {
      fs.closeSync(handle);
    } catch (e) {
      // Best-effort: the descriptor is about to be dropped either way, and
      // nothing downstream depends on the close succeeding.
    }
  }

  private dropSlot(key: string, player: media.AVPlayer | null): void {
    if (player === null) return;
    if (this.slotOf(key) === player) {
      this.clearSlot(key);
    }
    // Best-effort teardown: a player that failed to play may also refuse to
    // stop, and nothing downstream depends on either call succeeding.
    player.stop()
      .catch(() => {
      })
      .then(() => {
        return player.release();
      })
      .catch(() => {
      });
  }

  private stopSlot(key: string): void {
    const current = this.clearSlot(key);
    if (!current) return;
    current.stop().catch(() => {
    });
  }

  private releaseSlot(key: string): void {
    const current = this.clearSlot(key);
    if (!current) return;
    current.stop()
      .catch(() => {
      })
      .then(() => {
        return current.release();
      })
      .catch(() => {
      });
  }
}

function playerKeyOf(raw: Object | undefined): string | null {
  if (raw === 'effects') return KEY_EFFECTS;
  if (raw === 'speech') return KEY_SPEECH;
  return null;
}

function fileNameOf(relative: string): string {
  const slash = relative.lastIndexOf('/');
  const name = slash === -1 ? relative : relative.slice(slash + 1);
  return name.length > 0 ? name : 'asset.bin';
}
