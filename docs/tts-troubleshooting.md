# TTS troubleshooting

## Architecture (short)

| Mode | Path |
|------|------|
| **System TTS** (default) | Android: force `com.google.android.tts` → resolve `sw` / `sw-KE` / `sw-TZ` → `flutter_tts.speak` → on failure, Piper |
| **Offline Piper** | Bundled `sw_CD-lanfrica-medium` via `sherpa_onnx` → on failure, system |

## "Google TTS is installed but the app cannot use it"

1. **Rebuild after Manifest fix** — Android 11+ requires:

   ```xml
   <queries>
     <intent>
       <action android:name="android.intent.action.TTS_SERVICE" />
     </intent>
     <package android:name="com.google.android.tts" />
   </queries>
   ```

   Without this, `getEngines` is often empty even when Google TTS is installed.

2. **Download Swahili voice data** — Installing the Google TTS *app* is not enough. In system **Text-to-speech** settings → Google → install **Swahili / Kiswahili**.

3. **App setting stuck on Offline** — Settings → **Voice source** → **System TTS**. Splash may have set Offline Piper once.

4. **Logcat keywords**

   - `TtsAvailabilityChecker: engines=...` — empty list ⇒ package visibility / no engines
   - `selected Google TTS engine`
   - `resolved installed language "sw-KE"...`
   - `TTS route: system primary` vs `piper fallback` / `offline primary`
   - `setLanguage(...) failed` — locale missing

## "Piper does not sound like Swahili"

The bundled model **is** Swahili (`sw_CD`, espeak voice `sw`, lanfrica dataset). It is:

- Congo (DRC) accent, not East African (KE/TZ)
- Finetuned from an English (lessac) base voice
- int8-quantized

Prefer **System / Google TTS** for learning quality.

## Manual check on device

1. Settings → Voice source → System TTS  
2. Open system TTS settings → preferred engine Google → install Swahili  
3. Tap Voice source → **Play sample (Habari)**  
4. Snackbar should say `Playing: Google / system TTS`  
5. Log: `TTS route: system primary OK`

## Offline Piper not playing

1. Settings → Voice source → **Offline Piper**  
2. Play sample — Snackbar must say `Playing: Offline Piper`  
3. If Snackbar says *Wanted Offline Piper, but it failed — played Google/system instead*:
   - Tap **Retry offline Piper init…**
   - Check logcat for `PiperSwahiliTts init failed` / `offline primary`
4. Piper should sound **different** from Google (Congo accent, more synthetic).

### Sticky init failure

If early `prewarm()` failed, older builds permanently set `_initFailed`. Current builds auto-retry a few times and expose **Retry offline Piper init**.

## Higher-quality offline model options (Part 2)

| Option | Notes |
|--------|--------|
| Current: Piper `sw_CD-lanfrica-medium` int8 | Only official Piper Swahili; Congo accent |
| Piper full (non-int8) same voice | Slight quality gain; same accent; looser license |
| Meta `facebook/mms-tts-swh` via sherpa-onnx | Better naturalness candidate; **often CC-BY-NC** — confirm before shipping in store APK |
| Google system TTS | Best quality when installed; keep as default |

There is **no** official Piper `sw_KE` / high-quality East African voice in rhasspy/piper-voices.