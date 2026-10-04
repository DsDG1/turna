// Copyright (c) 2024 Turna. All rights reserved.
// Text-to-speech for HarmonyOS — bridges @kit.CoreSpeechKit to Flutter via
// MethodChannel.
//
// `flutter_tts` has no OpenHarmony implementation, and its community fork
// cannot be used: it names `TargetPlatform.ohos` in its own Dart source and
// adds public API upstream lacks, which is unrepresentable under the global,
// platform-blind `dependency_overrides` this project is built with (ADR 0047
// §7.3). So the companion build speaks through the platform engine directly.
//
// The engine model is not Android's. Android exposes a *list of engines* the
// app selects from and per-language "voice data installed" flags; CoreSpeechKit
// exposes one engine and a *list of voices* it already knows about. The Dart
// side keeps its Android engine-selection code untouched and gets its locale
// answers from `listVoices` instead.

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';

const TAG = "TtsPlugin";
const CHANNEL = "me.dsdogs.turna/tts";
const DOMAIN = 0xA700;

// Used when the requested language cannot initialise an engine. Any widely
// installed voice will do: the point is to have *a* working engine so the voice
// list can be queried and utterances can carry their own locale, not to speak
// in this language.
const FALLBACK_LANGUAGES: string[] = ['en-US', 'zh-CN'];

// The voice ("person") id is discovered rather than assumed.
//
// `CreateEngineParams` requires a `person`, but there is no API that lists valid
// ids without an engine, and the obvious `0` is rejected on real hardware:
// Mate 90 Pro Max / API 26 answers `1002300003 create param is error, person not
// support!`. So the candidates are tried in order and the first one that builds
// an engine is remembered for the life of the process.
const PERSON_CANDIDATES: number[] = [0, 1, 2, 3, 4, 5, 6, 7];

// `online: 1` selects the offline (on-device) module per the SDK docs. Online
// voices need a network round trip and would make lesson playback depend on
// connectivity.
const OFFLINE_MODULE = 1;

// Both module types are queried when listing voices: the downloadable set is not
// the installed set, and only the union answers "could this device ever speak
// this language".
const VOICE_QUERY_MODULES: number[] = [0, 1];

