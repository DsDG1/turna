// Copyright (c) 2024 Turna. All rights reserved.
// Offline TTS via sherpa-onnx — synthesises audio for the OpenHarmony
// companion build; playback is NOT done here.
//
// Why this exists: CoreSpeechKit is silent on the device this build was
// verified against (CMM-AL10 / OpenHarmony 7.0.0.109 / API 26). Its
// `listVoices` reports `zh_CN person=13 status=INSTALLED`, the engine is
// created, `speak` returns true, `onStart` fires, `onComplete` fires — about
// 44 ms later, twice — and no `onError` ever arrives. Nothing is audible in any
// language, including the one the device itself claims to have installed. The
// only honest reading is that the platform's synthesiser renders nothing here,
// so a model that ships with the app is not a fallback for one language but the
// only speaking path.
//
// Division of labour: sherpa-onnx turns text into PCM, this plugin wraps it in a
// WAV and hands back a sandbox path. `AudioBackend` plays it — that path was
// fixed and verified on device (fd source, state-machine driven), and a second
// player here would be a second thing that can be silently broken.
//
// The model must be a real file. `resourceManager` exposes `getRawFd` and
// `getRawFileContentSync` but no `getRawFilePath`, and the espeak-ng-data
// phonemiser needs a *directory*, so a rawfile inside the hap cannot be handed
// to sherpa at all. The model is therefore copied out of the rawfile once into
// the sandbox and loaded from there.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import {
  OfflineTts,
  OfflineTtsConfig,
  OfflineTtsModelConfig,
  OfflineTtsVitsModelConfig,
  TtsInput
} from 'sherpa_onnx';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';

const TAG = "SherpaTts";
const CHANNEL = "me.dsdogs.turna/sherpa-tts";
const DOMAIN = 0xA700;

// Where the model lives inside the hap's rawfile, and where it is copied to.
const MODEL_RAW_ROOT = 'sherpa/vits-piper-tr_TR-dfki-medium-int8';
const MODEL_DIR = 'sherpa';
const SPEAKER_ID = 0;

// espeak-ng-data is what turns Turkish text into phonemes for Piper VITS. A
// model without it loads fine and then produces nothing, which is the same
// silence this plugin exists to end, so its presence is checked explicitly.
const ESPEAK_DIR = 'espeak-ng-data';
const MODEL_FILE = 'tr_TR-dfki-medium.onnx';
const TOKENS_FILE = 'tokens.txt';
const VITS_METADATA_FILE = 'tr_TR-dfki-medium.onnx.json';
const MANIFEST_FILE = 'stage-manifest.tsv';

/** One staging step: a flat rawfile name and where it belongs once staged. */
class StageStep {
  public rawName: string;
  public destRelative: string;

  constructor(rawName: string, destRelative: string) {
    this.rawName = rawName;
    this.destRelative = destRelative;
  }
}

/** The whole staging job, read from the manifest that ships beside the model. */
class StagePlan {
  public sizes: Map<string, number> = new Map();
  public steps: StageStep[] = [];

  constructor() {
  }
}

// How long one batch of copies may run before the thread is handed back.
//
// The whole copy is 355 reads and one 17.8 MB read. Done as a single block it
// holds the platform thread long enough for the device to kill the process —
// silently, with no catch, which is why this budget exists rather than a plain
// loop.
const COPY_BATCH_BUDGET_MS = 40;

