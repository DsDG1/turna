// Copyright (c) 2024 Turna. All rights reserved.
//
// ArkTS mirror of `OfficialAnkiHttpRange.kt` and `OfficialAnkiMime.kt`
// (Android). The reviewer advertises `Accept-Ranges: bytes`, so the kernel is
// entitled to ask for a slice and entitled to be told 416 when the slice is
// nonsense — a server that answers 200 to every Range is not a lenient server,
// it is one the kernel cannot seek in.

export class HttpRange {
  readonly satisfiable: boolean;
  readonly start: number;
  readonly end: number;
  readonly length: number;
  readonly status: number;

  constructor(
    satisfiable: boolean,
    start: number,
    end: number,
    length: number,
    status: number,
  ) {
    this.satisfiable = satisfiable;
    this.start = start;
    this.end = end;
    this.length = length;
    this.status = status;
  }

  get contentLength(): number {
    return this.satisfiable && this.end >= this.start ? this.end - this.start + 1 : 0;
  }

  get contentRange(): string {
    return this.satisfiable
      ? 'bytes ' + String(this.start) + '-' + String(this.end) + '/' + String(this.length)
      : 'bytes */' + String(this.length);
  }
}

function unsatisfiable(length: number): HttpRange {
  return new HttpRange(false, 0, -1, length, 416);
}

function full(length: number): HttpRange {
  return new HttpRange(true, 0, length <= 0 ? -1 : length - 1, length, 200);
}

function parseLongOrUndefined(text: string): number | undefined {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  for (let i: number = 0; i < trimmed.length; i++) {
    const ch: string = trimmed.charAt(i);
    if (ch < '0' || ch > '9') {
      return undefined;
    }
  }
  return parseInt(trimmed, 10);
}

/// Single-range `bytes=a-b` only. A multi-range request would need a
/// `multipart/byteranges` body, and no browser issues one for `<audio>` — so the
/// comma case answers 416 rather than pretending to serve the first range, which
/// would look like success and then truncate the media.
export function parseRange(raw: string, length: number): HttpRange {
  if (raw.trim().length === 0) {
    return full(length);
  }
  const trimmed: string = raw.trim();
  const lower: string = trimmed.toLowerCase();
  if (!lower.startsWith('bytes=')) {
    return unsatisfiable(length);
  }
  const spec: string = trimmed.substring(6).trim();
  if (spec.length === 0 || spec.indexOf(',') >= 0) {
    return unsatisfiable(length);
  }
  const dash: number = spec.indexOf('-');
  if (dash < 0) {
    return unsatisfiable(length);
  }
  const left: string = spec.substring(0, dash).trim();
  const right: string = spec.substring(dash + 1).trim();
  if (length <= 0) {
    return unsatisfiable(length);
  }
  if (left.length === 0 && right.length === 0) {
    return unsatisfiable(length);
  }
  if (left.length === 0) {
    const suffix: number | undefined = parseLongOrUndefined(right);
    if (suffix === undefined || suffix <= 0) {
      return unsatisfiable(length);
    }
    const start: number = length > suffix ? length - suffix : 0;
    return new HttpRange(true, start, length - 1, length, 206);
  }
  const start: number | undefined = parseLongOrUndefined(left);
  if (start === undefined || start < 0 || start >= length) {
    return unsatisfiable(length);
  }
  if (right.length === 0) {
    return new HttpRange(true, start, length - 1, length, 206);
  }
  const end: number | undefined = parseLongOrUndefined(right);
  if (end === undefined || end < start) {
    return unsatisfiable(length);
  }
  return new HttpRange(true, start, end >= length ? length - 1 : end, length, 206);
}

export function mimeForName(name: string): string {
  const lower: string = name.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  if (lower.endsWith('.mp3')) {
    return 'audio/mpeg';
  }
  if (lower.endsWith('.ogg')) {
    return 'audio/ogg';
  }
  if (lower.endsWith('.wav')) {
    return 'audio/wav';
  }
  if (lower.endsWith('.m4a')) {
    return 'audio/mp4';
  }
  if (lower.endsWith('.mp4')) {
    return 'video/mp4';
  }
  if (lower.endsWith('.webm')) {
    return 'video/webm';
  }
  if (lower.endsWith('.css')) {
    return 'text/css';
  }
  if (lower.endsWith('.js')) {
    return 'text/javascript';
  }
  if (lower.endsWith('.html')) {
    return 'text/html';
  }
  if (lower.endsWith('.json')) {
    return 'application/json';
  }
  if (lower.endsWith('.woff')) {
    return 'font/woff';
  }
  if (lower.endsWith('.woff2')) {
    return 'font/woff2';
  }
  if (lower.endsWith('.ttf')) {
    return 'font/ttf';
  }
  if (lower.endsWith('.otf')) {
    return 'font/otf';
  }
  return 'application/octet-stream';
}

/// `''` rather than a nullable, because `WebResourceResponse` wants the empty
/// string for "no charset" and a `null` here would be a compile error at every
/// call site instead of one decision made here.
export function encodingForMime(mime: string): string {
  const base: string = mime.split(';')[0].trim().toLowerCase();
  if (base.startsWith('text/') || base === 'application/json') {
    return 'utf-8';
  }
  return '';
}