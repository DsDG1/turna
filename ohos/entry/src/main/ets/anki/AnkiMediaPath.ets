// Copyright (c) 2024 Turna. All rights reserved.
//
// ArkTS mirror of `lib/application/anki_official/render/official_anki_media_path.dart`.
//
// This file is a security boundary and it is the *second* implementation of one:
// `OfficialAnkiMediaPath.kt` (Android) and `OfficialAnkiSchemeHandler.swift` (iOS)
// already re-derive these rules natively, and the repo's established answer is
// that each native reviewer carries its own copy rather than calling back into
// Dart per request (which would put a channel round-trip in front of every Range
// request). The consequence is a real obligation, stated here so it is not lost:
// **Dart is the normative source** and this file must not drift from it. The
// vectors in the Dart media-path tests are the Dart side of that obligation;
// they are checked against this file on device.
//
// Mirroring Dart rather than Kotlin is deliberate, because the divergence between
// the two already exists and should not be copied silently: for a raw (unescaped)
// non-ASCII character Dart keeps the full UTF-16 code unit where Kotlin masks it
// down to one byte (`ch.code and 0xff`) before decoding. Dart's behaviour is the
// one reproduced here. It is unreachable for percent-encoded names, which is how
// every real request arrives.

export const ORIGIN_HOST: string = 'anki.local';
export const ASSET_PREFIX: string = '/assets/';
export const MEDIA_PREFIX: string = '/media/';

const NUL: string = String.fromCharCode(0);

export class NameDecision {
  readonly allowed: boolean;
  readonly filename: string | undefined;
  readonly reason: string | undefined;

  constructor(allowed: boolean, filename?: string, reason?: string) {
    this.allowed = allowed;
    this.filename = filename;
    this.reason = reason;
  }
}

export class RequestTarget {
  readonly allowed: boolean;
  readonly assetName: string | undefined;
  readonly mediaName: string | undefined;
  readonly reason: string | undefined;

  constructor(
    allowed: boolean,
    assetName?: string,
    mediaName?: string,
    reason?: string,
  ) {
    this.allowed = allowed;
    this.assetName = assetName;
    this.mediaName = mediaName;
    this.reason = reason;
  }
}

function isHexDigit(ch: string): boolean {
  return (
    (ch >= '0' && ch <= '9') ||
    (ch >= 'a' && ch <= 'f') ||
    (ch >= 'A' && ch <= 'F')
  );
}

/// Percent-decodes exactly once. A second decoding pass is the traversal vector
/// this whole file exists to close, so `%252f` must stay `%2f` here and then be
/// rejected by `classifyDecodedName` as residual encoding, rather than becoming
/// a separator.
export function decodeOnce(encoded: string): string | undefined {
  const units: Array<number> = [];
  let i: number = 0;
  while (i < encoded.length) {
    const unit: number = encoded.charCodeAt(i);
    if (unit === 0) {
      return undefined;
    }
    if (encoded.charAt(i) !== '%') {
      units.push(unit);
      i += 1;
      continue;
    }
    if (i + 2 >= encoded.length) {
      return undefined;
    }
    const hex: string = encoded.substring(i + 1, i + 3);
    if (!isHexDigit(hex.charAt(0)) || !isHexDigit(hex.charAt(1))) {
      return undefined;
    }
    units.push(parseInt(hex, 16));
    i += 3;
  }
  for (const unit of units) {
    if (unit === 0) {
      return undefined;
    }
  }
  let decoded: string = '';
  for (const unit of units) {
    decoded += String.fromCharCode(unit);
  }
  return decoded;
}

export function classifyDecodedName(decoded: string): NameDecision {
  if (decoded.length === 0 || decoded.indexOf(NUL) >= 0) {
    return new NameDecision(false, undefined, 'empty_or_nul');
  }
  if (decoded.indexOf('/') >= 0 || decoded.indexOf('\\') >= 0) {
    return new NameDecision(false, undefined, 'separator');
  }
  if (decoded === '.' || decoded === '..') {
    return new NameDecision(false, undefined, 'dotdot');
  }
  if (decoded.startsWith('/') || looksAbsolute(decoded)) {
    return new NameDecision(false, undefined, 'absolute');
  }
  if (hasResidualEncodedTraversal(decoded)) {
    return new NameDecision(false, undefined, 'double_encoding');
  }
  return new NameDecision(true, decoded);
}