export default class TtsPlugin implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  // The language the engine was actually created with, which is not necessarily
  // the one asked for. Reported back to Dart so a log can say which voice the
  // sound came from instead of guessing.
  private engineLanguage: string = '';
  // The voice id the engine was built with. Sent with every utterance: the
  // engine is single-voice, and a request that omits `person` speaks with
  // whatever the engine happens to hold rather than the one that was probed.
  private enginePerson: number = 0;
  private requestSeq: number = 0;

  getUniqueClassName(): string {
    return "TtsPlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        switch (call.method) {
          case 'init':
            this.init(call, result);
            break;
          case 'voices':
            this.voices(result);
            break;
          case 'speak':
            this.speak(call, result);
            break;
          case 'stop':
            this.stop(result);
            break;
          case 'shutdown':
            this.shutdown(result);
            break;
          default:
            result.notImplemented();
        }
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.engine?.shutdown();
    this.engine = null;
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  // ── method handlers ──────────────────────────────────────────────

  private init(call: MethodCall, result: MethodResult): void {
    const requested = (call.argument('language') as string) || FALLBACK_LANGUAGES[0];
    if (this.engine) {
      result.success({ language: this.engineLanguage });
      return;
    }
    // A language the device cannot build an engine for is a normal condition,
    // not a plugin fault: the app asks for the course language and the device
    // may not have that voice. Mate 90 Pro Max, for instance, answers
    // `1002300002 … language not support!` for `tr`. Each candidate is therefore
    // a rung on a ladder rather than a failure, and the caller is told which one
    // was accepted so a log can name the voice instead of guessing.
    this.probeEngine(requested)
      .then((probe: EngineProbe) => {
        if (!probe.found || !probe.choice) {
          result.error('TTS_INIT_FAILED',
            `语音引擎初始化失败: [${probe.code}] ${probe.message}`, null);
          return;
        }
        const degraded: boolean = probe.choice.language !== requested;
        result.success({
          'language': probe.choice.language,
          'person': probe.choice.person,
          'requested': requested,
          'degraded': degraded,
        });
      })
      .catch((e: BusinessError) => {
        result.error('TTS_INIT_FAILED',
          `语音引擎初始化失败: [${e.code}] ${e.message}`, null);
      });
  }

  private async probeEngine(requested: string): Promise<EngineProbe> {
    const languages: string[] = [requested];
    for (const candidate of FALLBACK_LANGUAGES) {
      if (candidate !== requested) {
        languages.push(candidate);
      }
    }

    let lastCode: number = 0;
    let lastMessage: string = '';
    for (const language of languages) {
      for (const person of PERSON_CANDIDATES) {
        try {
          await this.createEngine(language, person);
          const choice: EngineChoice = new EngineChoice(language, person);
          return new EngineProbe(true, choice, 0, '');
        } catch (e) {
          const err = e as BusinessError;
          lastCode = err.code;
          lastMessage = err.message;
          hilog.debug(DOMAIN, TAG, 'engine probe: %{public}s/%{public}d -> %{public}d',
            language, person, err.code);
        }
      }
    }
    // Reported as a value rather than a rejection: ArkTS refuses to rethrow a
    // value it cannot prove is an Error, and a probe that ran out of rungs is a
    // result, not an exceptional path.
    const failed: EngineChoice = new EngineChoice('', 0);
    return new EngineProbe(false, failed, lastCode, lastMessage);
  }

  private createEngine(language: string, person: number): Promise<void> {
    const params: textToSpeech.CreateEngineParams = {
      language: language,
      person: person,
      online: OFFLINE_MODULE,
    };
    return new Promise<void>((resolve: () => void,
                              reject: (reason: BusinessError) => void) => {
      textToSpeech.createEngine(params, (err: BusinessError, engine: textToSpeech.TextToSpeechEngine) => {
        if (err) {
          reject(err);
          return;
        }
        this.engine = engine;
        this.engineLanguage = language;
        this.enginePerson = person;
        // `speak` returns as soon as the request is accepted, so a voice that
        // refuses to speak is only visible through the listener. Without one,
        // "installed engine, no sound" is indistinguishable from a muted
        // device. The SDK also requires a listener before `stop` can report
        // anything.
        engine.setListener(new TurnaSpeakListener());
        hilog.info(DOMAIN, TAG, 'engine created for %{public}s person %{public}d',
          language, person);
        resolve();
      });
    });
  }

  /**
   * Reports the voices the device can speak with, split in two.
   *
   * `installed` is what the engine holds right now; `supported` is everything the
   * platform says it can provide, which includes voices that are downloadable
   * but not yet on the device. The split is the whole point: "no Turkish voice
   * exists" and "Turkish voice exists, download it" call for different answers,
   * and collapsing them into one empty list is what makes a missing voice look
   * like a broken feature.
   *
   * The namespace-level `listVoices` is the one that knows about downloadable
   * voices; the engine method only reports what it can already use. Both are
   * queried, for both module types, and merged.
   */
  private async voices(result: MethodResult): Promise<void> {
    const supported: Array<VoiceEntry> = [];
    for (const online of VOICE_QUERY_MODULES) {
      try {
        const query: textToSpeech.VoiceQuery = {
          requestId: this.nextRequestId(),
          online: online,
        };
        const list = await textToSpeech.listVoices(query);
        for (const voice of list) {
          supported.push(toVoiceEntry(voice));
        }
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'supported voices (online=%{public}d) failed: '
          + '[%{public}d] %{public}s', online, err.code, err.message);
      }
    }

    const installed: Array<VoiceEntry> = [];
    const engine = this.engine;
    if (engine) {
      try {
        const query: textToSpeech.VoiceQuery = {
          requestId: this.nextRequestId(),
          online: OFFLINE_MODULE,
        };
        const list = await engine.listVoices(query);
        for (const voice of list) {
          installed.push(toVoiceEntry(voice));
        }
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'installed voices failed: [%{public}d] %{public}s',
          err.code, err.message);
      }
    }

    const reply: Record<string, Object> = {
      'installed': installed,
      'supported': supported,
    };
    result.success(reply);
  }

  private speak(call: MethodCall, result: MethodResult): void {
    const text = call.argument('text') as string;
    if (!text) {
      result.error('BAD_ARGS', 'text is required', null);
      return;
    }
    const language = (call.argument('language') as string) || this.engineLanguage;
    const rate = call.argument('rate') as number;

    this.withEngine(result, (engine: textToSpeech.TextToSpeechEngine) => {
      // `rate` is a 0–100 percentage where 50 is the engine's own default. The
      // conversion from the app's speed multiplier happens in Dart so it can be
      // unit-tested without a device.
      const extra: Record<string, Object> = {
        'language': language,
        'person': this.enginePerson,
        'rate': rate,
      };
      const params: textToSpeech.SpeakParams = {
        requestId: this.nextRequestId(),
        extraParams: extra,
      };
      try {
        engine.speak(text, params);
        result.success(true);
      } catch (e) {
        const err = e as BusinessError;
        result.error('TTS_SPEAK_FAILED', `朗读失败: [${err.code}] ${err.message}`, null);
      }
    });
  }

  private stop(result: MethodResult): void {
    const engine = this.engine;
    if (!engine) {
      result.success(null);
      return;
    }
    try {
      engine.stop();
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      // Stopping is always best-effort on the Dart side too (it runs on the
      // path that clears a half-played clip before the next one), so a refusal
      // is reported but not treated as a failure by the caller.
      result.error('TTS_STOP_FAILED', `停止朗读失败: [${err.code}] ${err.message}`, null);
    }
  }

  private shutdown(result: MethodResult): void {
    const engine = this.engine;
    this.engine = null;
    this.engineLanguage = '';
    this.enginePerson = 0;
    if (!engine) {
      result.success(null);
      return;
    }
    try {
      engine.shutdown();
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      result.error('TTS_SHUTDOWN_FAILED', `关闭语音引擎失败: [${err.code}] ${err.message}`, null);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────

  /**
   * Runs [body] with a live engine, answering [result] itself when there is
   * none. Every entry point needs the engine, and answering "not initialised"
   * from four places invites the four to drift apart.
   */
  private withEngine(result: MethodResult,
                      body: (engine: textToSpeech.TextToSpeechEngine) => void): void {
    const engine = this.engine;
    if (!engine) {
      result.error('TTS_NOT_READY', '语音引擎尚未初始化', null);
      return;
    }
    body(engine);
  }

  // The SDK requires a unique request id per call; reusing one makes the engine
  // drop the later request.
  private nextRequestId(): string {
    this.requestSeq += 1;
    return `turna-${Date.now()}-${this.requestSeq}`;
  }
}

class VoiceEntry {
  language: string;
  person: number;

  constructor(language: string, person: number) {
    this.language = language;
    this.person = person;
  }
}

/// The language / voice pair the engine was actually built with.
class EngineChoice {
  language: string;
  person: number;

  constructor(language: string, person: number) {
    this.language = language;
    this.person = person;
  }
}

/// Outcome of walking the language / voice ladder.
class EngineProbe {
  found: boolean;
  choice: EngineChoice | null;
  code: number;
  message: string;

  constructor(found: boolean, choice: EngineChoice | null, code: number, message: string) {
    this.found = found;
    this.choice = choice;
    this.code = code;
    this.message = message;
  }
}

function toVoiceEntry(voice: textToSpeech.VoiceInfo): VoiceEntry {
  return new VoiceEntry(voice.language, voice.person);
}

/**
 * Reports what the engine did after a request was accepted.
 *
 * Only `onError` is acted on, and only by logging: a failure here arrives long
 * after the Dart `speak` call returned true, so there is no reply left to fail.
 * It still has to be recorded — the alternative is a device that plays nothing
 * with no trace of why. The other three callbacks are required by the interface
 * and say nothing this plugin needs.
 */
class TurnaSpeakListener implements textToSpeech.SpeakListener {
  onStart(requestId: string, response: textToSpeech.StartResponse): void {
    hilog.debug(DOMAIN, TAG, 'speak start %{public}s', requestId);
  }

  onComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    hilog.debug(DOMAIN, TAG, 'speak complete %{public}s', requestId);
  }

  onStop(requestId: string, response: textToSpeech.StopResponse): void {
    hilog.debug(DOMAIN, TAG, 'speak stopped %{public}s', requestId);
  }

  onError(requestId: string, errorCode: number, errorMessage: string): void {
    hilog.error(DOMAIN, TAG, 'speak error %{public}s [%{public}d] %{public}s',
      requestId, errorCode, errorMessage);
  }
}
