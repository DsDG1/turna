// Copyright (c) 2024 Turna. All rights reserved.
//
// ADR 0050 §6 step 5b probe payloads.
//
// Everything here is data the probe serves over the synthetic
// `https://anki.local` origin. It deliberately mirrors
// `assets/anki_reviewer/reviewer.html` and `card-frame.html` — same CSP, same
// `<base href>`, same frame relationship — because ADR 0050's acceptance
// criterion for 5b is "can ArkUI `Web` satisfy the reviewer's CSP", and a probe
// with a looser CSP would answer a question nobody asked.
//
// The media fixture is a WAV this file synthesises rather than an asset the
// bundle carries. The reviewer ability is a separate ability with no
// FlutterAssetManager, so a bundled asset is not reachable from where the
// interception happens; and a synthesised WAV keeps the probe honest about the
// one property under test (does the kernel send Range and honour our 206)
// without adding a second question about who owns the bytes.
//
// R1 (2026-10-17) moved this file out of `ets/anki/` into `ets/probe/`. Nothing
// here changed except its address.
//
// ALLOWED DIFFERENCES FROM THE PRODUCTION HTTP/MIME MIRROR
//
// Range and MIME have three implementations by design: Dart's
// `OfficialAnkiHttpRange`/`OfficialAnkiMime` are the normative source,
// `anki/AnkiHttp.ets` is the production ArkTS mirror, and the Range/MIME pair
// at the bottom of THIS file is the probe's. The probe's copy is deliberately
// looser on exactly three axes, and they are deliberate — do not "fix" them
// into a regression, and do not close them without updating this list:
//
//   1. `parseRange`, unrecognised prefix. Production answers 416 for a Range
//      header that does not start with `bytes=`; the probe answers 200 with the
//      whole file. Rationale: this probe's question is "does the kernel issue a
//      Range request and can it seek in what we serve", so a request we cannot
//      classify must still leave the probe something to measure. Production has
//      the opposite requirement — a server that answers 200 to every Range is
//      one the kernel cannot seek in.
//   2. `parseRange`, unparseable spec. Production answers 416 for a spec with no
//      dash, an empty spec, or a comma (multi-range); the probe falls back to
//      the whole file. Same reason as (1).
//   3. `mimeForName` / `encodingForMime`. Production maps `.js` to
//      `text/javascript` and gates utf-8 on `text/*` or `application/json`
//      (after stripping `;` parameters); the probe maps `.js` to
//      `application/javascript` — also accepted by the kernel — and gates on
//      `text/*` or anything ending in `javascript`. The probe serves four asset
//      kinds and has no `application/json`, so the narrower production table
//      would only be dead code here.
//
// These three are pinned by
// `test/application/anki_official/official_anki_reviewer_protocol_guard_test.dart`
// (differential needles against both files), so silently replacing one
// implementation with the other fails the gate rather than the field.

export const ANKI_ORIGIN: string = 'https://anki.local';

/// The CSP under test, copied from `assets/anki_reviewer/reviewer.html`.
/// `connect-src 'none'` is the load-bearing clause: it is the only directive
/// whose violation proves the kernel is actually enforcing this policy rather
/// than silently ignoring the `<meta http-equiv>`.
const PROBE_CSP: string =
  "default-src 'none'; img-src https://anki.local data: blob:; " +
  'media-src https://anki.local data: blob:; ' +
  'font-src https://anki.local data:; ' +
  "style-src 'unsafe-inline' https://anki.local; " +
  "script-src 'unsafe-inline' https://anki.local; " +
  "connect-src 'none'; " +
  'frame-src https://anki.local; ' +
  "object-src 'none'; " +
  'base-uri https://anki.local/media/; ' +
  "form-action 'none';";

/// The outer document. Loads its stylesheet and script as subresources (so a
/// successful paint proves the interception handler serves `script-src` and
/// `style-src` hits, not just the inline case) and hosts the card frame in an
/// iframe, which is the shape `reviewer.js` relies on.
export function probeShellHtml(): string {
  return '<!DOCTYPE html>\n<html lang="en">\n<head>\n' +
    '  <meta charset="utf-8">\n' +
    '  <meta http-equiv="Content-Security-Policy" content="' + PROBE_CSP + '">\n' +
    '  <base href="https://anki.local/media/">\n' +
    '  <title>Anki Reviewer Probe</title>\n' +
    '  <link rel="stylesheet" href="https://anki.local/assets/probe.css">\n' +
    '</head>\n' +
    '<body class="reviewer-shell">\n' +
    '  <div id="shell-marker">shell</div>\n' +
    '  <iframe id="card-frame" src="https://anki.local/assets/frame.html"></iframe>\n' +
    '  <audio id="clip" src="https://anki.local/media/probe.wav"></audio>\n' +
    '  <script src="https://anki.local/assets/probe.js"></script>\n' +
    '</body>\n</html>\n';
}

