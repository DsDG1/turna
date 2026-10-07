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

// Ceiling on one `listVoices` call.
//
// This platform has already turned four promise-returning accessors into
// silence, and the voice query is a fifth candidate: the first log line in
// `voices()` used to sit *after* the await, so a query that never settled
// produced no line at all and the voice list looked empty rather than stuck.
// Every such call is bounded and every entry point logs before it awaits.
const _voiceQueryWaitMs: number = 3000;

// Both module types are queried when listing voices: the downloadable set is not
// the installed set, and only the union answers "could this device ever speak
// this language".
const VOICE_QUERY_MODULES: number[] = [0, 1];

// Resolves [work] or rejects with a named timeout.
//
// A hung platform call has to become a named failure, because silence is the one
// outcome that teaches nothing.
function awaitBounded<T>(work: Promise<T>, ms: number, what: string): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void,
                         reject: (reason: Error) => void) => {
    let settled: boolean = false;
    setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error(`${what} did not answer within ${ms}ms`));
      }
    }, ms);
    work.then((value: T) => {
      if (!settled) {
        settled = true;
        resolve(value);
      }
    }).catch((e: BusinessError) => {
      if (!settled) {
        settled = true;
        reject(e as Error);
      }
    });
  });
}

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
    for (const rung of await this.voiceLadder(languages)) {
      try {
        await this.createEngine(rung.language, rung.person);
        return new EngineProbe(true, rung, 0, '');
      } catch (e) {
        const err = e as BusinessError;
        lastCode = err.code;
        lastMessage = err.message;
        hilog.warn(DOMAIN, TAG, 'engine probe: %{public}s/%{public}d -> %{public}d',
          rung.language, rung.person, err.code);
      }
    }
    // Reported as a value rather than a rejection: ArkTS refuses to rethrow a
    // value it cannot prove is an Error, and a probe that ran out of rungs is a
    // result, not an exceptional path.
    const failed: EngineChoice = new EngineChoice('', 0);
    return new EngineProbe(false, failed, lastCode, lastMessage);
  }

  /**
   * The engine candidates to try, built from what the device reports.
   *
   * This used to be `[0..7]` guessed in source. A device run (CMM-AL10 /
   * OpenHarmony 7.0.0.109 / API 26) proved the guess wrong in a way that looked
   * like a language problem: `listVoices` reports `zh_CN person=13`,
   * `zh_CN person=21` and `en_US person=8`, so *none* of 0–7 exists. Every one of
   * them was refused with `1002300003 person not support` — for English and
   * Chinese alike — while `zh-CN person 0` was accepted and then produced an
   * engine that completed every utterance in ~44 ms with no audio. The
   * "English is unsupported" reading was wrong; English was never asked for
   * with a valid voice, and the one engine that did get built had no voice
   * behind it.
   *
   * Installed voices come first: a voice the device has not downloaded cannot
   * speak, and asking for one gets the same instant silent completion.
   */
  private async voiceLadder(languages: string[]): Promise<EngineChoice[]> {
    const rungs: EngineChoice[] = [];
    let voices: Array<textToSpeech.VoiceInfo> = [];
    try {
      voices = await awaitBounded(
        textToSpeech.listVoices({
          requestId: this.nextRequestId(),
          online: OFFLINE_MODULE,
        }),
        _voiceQueryWaitMs,
        'listVoices for the engine ladder',
      );
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG,
        'voice list unavailable ([%{public}d] %{public}s); falling back to the guessed ids',
        err.code, err.message);
    }
    if (voices.length === 0) {
      // No list, no better option than the old guess. Kept as a labelled last
      // resort rather than deleted, because a device that cannot answer the
      // query at all would otherwise get no engine and no sound whatsoever.
      for (const language of languages) {
        for (const person of PERSON_CANDIDATES) {
          rungs.push(new EngineChoice(language, person));
        }
      }
      return rungs;
    }
    const ordered = voices.slice().sort((a, b) => voiceRank(a) - voiceRank(b));
    for (const language of languages) {
      for (const voice of ordered) {
        if (sameLanguage(voice.language, language)) {
          rungs.push(new EngineChoice(voice.language, voice.person));
        }
      }
    }
    // Last: any voice the device has, in a language nobody asked for. A
    // wrong-language voice is still a voice; a missing one is silence.
    for (const voice of ordered) {
      if (!rungs.some((rung: EngineChoice) => sameLanguage(rung.language, voice.language))) {
        rungs.push(new EngineChoice(voice.language, voice.person));
      }
    }
    hilog.warn(DOMAIN, TAG, 'engine ladder: %{public}d rungs from %{public}d voices',
      rungs.length, voices.length);
    return rungs;
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
        hilog.warn(DOMAIN, TAG, 'supported voices: querying online=%{public}d', online);
        const list = await awaitBounded(
          textToSpeech.listVoices(query),
          _voiceQueryWaitMs,
          `listVoices(online=${online})`,
        );
        hilog.warn(DOMAIN, TAG, 'supported voices (online=%{public}d): %{public}d',
          online, list.length);
        for (const voice of list) {
          // `status` is dropped from [toVoiceEntry] — the Dart protocol only
          // carries language and person — so it is dropped here too, and that is
          // exactly the gap: an engine that builds for `zh-CN person 0` while no
          // offline voice is installed looks identical to one that really has a
          // voice. Logged rather than returned, so the wire protocol (and the
          // guard test over it) stays as it is.
          hilog.warn(DOMAIN, TAG, '  voice %{public}s person=%{public}d status=%{public}s',
            voice.language, voice.person, voice.status);
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
        hilog.warn(DOMAIN, TAG, 'installed voices: querying');
        const list = await awaitBounded(
          engine.listVoices(query),
          _voiceQueryWaitMs,
          'engine.listVoices',
        );
        hilog.warn(DOMAIN, TAG, 'installed voices: %{public}d', list.length);
        for (const voice of list) {
          hilog.warn(DOMAIN, TAG, '  installed %{public}s person=%{public}d status=%{public}s',
            voice.language, voice.person, voice.status);
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
    // The engine is single-voice: it was built for exactly one language/person
// pair, and asking it to speak with a different tag gets silence rather than an
// error. A device run sent `lang=zh_CN` to an engine created with `zh-CN` — the
// same language in two spellings, the caller's winning over the engine's — and
// the utterance completed in 44 ms with no audio. So the engine's own tag wins,
// and the disagreement is logged rather than silently absorbed: it is the
// difference between "this device has no voice for this language" and "the app
// asked the wrong voice".
const requested = (call.argument('language') as string) || this.engineLanguage;
const language = this.engineLanguage;
if (requested !== this.engineLanguage) {
      hilog.warn(DOMAIN, TAG,
        'asked for %{public}s but the engine is %{public}s; speaking with the engine',
        requested, this.engineLanguage);
    }
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
        // Logged before the call, with the text itself: a device run showed
        // `speak start` followed by `speak complete` **47 ms** later, twice, and
        // no `onError` at all. A word cannot be synthesised in 47 ms, so either
        // the text is not what the caller thinks it is, or the engine accepted
        // the request with no voice behind it. Those are indistinguishable from
        // the outside, so both halves go in the log.
        hilog.warn(DOMAIN, TAG,
          'speaking [%{public}s] %{public}s lang=%{public}s person=%{public}d rate=%{public}d',
          params.requestId, text, language, this.enginePerson, rate);
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

// `VoiceInfo.status` is a free-form string on this SDK; this is the value a
// device actually reports for a voice it can speak with.
const VOICE_INSTALLED: string = 'INSTALLED';

// Installed before merely available. `zh_CN person=21` and `en_US person=8`
// report `GA` on the device that produced this, which is not the same claim as
// `INSTALLED`.
function voiceRank(voice: textToSpeech.VoiceInfo): number {
  return voice.status === VOICE_INSTALLED ? 0 : 1;
}

// `createEngine` is called with the tag `listVoices` reported (`zh_CN`), so the
// two ends of every comparison have to agree on spelling as well as language:
// `zh-CN` and `zh_CN` are the same language in two notations, and treating them
// as different is how a valid voice gets skipped.
function sameLanguage(a: string, b: string): boolean {
  return normalizeLanguage(a) === normalizeLanguage(b);
}

function normalizeLanguage(raw: string): string {
  return raw.replace('_', '-').toLowerCase();
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
  // Start timestamps per request, so `onComplete` can say how long the engine
  // actually took.
  //
  // Duration is the one objective signal available for "did it synthesise".
  // A device run saw `speak start` → `speak complete` in 44 ms for a whole word,
  // which no synthesis can do, while reporting success and raising no error. A
  // completion that arrives in tens of milliseconds is the engine reporting that
  // it had nothing to render — but only a measured duration shows that, rather
  // than it being inferred from the absence of sound.
  private static startedAt: Map<string, number> = new Map();

  // `warn`, not `debug`, for all four: the default hilog level filters `debug`
  // out and the buffer rotates, so a `debug` line is not evidence — it is a
  // line that happens to exist. The only durable channel this app has is the
  // Dart transparency log, and an event that arrives after `speak` already
  // returned true cannot be routed through it. A device run therefore had "the
  // platform accepted the utterance" and nothing at all about whether the engine
  // then produced sound, which are the two things worth knowing.
  onStart(requestId: string, response: textToSpeech.StartResponse): void {
    TurnaSpeakListener.startedAt.set(requestId, Date.now());
    hilog.warn(DOMAIN, TAG, 'speak start %{public}s', requestId);
  }

  onComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    const began = TurnaSpeakListener.startedAt.get(requestId);
    if (began === undefined) {
      // A completion with no matching start: the engine reported the end of
      // something that never began, which is its own kind of evidence.
      hilog.warn(DOMAIN, TAG, 'speak complete %{public}s (no start recorded)', requestId);
      return;
    }
    hilog.warn(DOMAIN, TAG, 'speak complete %{public}s after %{public}dms',
      requestId, Date.now() - began);
    TurnaSpeakListener.startedAt.delete(requestId);
  }

  onStop(requestId: string, response: textToSpeech.StopResponse): void {
    hilog.warn(DOMAIN, TAG, 'speak stopped %{public}s', requestId);
  }

  onError(requestId: string, errorCode: number, errorMessage: string): void {
    hilog.error(DOMAIN, TAG, 'speak error %{public}s [%{public}d] %{public}s',
      requestId, errorCode, errorMessage);
  }
}
