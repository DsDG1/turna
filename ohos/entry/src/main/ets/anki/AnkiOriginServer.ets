// Copyright (c) 2024 Turna. All rights reserved.
//
// The production `https://anki.local` origin for the HarmonyOS reviewer.
//
// This is the ArkTS counterpart of `OfficialAnkiMediaHandler.kt`, and the shape
// of it — native path rules, native Range answering, a foreign origin denied
// rather than passed through — is copied from there on purpose, for the reason
// recorded in `AnkiMediaPath.ets`: each native reviewer carries its own copy of
// the media policy because routing every Range request through the Flutter
// channel would put a round-trip in front of each one.
//
// Two things are *not* copies, and both were forced by the platform:
//
// 1. **Assets are preloaded, not read on demand.** ArkUI's
//    `onInterceptRequest` is synchronous, so a rawfile read inside it would have
//    to be `getRawFileContentSync` — and one of the eight assets is 2.27 MB of
//    MathJax. The promise form *does* settle on this device (§3.3 of ADR 0050),
//    so the bytes are fetched once in `preload` and the intercept path touches no
//    I/O at all. That is the whole reason the promise form was worth re-testing.
// 2. **Media is read synchronously with a positioned read.** `respond` cannot
//    await, so a Range slice is one `readSync` at an offset rather than a whole
//    file followed by a slice.

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  ORIGIN_HOST,
  RequestTarget,
  classifyDecodedName,
  classifyEncodedPath,
  isSafeAssetName,
  originAllowed,
} from './AnkiMediaPath';
import { HttpRange, encodingForMime, mimeForName, parseRange } from './AnkiHttp';

const SHELL_URL: string = 'https://anki.local/assets/reviewer.html';

/// Matches `OfficialAnkiCsp.VALUE` on Android and the `<meta http-equiv>` in
/// `assets/anki_reviewer/reviewer.html`. Sent as a header *and* carried by the
/// document: the header covers subresources the document did not author, and the
/// two must not be allowed to drift into a document that is stricter or looser
/// than the responses it pulls.
const CSP: string =
  "default-src 'none'; " +
  'img-src https://anki.local data: blob:; ' +
  'media-src https://anki.local data: blob:; ' +
  'font-src https://anki.local data:; ' +
  "style-src 'unsafe-inline' https://anki.local; " +
  "script-src 'unsafe-inline' https://anki.local; " +
  "connect-src 'none'; " +
  'frame-src https://anki.local; ' +
  "object-src 'none'; " +
  'base-uri https://anki.local/media/; ' +
  "form-action 'none';";

/// The eight files the shell and the card frame request. Mirrors
/// `REVIEWER_ASSETS` in `AnkiReviewerAssetProbe.ets` — which is where the byte
/// counts in ADR 0050 §3.3 were measured, so a file added in one place and not
/// the other would show up as a blank card rather than as a build error.
const ASSET_NAMES: Array<string> = [
  'reviewer.html',
  'reviewer.js',
  'reviewer.css',
  'card-frame.html',
  'card-frame.js',
  'mathjax-config.js',
  'manifest.json',
  'mathjax/tex-svg-full.js',
];

/// Everything except MathJax: ~16 KB in total, small enough that reading it
/// synchronously costs nothing, which is what lets the shell family be served
/// without ever racing the kernel's first request (see [preloadSync]).
const SYNC_ASSET_NAMES: Array<string> = [
  'reviewer.html',
  'reviewer.js',
  'reviewer.css',
  'card-frame.html',
  'card-frame.js',
  'mathjax-config.js',
  'manifest.json',
];

const RAWFILE_ROOT: string = 'flutter_assets/assets/anki_reviewer';

export function isShellUrl(url: string): boolean {
  return url === SHELL_URL || url.startsWith(SHELL_URL + '?');
}

