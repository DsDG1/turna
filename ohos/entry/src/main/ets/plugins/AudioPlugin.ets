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
  }

  getUniqueClassName(): string {
    return "AudioPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        switch (call.method) {
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
          default:
            result.notImplemented();
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.releaseSlot(KEY_EFFECTS);
    this.releaseSlot(KEY_SPEECH);
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  // ── method handlers ──────────────────────────────────────────────

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

  private playUrl(key: string, absolutePath: string, result: MethodResult): void {
    // Whatever was playing in this slot is cancelled first: the Dart side
    // always `stop()`s before a new source, but a play that arrives without one
    // (a rapid second tap) must still not overlap two clips.
    this.stopSlot(key);

    let source: media.MediaSource | undefined;
    let sourceKind: string = '';
    try {
      // A file descriptor, not a `file://` URL. The URL form produced a source
      // the player accepted and then played nothing at all — `play()` resolved,
      // no error was raised, and no sound came out. An fd is what the SDK's own
      // samples use for local media, and it cannot be defeated by a path the
      // player decides to treat as a URI to resolve.
      const handle = fs.openSync(absolutePath, fs.OpenMode.READ_ONLY);
      const length = fs.statSync(absolutePath).size;
      const descriptor: media.AVFileDescriptor = {
        fd: handle.fd,
        offset: 0,
        length: length,
      };
      source = media.createMediaSourceWithFd(descriptor);
      sourceKind = 'fd';
      this.openHandles.set(key, handle);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'fd source failed for %{public}s: [%{public}d]',
        absolutePath, err.code);
      try {
        source = media.createMediaSourceWithUrl(`file://${absolutePath}`);
        sourceKind = 'url';
      } catch (inner) {
        const innerErr = inner as BusinessError;
        result.error('NO_SOURCE',
          `无法为 ${absolutePath} 创建媒体源: [${innerErr.code}] ${innerErr.message}`,
          null);
        return;
      }
    }
    if (!source) {
      result.error('NO_SOURCE', `无法为 ${absolutePath} 创建媒体源`, null);
      return;
    }
    hilog.warn(DOMAIN, TAG, 'play %{public}s via %{public}s (%{public}s)',
      key, sourceKind, absolutePath);

    // The reply must be sent exactly once. `play()` resolving only means the
    // player accepted the command, and the events below can still fire an error
    // afterwards; answering twice crashes the channel with
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
    // is what the SDK documents first and what the official samples use.
    media.createAVPlayer((createErr: BusinessError, player: media.AVPlayer) => {
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
      player.setMediaSource(source)
        .then(() => {
          return player.prepare();
        })
        .then(() => {
          // A prepared player with no decodable track accepts `play()`, reports
          // success, and stays silent — which is exactly what a broken source
          // looks like from Dart. Checking here turns that silence into an
          // error the app can log instead of a mystery.
          return player.getTrackDescription();
        })
        .then((tracks: Array<media.MediaDescription>) => {
          hilog.warn(DOMAIN, TAG, 'tracks for %{public}s: %{public}d',
            absolutePath, tracks.length);
          if (tracks.length === 0) {
            this.dropSlot(key, player);
            fail('NO_TRACK', `没有可解码的音轨: ${absolutePath}`);
            return;
          }
          this.keepSlot(key, player);
          return player.play();
        })
        .then(() => {
          succeed();
        })
        .catch((e: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'prepare/play failed, code: %{public}s',
            `${e.code}`);
          this.dropSlot(key, player);
          fail('PLAY_ERROR', `播放失败: [${e.code}] ${e.message}`);
        });
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
    return this.context.resourceManager.getRawFileContent(rawName)
      .then((bytes: Uint8Array) => {
        const dir = `${this.context.cacheDir}/${CACHE_SUBDIR}`;
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir);
        }
        const dest = `${dir}/${fileNameOf(relative)}`;
        // Synchronous on purpose. The write happens once per asset, is a few
        // dozen kilobytes, and the async form would need its own error path for
        // a step whose failure is already fatal to this playback.
        const handle = fs.openSync(
          dest,
          fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
        );
        try {
          fs.writeSync(handle.fd, bytes.buffer);
        } finally {
          fs.closeSync(handle);
        }
        hilog.info(DOMAIN, TAG, 'cached asset %{public}s (%{public}d bytes)',
          dest, bytes.length);
        this.cachedAssets.set(relative, dest);
        return dest;
      });
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