/// The card frame, CSP copied from `card-frame.html` — note `frame-src 'none'`
/// here and the narrowed `base-uri`. Its inline script leaves a marker on the
/// body rather than posting a message: the parent reads it same-origin, which
/// cannot race the way a `postMessage` from a frame that parses first can.
export function probeFrameHtml(): string {
  const frameCsp: string = PROBE_CSP.replace('frame-src https://anki.local;', "frame-src 'none';");
  return '<!DOCTYPE html>\n<html lang="en">\n<head>\n' +
    '  <meta charset="utf-8">\n' +
    '  <meta http-equiv="Content-Security-Policy" content="' + frameCsp + '">\n' +
    '  <base href="https://anki.local/media/">\n' +
    '  <title>Probe Card Frame</title>\n' +
    '</head>\n' +
    '<body class="card card-frame">\n' +
    '  <div id="frame-marker">frame</div>\n' +
    '  <script>document.body.setAttribute("data-probe-script", "ran");</script>\n' +
    '</body>\n</html>\n';
}

export function probeCss(): string {
  return 'html,body{margin:0;padding:0;background:#fff;color:#111;' +
    'font-family:sans-serif}\n' +
    '#shell-marker{font-size:20px;padding:8px}\n' +
    'iframe{width:100%;height:120px;border:1px solid #ccc}\n';
}