/// Media bytes for a name that has already passed every path rule.
///
/// It exists because of a real gap in this platform's file API, not for
/// abstraction's sake: `fileIo.openSync` (since 12) returns a `File`, while
/// `fileIo.readSync` (since 11) still takes a `number` descriptor, and
/// `readFileSync` does not exist at all — so there is **no synchronous binary
/// read that accepts the handle `openSync` returns**. `respond` cannot await
/// (see `interceptFor`).
///
/// It is a **cache lookup and nothing else**, deliberately. The first shape
/// considered was a callback into Dart, which would read more naturally and is
/// impossible: `respond` runs inside a synchronous interception, and a
/// MethodChannel call is a promise, so there is no way for the page to have the
/// bytes before the response object has to be returned. Dart therefore pushes
/// the current card's media here *before* the `present` that will request it —
/// the same preload-then-serve-sync arrangement the eight assets already use.
///
/// Guessing that the runtime would accept a `File` where the type says `number`
/// is the kind of assumption that compiles nowhere and fails only on device.
export type MediaProvider = (name: string, start: number, length: number) => Uint8Array | undefined;

/// The ArkWeb response body accepts ArrayBuffer, not Uint8Array. Handing the
/// rawfile bytes over as a TypedArray compiles but delivers an empty body —
/// the shell then "loads" as a blank document with no scripts, which on device
/// looked exactly like a missing asset. The explicit copy keeps any byteOffset
/// or over-allocation of the underlying buffer out of the answer.
function bodyOf(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

export class AnkiOriginServer {
  private readonly assets: Map<string, Uint8Array> = new Map();
  private readonly mediaRoot: string;
  private readonly media: Map<string, Uint8Array> = new Map();
  private denialCount: number = 0;

  constructor(mediaRoot: string) {
    this.mediaRoot = mediaRoot;
  }

  /// Dart pushes the current card's media here before the present that will
  /// request it. Base64 because a MethodChannel carries strings, and because
  /// this SDK's standard codec has no byte-array mapping — the same reason
  /// AudioPlugin.stageBytes and the RDB BLOB bridge base64.
  public cacheMedia(name: string, base64: string): void {
    // `decodeSync` is an instance method on `Base64Helper`, not a static one —
    // asking for it off the class type is a compile error, and guessing wrong
    // here costs a build cycle for no information.
    this.media.set(name, new util.Base64Helper().decodeSync(base64));
  }

  /// Warms the small assets synchronously. Called before the `Web` exists, so
  /// the kernel's very first request — the shell itself, issued the instant the
  /// component attaches — is answered from a cache that cannot be cold. This is
  /// the fix for a real race, not a style choice: with only the promise
  /// preload, the shell request was observed beating the 8 ms rawfile read and
  /// being answered `asset_missing` 404, leaving a page whose `document.scripts`
  /// is empty and whose every `present` dies on "reading 'present' of
  /// undefined". MathJax deliberately stays on the promise path — 2.27 MB read
  /// synchronously would stall the UI thread — and is only needed once a card
  /// renders, long after [preload] has resolved.
  ///
  /// Throws on an unreadable asset rather than caching a hole: a missing shell
  /// asset is a build-order mistake and wants to fail loudly at open time.
  public preloadSync(context: common.UIAbilityContext): void {
    for (const name of SYNC_ASSET_NAMES) {
      const raw: string = RAWFILE_ROOT + '/' + name;
      try {
        this.assets.set(name, context.resourceManager.getRawFileContentSync(raw));
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        throw new Error('asset ' + name + ' unreadable-sync [' + String(err.code) + ']');
      }
    }
  }

  /// Warms the asset cache. Must be awaited before the `Web` is pointed at the
  /// shell, because a request that arrives before its asset is cached would have
  /// to be answered from somewhere — and "somewhere" here means either a sync
  /// read on the intercept path or a silent 404, and both are worse than a
  /// half-second wait at open time.
  ///
  /// A miss is reported rather than swallowed: a reviewer missing MathJax looks
  /// exactly like a reviewer correctly declining to render a card with no maths.
  public preload(context: common.UIAbilityContext): Promise<string> {
    const pending: Array<Promise<void>> = [];
    for (const name of ASSET_NAMES) {
      const raw: string = RAWFILE_ROOT + '/' + name;
      pending.push(
        context.resourceManager
          .getRawFileContent(raw)
          .then((bytes: Uint8Array) => {
            this.assets.set(name, bytes);
          })
          .catch((e: BusinessError) => {
            const err: BusinessError = e as BusinessError;
            throw new Error('asset ' + name + ' unreadable [' + String(err.code) + ']');
          }),
      );
    }
    return Promise.all(pending).then(() => {
      let total: number = 0;
      this.assets.forEach((bytes: Uint8Array) => {
        total += bytes.length;
      });
      return 'assets=' + String(this.assets.size) + ' bytes=' + String(total);
    });
  }

  /// Never returns null, unlike the SDK contract where null means "let the
  /// kernel load it". A foreign origin is denied rather than passed through:
  /// `anki.local` does not resolve, so passing it through turns a policy decision
  /// into a DNS failure the reader then has to decode.
  public respond(
    url: string,
    method: string,
    headers: Array<Header>,
  ): WebResourceResponse {
    const target: RequestTarget = classifyRequest(url);
    if (!target.allowed) {
      this.denialCount += 1;
      return denied(403, target.reason ?? 'denied');
    }
    if (target.assetName !== undefined) {
      return this.assetResponse(method, target.assetName);
    }
    const name: string = target.mediaName ?? '';
    return this.mediaResponse(method, name, findHeader(headers, 'range'));
  }

  public denials(): number {
    return this.denialCount;
  }

  private assetResponse(method: string, name: string): WebResourceResponse {
    const bytes: Uint8Array | undefined = this.assets.get(name);
    if (bytes === undefined) {
      // MathJax gets its own reason because that is the one whose absence has a
      // stable error code on the Dart side (`MATHJAX_ASSET_MISSING`); every other
      // missing asset is a build-order mistake and wants one undifferentiated
      // answer.
      const reason: string =
        name.indexOf('mathjax') >= 0 || name.endsWith('tex-svg-full.js')
          ? 'MATHJAX_ASSET_MISSING'
          : 'asset_missing';
      return denied(404, reason);
    }
    const mime: string = mimeForName(name);
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseMimeType(mime);
    response.setResponseEncoding(encodingForMime(mime));
    response.setResponseData(bodyOf(bytes));
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseHeader(assetHeaders(bytes.length, mime));
    return response;
  }

  private mediaResponse(method: string, name: string, rangeHeader: string): WebResourceResponse {
    const path: string | undefined = this.resolveMediaFile(name);
    if (path === undefined) {
      return denied(403, 'escape');
    }
    let length: number = 0;
    try {
      if (!fs.statSync(path).isFile()) {
        return denied(404, 'missing');
      }
      length = fs.statSync(path).size;
    } catch (e) {
      return denied(404, 'missing');
    }

    const mime: string = mimeForName(name);
    const range: HttpRange = parseRange(rangeHeader, length);
    if (!range.satisfiable) {
      const headers: Array<Header> = baseHeaders(0, mime);
      headers.push({ headerKey: 'Accept-Ranges', headerValue: 'bytes' });
      headers.push({ headerKey: 'Content-Range', headerValue: range.contentRange });
      const response: WebResourceResponse = new WebResourceResponse();
      response.setResponseMimeType('text/plain');
      response.setResponseEncoding('utf-8');
      response.setResponseData('');
      response.setResponseCode(416);
      response.setReasonMessage('Range Not Satisfiable');
      response.setResponseHeader(headers);
      return response;
    }

    const headers: Array<Header> = baseHeaders(range.contentLength, mime);
    headers.push({ headerKey: 'Accept-Ranges', headerValue: 'bytes' });
    if (range.status === 206) {
      headers.push({ headerKey: 'Content-Range', headerValue: range.contentRange });
    }
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseMimeType(mime);
    response.setResponseEncoding(encodingForMime(mime));
    if (method.toUpperCase() === 'HEAD' || range.contentLength === 0) {
      response.setResponseData('');
    } else {
      const cached: Uint8Array | undefined = this.media.get(name);
      if (cached === undefined) {
        // Distinct from `escape` and `missing`: the name passed every rule, and
        // the bytes are absent because Dart has not pushed them yet. Answering
        // 403 here would blame the card for a push that has not happened.
        return denied(503, 'MEDIA_NOT_PUSHED');
      }
      const slice: Uint8Array = cached.slice(range.start, range.start + range.contentLength);
      response.setResponseData(bodyOf(slice));
    }
    response.setResponseCode(range.status);
    response.setReasonMessage(range.status === 206 ? 'Partial Content' : 'OK');
    response.setResponseHeader(headers);
    return response;
  }

  /// `OfficialAnkiMediaStore.resolveMediaFile`, adapted to what `fileIo` can do
  /// synchronously.
  ///
  /// Android reaches for `canonicalFile` and compares resolved paths. ArkTS has
  /// no synchronous realpath (`fs.realpath` is a promise), and `respond` cannot
  /// await — so the symlink check is done with `lstatSync` instead, which is not
  /// a weaker check here but a stricter one: the classifier guarantees the name
  /// has no separators, so the only way out of the media folder is a symlink at
  /// `mediaRoot/<name>` itself, and refusing every symlink outright closes that
  /// without needing to compare resolved paths at all.
  private resolveMediaFile(rawName: string): string | undefined {
    const decision = classifyDecodedName(rawName);
    if (!decision.allowed || decision.filename === undefined) {
      return undefined;
    }
    const name: string = decision.filename;
    if (name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) {
      return undefined;
    }
    const candidate: string = this.mediaRoot + '/' + name;
    try {
      const link: fs.Stat = fs.lstatSync(candidate);
      if (link.isSymbolicLink()) {
        return undefined;
      }
      const stat: fs.Stat = fs.statSync(candidate);
      if (!stat.isFile()) {
        return undefined;
      }
    } catch (e) {
      return undefined;
    }
    return candidate;
  }
}

function classifyRequest(url: string): RequestTarget {
  const schemeSep: number = url.indexOf('://');
  if (schemeSep < 0) {
    return new RequestTarget(false, undefined, undefined, 'scheme');
  }
  const scheme: string = url.substring(0, schemeSep);
  const afterHost: number = url.indexOf('/', schemeSep + 3);
  const authority: string =
    afterHost < 0 ? url.substring(schemeSep + 3) : url.substring(schemeSep + 3, afterHost);
  const host: string = authority.split(':')[0];
  if (!originAllowed(scheme, host, undefined)) {
    return new RequestTarget(false, undefined, undefined, 'host');
  }
  let path: string =
    afterHost < 0 ? '/' : url.substring(afterHost);
  const hash: number = path.indexOf('#');
  if (hash >= 0) {
    path = path.substring(0, hash);
  }
  const query: number = path.indexOf('?');
  if (query >= 0) {
    path = path.substring(0, query);
  }
  return classifyEncodedPath(path);
}

function baseHeaders(contentLength: number, mime: string): Array<Header> {
  const headers: Array<Header> = [];
  headers.push({ headerKey: 'Content-Length', headerValue: String(contentLength) });
  headers.push({ headerKey: 'Cache-Control', headerValue: 'private, max-age=0' });
  if (mime === 'application/octet-stream') {
    headers.push({ headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' });
  }
  return headers;
}

function assetHeaders(contentLength: number, mime: string): Array<Header> {
  const headers: Array<Header> = baseHeaders(contentLength, mime);
  headers.push({ headerKey: 'Cache-Control', headerValue: 'no-store' });
  headers.push({ headerKey: 'Content-Security-Policy', headerValue: CSP });
  return headers;
}

function denied(code: number, reason: string): WebResourceResponse {
  const response: WebResourceResponse = new WebResourceResponse();
  response.setResponseMimeType('text/plain');
  response.setResponseEncoding('utf-8');
  response.setResponseData('');
  response.setResponseCode(code);
  response.setReasonMessage(reason);
  const headers: Array<Header> = [];
  headers.push({ headerKey: 'Content-Length', headerValue: '0' });
  headers.push({ headerKey: 'Cache-Control', headerValue: 'no-store' });
  headers.push({ headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' });
  response.setResponseHeader(headers);
  return response;
}

function findHeader(headers: Array<Header>, name: string): string {
  const wanted: string = name.toLowerCase();
  for (const header of headers) {
    if (header.headerKey.toLowerCase() === wanted) {
      return header.headerValue;
    }
  }
  return '';
}

/// Exported so the gate can assert the reviewer's own rules without duplicating
/// them: the Dart resolver asks the same question with the same vectors.
export { isSafeAssetName };