export default class SherpaTtsPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  private tts: OfflineTts | null = null;
  private modelDir: string = '';
  // Last mismatch reported, so a wrong size is logged once rather than on every
  // launch — the staging probe asks the same question every time.
  private reported: string = '';
  // Set once the engine exists, so a second `init` is cheap and callers can ask
  // what sample rate the audio they are about to play actually has.
  private sampleRate: number = 0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    hilog.warn(DOMAIN, TAG, 'SherpaTtsPlugin constructed');
  }

  getUniqueClassName(): string {
    return "SherpaTtsPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    hilog.warn(DOMAIN, TAG, 'SherpaTts channel created for %{public}s', CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        // Wrapped for the same reason `AudioPlugin` wraps its dispatcher: an
        // exception here leaves the `MethodResult` unanswered, and on this
        // embedding an unanswered result is indistinguishable from a slow call.
        try {
          this.dispatch(call, result);
        } catch (e) {
          const err = e as BusinessError;
          hilog.error(DOMAIN, TAG, 'dispatch threw for %{public}s: [%{public}d] %{public}s',
            call.method, err.code, err.message);
          result.error('DISPATCH_ERROR',
            `${call.method} 处理异常: [${err.code}] ${err.message}`, null);
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.tts = null;
  }

  private dispatch(call: MethodCall, result: MethodResult): void {
    hilog.warn(DOMAIN, TAG, 'dispatch %{public}s', call.method);
    switch (call.method) {
      case 'init':
        this.init(result);
        break;
      case 'speak':
        this.speak(call, result);
        break;
      default:
        result.notImplemented();
    }
  }

  // ── init ─────────────────────────────────────────────────────────
private init(result: MethodResult): void {
    if (this.tts !== null) {
      result.success({ 'ready': true, 'sampleRate': this.sampleRate });
      return;
    }
    const began = Date.now();
    // Asynchronous, and deliberately not synchronous. The first version copied
    // the model inline in this handler: 355 blocking reads plus a 17.8 MB one,
    // all on the platform thread. The device killed the process for it — no
    // error, no catch, the pid simply gone — which is the third time this
    // project has met a failure that only shows up as an absence.
    this.ensureModelOnDiskAsync((dir, failure) => {
      // Narrowed on `dir`, not on `failure`: the two are set together, but
      // ArkTS will not infer that `failure === null` implies `dir !== null`,
      // and the load below needs a plain `string`.
      if (dir === null) {
        hilog.error(DOMAIN, TAG, 'model unavailable: %{public}s', failure ?? 'unknown');
        result.error('SHERPA_INIT_FAILED', `模型不可用: ${failure ?? 'unknown'}`, null);
        return;
      }
      try {
        this.load(dir);
        hilog.warn(DOMAIN, TAG,
          'model loaded from %{public}s in %{public}dms, sampleRate=%{public}d',
          dir, Date.now() - began, this.sampleRate);
        result.success({ 'ready': true, 'sampleRate': this.sampleRate });
      } catch (e) {
        const err = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'load failed: [%{public}d] %{public}s', err.code, err.message);
        result.error('SHERPA_INIT_FAILED', `模型加载失败: [${err.code}] ${err.message}`, null);
      }
    });
  }

  private load(dir: string): void {
    this.modelDir = dir;

    // Built by construction rather than by object literal. These are classes
    // whose every field is declared, and ArkTS requires an object literal to
    // satisfy all of them — which for `OfflineTtsModelConfig` means also
    // filling in seven model families this app does not use.
    const vits: OfflineTtsVitsModelConfig = new OfflineTtsVitsModelConfig();
    vits.model = `${dir}/${MODEL_FILE}`;
    vits.tokens = `${dir}/${TOKENS_FILE}`;
    // espeak-ng-data, and it belongs on the **vits** config's `dataDir` rather
    // than on `OfflineTtsConfig.ruleFars`. Those are different things and the
    // engine's own diagnostic is what settles it: pointed at `ruleFars` it
    // answered "…/phontab does not exist. Please check --vits-data-dir", i.e.
    // it looks for the phonemiser under the vits data dir and nowhere else.
    // Piper VITS cannot make a sound without this, and loads happily without it.
    vits.dataDir = `${dir}/${ESPEAK_DIR}`;

    const model: OfflineTtsModelConfig = new OfflineTtsModelConfig();
    model.vits = vits;
    // `numThreads` / `debug` / `provider` live here, not on the vits config
    // and not on `OfflineTtsConfig` — the same layering trap the SDK's own
    // type names invite, and one this build already hit.
    model.numThreads = 2;
    // Left off in normal operation. It is the single most useful switch in this
// plugin — it turns "Please check your config!" into a line naming the file or
// field at fault, which is what located the espeak-ng-data mix-up — but it makes
// the native library log its whole config on every load.
model.debug = false;
    model.provider = 'cpu';

    const config: OfflineTtsConfig = new OfflineTtsConfig();
    config.model = model;
    // Left empty on purpose: this is the FST text-normalisation rule set, not the
    // phonemiser. See the `vits.dataDir` note above.
    config.ruleFars = '';
    config.maxNumSentences = 1;

    this.tts = new OfflineTts(config);
    this.sampleRate = this.tts.sampleRate;
  }

  /**
   * Copies the model out of the hap on first use, yielding between batches.
   *
   * `filesDir` rather than `cacheDir`: the OS is free to reclaim cacheDir under
   * pressure, and silently deleting a 35 MB model would turn every later launch
   * into another copy with no way to tell it happened.
   *
   * [done] receives the sandbox directory, or null plus a description. It is
   * never left uncalled: a copy that stops halfway is the one failure here that
   * would otherwise look exactly like a working model with no voice.
   *
   * The espeak tree ships **flat** (`espeak-flat/f0001`, `f0002`, …) and is
   * rebuilt into its real directory shape here. That is not tidiness: a nested
   * rawfile path such as `…/espeak-ng-data/lang/aav/vi` reads back as
   * `13900002 No such file or directory` on this platform even though the file
   * is in the hap — all 118 same-directory entries copy and the first nested one
   * fails. A flat name has no separator to get wrong, and the destination path
   * travels as manifest data instead.
   */
  private ensureModelOnDiskAsync(
    done: (dir: string | null, failure: string | null) => void
  ): void {
    const dir = `${this.context.filesDir}/${MODEL_DIR}`;
    let plan: StagePlan;
    try {
      plan = this.readPlan();
    } catch (e) {
      const err = e as BusinessError;
      done(null, `cannot read stage manifest: [${err.code}] ${err.message}`);
      return;
    }
    const missing = this.firstIncomplete(dir, plan);
    if (missing === null) {
      done(dir, null);
      return;
    }
    hilog.warn(DOMAIN, TAG,
      'staging model into %{public}s (%{public}d files, first missing: %{public}s)',
      dir, plan.steps.length, missing);
    let index = 0;
    const pump = (): void => {
      const deadline = Date.now() + COPY_BATCH_BUDGET_MS;
      try {
        while (index < plan.steps.length && Date.now() < deadline) {
          const step = plan.steps[index];
          index++;
          this.copyRawFile(`${MODEL_RAW_ROOT}/${step.rawName}`, `${dir}/${step.destRelative}`);
        }
      } catch (e) {
        const err = e as BusinessError;
        const at = index > 0 ? plan.steps[index - 1].destRelative : 'unknown';
        done(null, `copy failed at ${at}: [${err.code}] ${err.message}`);
        return;
      }
      if (index < plan.steps.length) {
        // Hand the thread back before continuing. Without this the whole copy
        // runs as one uninterruptible block and the device kills the app — no
        // error, no catch, the pid simply gone.
        setTimeout(pump, 0);
        return;
      }
      const stillMissing = this.firstIncomplete(dir, plan);
      if (stillMissing !== null) {
        done(null, `model incomplete after staging: ${stillMissing}`);
        return;
      }
      done(dir, null);
    };
    pump();
  }

  /** The staging manifest: which files, and how big the load-bearing ones must be. */
  private readPlan(): StagePlan {
    const bytes: Uint8Array = this.context.resourceManager
      .getRawFileContentSync(`${MODEL_RAW_ROOT}/${MANIFEST_FILE}`);
    const plan = new StagePlan();
    for (const raw of utf8Decode(bytes).split('\n')) {
      const line = raw.trim();
      if (line.length === 0) {
        continue;
      }
      const parts: string[] = line.split('\t');
      if (parts[0] === '#SIZE' && parts.length >= 3) {
        plan.sizes.set(parts[1], parseInt(parts[2], 10));
      } else if (parts[0] === '#FILE' && parts.length >= 3) {
        plan.steps.push(new StageStep(parts[1], parts[2]));
      }
    }
    if (plan.steps.length === 0) {
      throw new Error('stage manifest lists no files');
    }
    return plan;
  }

  /**
   * The first staged path that is absent or the wrong size, or null when the
   * staged model is whole.
   *
   * Size-checked rather than counted. A count is how a truncated 17.8 MB weight
   * file passes as complete — the file is present, the file count is right, and
   * then the engine loads the damaged file and the process dies with no error
   * line anywhere. Which is what happened.
   */
  private firstIncomplete(dir: string, plan: StagePlan): string | null {
    plan.sizes.forEach((expected: number, relative: string) => {
      const path = `${dir}/${relative}`;
      let actual = -1;
      try {
        actual = fs.statSync(path).size;
      } catch (e) {
        // Absent, which is a size of nothing for this purpose.
      }
      if (actual !== expected && this.reported !== relative) {
        this.reported = relative;
        hilog.warn(DOMAIN, TAG, 'not staged correctly: %{public}s is %{public}d bytes, want %{public}d',
          relative, actual, expected);
      }
    });
    for (const step of plan.steps) {
      if (!this.exists(`${dir}/${step.destRelative}`)) {
        return step.destRelative;
      }
    }
    return null;
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      // A missing path is the expected answer here, not a failure to report.
      return false;
    }
  }

  private copyRawFile(rawName: string, dest: string): void {
    const bytes: Uint8Array = this.context.resourceManager.getRawFileContentSync(rawName);
    const parent = parentOf(dest);
    // Recursive: the flat manifest restores a nested shape
    // (`espeak-ng-data/lang/aav/vi`), so the parent is usually several levels
    // deep and a single-level mkdir throws on the first branch.
    if (!fs.accessSync(parent)) {
      fs.mkdirSync(parent, true);
    }
    const handle = fs.openSync(
      dest,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(handle.fd, bytes.buffer);
    } finally {
      fs.closeSync(handle);
    }
  }

  // ── speak ────────────────────────────────────────────────────────

  private speak(call: MethodCall, result: MethodResult): void {
    const text = call.argument('text') as string;
    const speed = call.argument('speed') as number;
    const tts = this.tts;
    if (!text) {
      result.error('BAD_ARGS', 'text is required', null);
      return;
    }
    if (tts === null) {
      result.error('SHERPA_NOT_READY', '模型尚未初始化', null);
      return;
    }
    try {
      const began = Date.now();
      // `generate` takes one `TtsInput`, not `(text, sid, config)` — the
      // generation config is a separate overload (`generateWithConfig`).
      const input: TtsInput = new TtsInput();
      input.text = text;
      input.sid = SPEAKER_ID;
      input.speed = (speed > 0 ? speed : 1.0);
      const audio = tts.generate(input);
      const elapsed = Date.now() - began;
      if (audio.samples.length === 0) {
        // An empty buffer is what a phonemiser failure looks like from here:
        // no exception, no audio. Reported rather than handed on as a success,
        // because the caller would otherwise play a zero-length file.
        hilog.error(DOMAIN, TAG, 'generated no samples for %{public}s (%{public}d chars)',
          text, text.length);
        result.error('NO_SAMPLES', `合成结果为空: ${text}`, null);
        return;
      }
      const path = this.writeWav(audio.samples, audio.sampleRate);
      hilog.warn(DOMAIN, TAG,
        'generated %{public}d samples in %{public}dms (r=%{public}f), wav %{public}s',
        audio.samples.length, elapsed, audio.sampleRate, path);
      result.success({ 'path': path, 'ms': elapsed, 'sampleRate': audio.sampleRate });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'speak failed: [%{public}d] %{public}s', err.code, err.message);
      result.error('SHERPA_SPEAK_FAILED', `合成失败: [${err.code}] ${err.message}`, null);
    }
  }

  /** Wraps float samples in a 16-bit PCM WAV and returns the sandbox path. */
  private writeWav(samples: Float32Array, sampleRate: number): string {
    const dir = `${this.context.cacheDir}/turna_tts`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }
    const path = `${dir}/tts_${Date.now()}.wav`;
    const dataBytes = samples.length * 2;
    const buffer = new ArrayBuffer(44 + dataBytes);
    const view = new DataView(buffer);
    writeAscii(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataBytes, true);
    writeAscii(view, 8, 'WAVE');
    writeAscii(view, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, 1, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * 2, true);
    view.setUint16(32, 2, true);
    view.setUint16(34, 16, true);
    writeAscii(view, 36, 'data');
    view.setUint32(40, dataBytes, true);
    for (let i = 0; i < samples.length; i++) {
      const clamped = Math.max(-1.0, Math.min(1.0, samples[i]));
      view.setInt16(44 + i * 2, Math.round(clamped * 32767), true);
    }
    const handle = fs.openSync(
      path,
      fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(handle.fd, buffer);
    } finally {
      fs.closeSync(handle);
    }
    return path;
  }
}

function writeAscii(view: DataView, offset: number, text: string): void {
  for (let i = 0; i < text.length; i++) {
    view.setUint8(offset + i, text.charCodeAt(i));
  }
}

function parentOf(path: string): string {
  const slash = path.lastIndexOf('/');
  return slash === -1 ? '.' : path.slice(0, slash);
}

/// Decodes UTF-8 bytes. `util.TextDecoder` exists but a manifest is ASCII and
/// `String.fromCharCode` over the byte array keeps this to one line with no
/// second import to get wrong.
function utf8Decode(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}
