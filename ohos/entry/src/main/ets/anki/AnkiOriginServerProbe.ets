// Copyright (c) 2024 Turna. All rights reserved.
//
// The synthetic origin for the step 5b probe: what an `onInterceptRequest`
// handler has to be able to do before a reviewer is worth writing.
//
// It records every request it answers. That record is the whole point — the
// page in `AnkiReviewerProbePage` reports what it believes happened, and a
// probe whose only witness is the page would happily report success on a blank
// page that never loaded anything. Cross-checking the page's claim against a
// request that must-not-have-happened turns three optimistic assertions into
// four falsifiable ones.
//
// Renamed from `AnkiOriginServer.ets` when the production origin took that
// name. The probe is still the fallback evidence for premise 3, so it is kept
// rather than deleted; only the file name changed.

import {
  ANKI_ORIGIN,
  RangeSpec,
  encodingForMime,
  mimeForName,
  parseRange,
  probeCss,
  probeFrameHtml,
  probeJs,
  probeShellHtml,
  probeWav,
} from './AnkiProbeAssets';

const SHELL_PATH: string = '/assets/shell.html';
const FRAME_PATH: string = '/assets/frame.html';
const CSS_PATH: string = '/assets/probe.css';
const JS_PATH: string = '/assets/probe.js';
const WAV_PATH: string = '/media/probe.wav';

/// The URL the page's CSP probe is supposed to be unable to fetch
/// (`connect-src 'none'`). If this path ever appears in the transcript the
/// policy was not enforced, whatever the page claimed about itself.
export const MUST_NOT_FETCH_PATH: string = '/assets/must-not-be-fetched.css';

export class AnkiOriginServerProbe {
  private readonly wav: ArrayBuffer = probeWav();
  private readonly lines: Array<string> = [];
  private readonly ranged: Array<string> = [];
  private denialCount: number = 0;

  /// Never returns null, unlike the SDK's `onInterceptRequest` contract where
  /// null means "let the kernel load it". A foreign origin is denied rather
  /// than passed through: `anki.local` does not resolve, so passing it through
  /// turns a policy decision into a DNS failure the reader has to decode.
  public respond(url: string, method: string, headers: Array<Header>): WebResourceResponse {
    if (!url.startsWith(ANKI_ORIGIN)) {
      this.denialCount += 1;
      this.note('DENY', url, 'foreign-origin');
      return this.denied(403, 'foreign_origin');
    }
    const path: string = url.substring(ANKI_ORIGIN.length).split('?')[0];
    const range: string = findHeader(headers, 'range');
    if (range.length > 0) {
      // Record the header verbatim. "A Range request happened" and "a Range
      // request for the right bytes arrived" are different claims, and the
      // second is the one the media path depends on.
      this.ranged.push(method + ' ' + path + ' Range:' + range);
    }
    if (path === SHELL_PATH) {
      return this.text(method, path, 'text/html', probeShellHtml(), range);
    }
    if (path === FRAME_PATH) {
      return this.text(method, path, 'text/html', probeFrameHtml(), range);
    }
    if (path === CSS_PATH) {
      return this.text(method, path, 'text/css', probeCss(), range);
    }
    if (path === JS_PATH) {
      return this.text(method, path, 'application/javascript', probeJs(), range);
    }
    if (path === WAV_PATH) {
      return this.audio(method, path, range);
    }
    this.note(method, path, '404');
    return this.denied(404, 'not_found');
  }

  /// One line per answered request, plus the two counters that decide the
  /// verdict: whether anything ever asked for a byte range, and whether the
  /// CSP-blocked fetch got through.
  public transcript(): string {
    const mustNotFetched: boolean = this.sawPath(MUST_NOT_FETCH_PATH);
    let out: string = 'requests=[' + this.lines.join(' | ') + ']';
    out += ' rangeRequests=[' + this.ranged.join(' | ') + ']';
    out += ' ranged=' + String(this.ranged.length > 0);
    out += ' mustNotFetched=' + String(mustNotFetched);
    out += ' denials=' + String(this.denialCount);
    return out;
  }