/// The probe's driver script. Deliberately written as string concatenation
/// rather than template literals: this text is assembled inside a template
/// literal in ArkTS, and a literal `${` inside it would be interpolated by the
/// outer file instead of reaching the browser.
///
/// It never reports success on its own authority. Every claim it makes is
/// backed by an observable the ArkTS side also records — a subresource that
/// either painted or did not, a request that either carried a Range header or
/// did not. A probe that can only report "I ran" would pass on a blank page.
export function probeJs(): string {
  return [
    '(function () {',
    '  var out = {',
    '    shellSubresource: "pending",',
    '    frame: "pending",',
    '    cspConnect: "pending",',
    '    audioState: "pending",',
    '    audioDuration: -1,',
    '    audioError: -1,',
    '    seekPhase: "pending",',
    '    seekApplied: -1,',
    '    seekReadBack: -1,',
    '    playRejected: ""',
    '  };',
    '  var settled = 0;',
    '  var reported = false;',
    '  // Five, not four: seekPhase is a check too. Counting only the four',
    '  // automatic ones made the verdict land roughly a second after load --',
    '  // long before a human could reach PLAY + SEEK -- and the ability then',
    '  // terminated itself, so phase 4b was unreachable in practice and every',
    '  // run reported it as "pending". Counting it keeps that question open and',
    '  // answerable: the verdict now waits for the gesture, or for the 30 s',
    '  // no-gesture fallback, which still fits inside the ability 40 s timeout.',
    '  var PENDING = 5;',
    '  // Every check settles before anything is reported. An earlier version',
    '  // reported from the first callback to fire, so the verdict came back',
    '  // while the media checks had not run and reported them as "pending" —',
    '  // a probe declaring its own impatience to be a result.',
    '  function finish(name, value) {',
    '    if (out[name] !== "pending") { return; }',
    '    out[name] = value;',
    '    settled += 1;',
    '    report();',
    '  }',
    '  function report() {',
    '    if (reported || settled < PENDING) { return; }',
    '    reported = true;',
    '    if (window.AnkiProbeNative) {',
    '      window.AnkiProbeNative.report(JSON.stringify(out));',
    '    }',
    '  }',
    '  // 1. The stylesheet is a subresource under style-src. If it parsed, the',
    '  //    interception served it.',
    '  var link = document.querySelector("link[rel=stylesheet]");',
    '  finish("shellSubresource", link && link.sheet ? "loaded" : "missing");',
    '  // 2. connect-src is \'none\'. A fetch must therefore fail. The URL is',
    '  //    one the server counts: if it shows up in the server transcript,',
    '  //    the kernel ignored the policy and this page\'s claim was a lie.',
    '  try {',
    '    fetch("https://anki.local/assets/must-not-be-fetched.css")',
    '      .then(function () { finish("cspConnect", "leaked"); })',
    '      .catch(function () { finish("cspConnect", "blocked"); });',
    '  } catch (e) {',
    '    finish("cspConnect", "blocked");',
    '  }',
    '  // 3. The iframe is the reviewer\'s card host. Read it same-origin rather',
    '  //    than by postMessage: an earlier version used postMessage and raced,',
    '  //    because the frame can parse and post before this subresource script',
    '  //    has registered its listener. Same-origin access exists precisely',
    '  //    because onInterceptRequest makes the synthetic origin real.',
    '  var frameDeadline = Date.now() + 4000;',
    '  (function pollFrame() {',
    '    var frame = document.getElementById("card-frame");',
    '    var doc = null;',
    '    try { doc = frame ? frame.contentDocument : null; } catch (e) { doc = null; }',
    '    if (doc && doc.body && doc.body.getAttribute("data-probe-script") === "ran") {',
    '      finish("frame", "loaded");',
    '      return;',
    '    }',
    '    if (Date.now() > frameDeadline) {',
    '      finish("frame", doc ? "parsed-no-script" : "no-document");',
    '      return;',
    '    }',
    '    setTimeout(pollFrame, 120);',
    '  })();',
    '  // 4. Media. Two questions, asked separately, because the first run',
    '  //    answered the first and left the second open.',
    '  //',
    '  //    4a. LOAD — does the kernel send Range, and does it take the 206?',
    '  //        Settled by metadata alone.',
    '  //    4b. SEEK — does moving currentTime issue a sub-range request?',
    '  //        Settled only after a real user gesture. The first run set',
    '  //        currentTime on an element autoplay had left never-played and',
    '  //        read back -1, which does not distinguish "seeking is',
    '  //        unsupported" from "a paused element does not fetch". Different',
    '  //        answers, and only a gesture separates them.',
    '  var audio = document.getElementById("clip");',
    '  if (!audio) {',
    '    finish("audioState", "no-element");',
    '    return;',
    '  }',
    '  audio.addEventListener("error", function () {',
    '    out.audioError = audio.error ? audio.error.code : -1;',
    '    finish("audioState", "error");',
    '  });',
    '  function attemptSeek() {',
    '    if (out.audioState !== "pending") { return; }',
    '    out.audioState = "ready";',
    '    out.audioDuration = isFinite(audio.duration) ? audio.duration : -1;',
    '    settled += 1;',
    '    report();',
    '  }',
    '  audio.addEventListener("loadedmetadata", attemptSeek);',
    '  audio.addEventListener("canplaythrough", attemptSeek);',
    '  audio.load();',
    '  try {',
    '    var p = audio.play();',
    '    if (p && p.catch) { p.catch(function (err) { out.playRejected = err.name; }); }',
    '  } catch (e) {',
    '    out.playRejected = "threw";',
    '  }',
    '  // Phase 4b. Driven by ArkTS when the user taps the page\'s button, so',
    '  //    the element is playing when currentTime moves.',
    '  window.__probeSeek = function () {',
    '    if (out.seekPhase !== "pending") { return "already"; }',
    '    out.seekPhase = "started";',
    '    var clip = document.getElementById("clip");',
    '    var playback = clip.play();',
    '    if (playback && playback.catch) { playback.catch(function (err) { out.seekPlayError = err.name; }); }',
    '    setTimeout(function () {',
    '      out.seekPlaying = !clip.paused;',
    '      clip.currentTime = 1.0;',
    '      out.seekApplied = 1.0;',
    '      setTimeout(function () {',
    '        out.seekReadBack = clip.currentTime;',
    '        out.seekPhase = "done";',
    '        settled += 1;',
    '        report();',
    '      }, 900);',
    '    }, 500);',
    '    return "started";',
    '  };',
    '  setTimeout(function () { finish("audioState", "timeout"); }, 12000);',
    '  setTimeout(function () { finish("seekPhase", "not-gestured"); }, 30000);',
    '})();'
  ].join('\n');
}