export function classifyEncodedName(encodedName: string): NameDecision {
  // The separator test runs on the *encoded* name before decoding, so a `%2f`
  // that decodes to a separator is caught by the residual-encoding rule rather
  // than by this one. Order matters and matches Dart exactly.
  if (encodedName.indexOf('/') >= 0 || encodedName.indexOf('\\') >= 0) {
    return new NameDecision(false, undefined, 'separator');
  }
  const decoded: string | undefined = decodeOnce(encodedName);
  if (decoded === undefined) {
    return new NameDecision(false, undefined, 'malformed_percent');
  }
  return classifyDecodedName(decoded);
}

export function classifyEncodedPath(encodedPath: string): RequestTarget {
  if (encodedPath.startsWith(ASSET_PREFIX)) {
    const name: string = encodedPath.substring(ASSET_PREFIX.length);
    if (!isSafeAssetName(name)) {
      return new RequestTarget(false, undefined, undefined, 'asset_name');
    }
    return new RequestTarget(true, name);
  }
  if (!encodedPath.startsWith(MEDIA_PREFIX)) {
    return new RequestTarget(false, undefined, undefined, 'prefix');
  }
  const decision: NameDecision = classifyEncodedName(
    encodedPath.substring(MEDIA_PREFIX.length),
  );
  if (!decision.allowed || decision.filename === undefined) {
    return new RequestTarget(
      false,
      undefined,
      undefined,
      decision.reason ?? 'media_name',
    );
  }
  return new RequestTarget(false, undefined, decision.filename);
}

export function isSafeAssetName(name: string): boolean {
  if (name.length === 0 || name.startsWith('/')) {
    return false;
  }
  if (name.split('/').indexOf('..') >= 0) {
    return false;
  }
  return isAssetCharset(name) && name.indexOf('//') < 0;
}

/// `^[A-Za-z0-9._/-]+$` spelled out rather than handed to `RegExp`: ArkTS
/// restricts what a regular expression may contain, and an unanchored pattern
/// would be the wrong defence here anyway.
function isAssetCharset(name: string): boolean {
  for (let i: number = 0; i < name.length; i++) {
    const ch: string = name.charAt(i);
    const alnum: boolean =
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= 'a' && ch <= 'z') ||
      (ch >= '0' && ch <= '9');
    if (!alnum && ch !== '.' && ch !== '_' && ch !== '/' && ch !== '-') {
      return false;
    }
  }
  return true;
}

function hasResidualEncodedTraversal(decoded: string): boolean {
  const lower: string = decoded.toLowerCase();
  return (
    lower.indexOf('%2f') >= 0 ||
    lower.indexOf('%5c') >= 0 ||
    lower.indexOf('%00') >= 0 ||
    lower.indexOf('%2e%2e') >= 0
  );
}

function looksAbsolute(name: string): boolean {
  if (name.startsWith('/')) {
    return true;
  }
  if (name.length < 2) {
    return false;
  }
  const first: string = name.charAt(0);
  const isLetter: boolean =
    (first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z');
  return isLetter && name.charAt(1) === ':';
}

export function originAllowed(
  scheme: string | undefined,
  host: string | undefined,
  port: number | undefined,
): boolean {
  if (scheme !== 'https') {
    return false;
  }
  if (host !== ORIGIN_HOST) {
    return false;
  }
  // Dart also admits 0 next to 443 because `Uri` reports 0 for "no port", while
  // ArkUI's interceptor surfaces -1; both spellings mean "default port", and
  // accepting both is what lets the same rule survive the trip between them.
  if (port !== undefined && port !== -1 && port !== 443 && port !== 0) {
    return false;
  }
  return true;
}