  public servedShell(): boolean {
    return this.sawPath(SHELL_PATH);
  }

  public servedWav(): boolean {
    return this.sawPath(WAV_PATH);
  }

  public cspFetchBlocked(): boolean {
    return !this.sawPath(MUST_NOT_FETCH_PATH);
  }

  public mediaRangeVerified(): boolean {
    const requested: boolean = this.ranged.some((line: string): boolean =>
      line.startsWith('GET ' + WAV_PATH + ' Range:bytes='),
    );
    const served: boolean = this.lines.some((line: string): boolean =>
      line === 'GET ' + WAV_PATH + '->206',
    );
    return requested && served;
  }

  private sawPath(path: string): boolean {
    for (const line of this.lines) {
      if (line.indexOf(' ' + path + ' ') >= 0 || line.indexOf(' ' + path + '->') >= 0) {
        return true;
      }
    }
    return false;
  }

  private note(method: string, path: string, status: string): void {
    this.lines.push(method + ' ' + path + '->' + status);
  }

  private text(
    method: string,
    path: string,
    mime: string,
    body: string,
    range: string,
  ): WebResourceResponse {
    this.note(method, path, '200');
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseMimeType(mime);
    response.setResponseEncoding(encodingForMime(mime));
    response.setResponseData(body);
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseHeader(baseHeaders(body.length));
    return response;
  }

  private audio(method: string, path: string, rangeHeader: string): WebResourceResponse {
    const total: number = this.wav.byteLength;
    const spec: RangeSpec = parseRange(rangeHeader, total);
    if (!spec.satisfiable) {
      this.note(method, path, '416');
      const unsatisfiable: WebResourceResponse = new WebResourceResponse();
      unsatisfiable.setResponseMimeType('text/plain');
      unsatisfiable.setResponseEncoding('utf-8');
      unsatisfiable.setResponseData('');
      unsatisfiable.setResponseCode(416);
      unsatisfiable.setReasonMessage('Range Not Satisfiable');
      const headers: Array<Header> = baseHeaders(0);
      headers.push({ headerKey: 'Content-Range', headerValue: spec.contentRange });
      unsatisfiable.setResponseHeader(headers);
      return unsatisfiable;
    }
    const headers: Array<Header> = baseHeaders(spec.contentLength);
    headers.push({ headerKey: 'Accept-Ranges', headerValue: 'bytes' });
    if (spec.status === 206) {
      headers.push({ headerKey: 'Content-Range', headerValue: spec.contentRange });
    }
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseMimeType(mimeForName('probe.wav'));
    response.setResponseEncoding('utf-8');
    if (method.toUpperCase() === 'HEAD') {
      response.setResponseData('');
    } else {
      response.setResponseData(this.wav.slice(spec.start, spec.start + spec.contentLength));
    }
    response.setResponseCode(spec.status);
    response.setReasonMessage(spec.status === 206 ? 'Partial Content' : 'OK');
    response.setResponseHeader(headers);
    this.note(method, path, String(spec.status));
    return response;
  }

  private denied(code: number, reason: string): WebResourceResponse {
    const response: WebResourceResponse = new WebResourceResponse();
    response.setResponseMimeType('text/plain');
    response.setResponseEncoding('utf-8');
    response.setResponseData('');
    response.setResponseCode(code);
    response.setReasonMessage(reason);
    response.setResponseHeader(baseHeaders(0));
    return response;
  }
}

function baseHeaders(contentLength: number): Array<Header> {
  const headers: Array<Header> = [];
  headers.push({ headerKey: 'Content-Length', headerValue: String(contentLength) });
  headers.push({ headerKey: 'Cache-Control', headerValue: 'no-store' });
  headers.push({ headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' });
  return headers;
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