/// 8 kHz, 16-bit signed, mono. Two seconds: long enough that Chromium has a
/// reason to range-request it, short enough to seek inside without waiting.
/// 16-bit rather than 8-bit because an earlier fixture used 8-bit, and a
/// decoder that merely tolerates a format is not the same as one that seeks
/// within it — the probe is about seeking, so the fixture should be the most
/// ordinary PCM WAV there is and leave no room for a format excuse.
export function probeWav(): ArrayBuffer {
  const sampleRate: number = 8000;
  const seconds: number = 2;
  const dataLength: number = sampleRate * seconds;
  const total: number = 44 + dataLength * 2;
  const buffer: ArrayBuffer = new ArrayBuffer(total);
  const view: DataView = new DataView(buffer);
  let offset: number = 0;
  const writeAscii = (text: string): void => {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset, text.charCodeAt(i));
      offset += 1;
    }
  };
  writeAscii('RIFF');
  view.setUint32(offset, total - 8, true);
  offset += 4;
  writeAscii('WAVE');
  writeAscii('fmt ');
  view.setUint32(offset, 16, true);
  offset += 4;
  view.setUint16(offset, 1, true); // PCM
  offset += 2;
  view.setUint16(offset, 1, true); // mono
  offset += 2;
  view.setUint32(offset, sampleRate, true);
  offset += 4;
  view.setUint32(offset, sampleRate * 2, true); // byte rate
  offset += 4;
  view.setUint16(offset, 2, true); // block align
  offset += 2;
  view.setUint16(offset, 16, true); // bits per sample
  offset += 2;
  writeAscii('data');
  view.setUint32(offset, dataLength * 2, true);
  offset += 4;
  for (let i = 0; i < dataLength; i++) {
    view.setInt16(offset, Math.round(8000 * Math.sin(i / 40)), true);
    offset += 2;
  }
  return buffer;
}

const MIME_BY_EXTENSION: Record<string, string> = {
  '.html': 'text/html',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.wav': 'audio/wav',
};

/// Unknown extensions get `application/octet-stream`, matching
/// `OfficialAnkiMime`. It matters: the kernel picks a decoder from the MIME
/// type, and an unknown-but-parsed audio element is a different failure from
/// a correctly typed one.
export function mimeForName(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0) {
    return 'application/octet-stream';
  }
  const key: string = name.substring(dot).toLowerCase();
  const hit: string | undefined = MIME_BY_EXTENSION[key];
  return hit !== undefined ? hit : 'application/octet-stream';
}

export function encodingForMime(mime: string): string {
  return mime.startsWith('text/') || mime.endsWith('javascript') ? 'utf-8' : '';
}

/// A parsed `Range` header. Mirrors `OfficialAnkiHttpRange` on Android: the
/// reviewer serves `Accept-Ranges: bytes`, so the kernel is entitled to ask
/// for a slice and entitled to be told 416 when the slice is nonsense.
export interface RangeSpec {
  start: number;
  end: number;
  contentLength: number;
  status: number;
  satisfiable: boolean;
  contentRange: string;
}

/// Returns a full-file spec when [raw] is absent or unrecognised. Only the
/// single-range `bytes=a-b` form is supported — a multi-range request would
/// need a multipart/byteranges body, and no browser issues one for `<audio>`.
export function parseRange(raw: string, fileLength: number): RangeSpec {
  const whole: RangeSpec = {
    start: 0,
    end: fileLength - 1,
    contentLength: fileLength,
    status: 200,
    satisfiable: true,
    contentRange: 'bytes 0-' + String(fileLength - 1) + '/' + String(fileLength),
  };
  if (raw.length === 0 || fileLength <= 0) {
    return whole;
  }
  const prefix: string = 'bytes=';
  if (!raw.toLowerCase().startsWith(prefix)) {
    return whole;
  }
  const spec: string = raw.substring(prefix.length).trim();
  const dash: number = spec.indexOf('-');
  if (dash <= 0) {
    return whole;
  }
  const startText: string = spec.substring(0, dash);
  const endText: string = spec.substring(dash + 1);
  const start: number = startText.length === 0 ? fileLength - Number(endText) : Number(startText);
  let end: number = endText.length === 0 ? fileLength - 1 : Number(endText);
  if (!isFinite(start) || !isFinite(end) || start < 0 || start >= fileLength) {
    return {
      start: 0,
      end: 0,
      contentLength: 0,
      status: 416,
      satisfiable: false,
      contentRange: 'bytes */' + String(fileLength),
    };
  }
  if (end > fileLength - 1) {
    end = fileLength - 1;
  }
  if (end < start) {
    return {
      start: 0,
      end: 0,
      contentLength: 0,
      status: 416,
      satisfiable: false,
      contentRange: 'bytes */' + String(fileLength),
    };
  }
  return {
    start: start,
    end: end,
    contentLength: end - start + 1,
    status: 206,
    satisfiable: true,
    contentRange: 'bytes ' + String(start) + '-' + String(end) + '/' + String(fileLength),
  };
}
