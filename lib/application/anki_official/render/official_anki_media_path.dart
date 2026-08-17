import 'dart:convert';

/// Single-decode media filename policy shared with Kotlin OfficialAnkiMediaPath.
class OfficialAnkiMediaPath {
  OfficialAnkiMediaPath._();

  static const originHost = 'anki.local';
  static const assetPrefix = '/assets/';
  static const mediaPrefix = '/media/';

  static String? decodeOnce(String encoded) {
    final bytes = <int>[];
    for (var i = 0; i < encoded.length; i++) {
      final unit = encoded.codeUnitAt(i);
      if (unit == 0) {
        return null;
      }
      if (encoded[i] != '%') {
        bytes.add(unit);
        continue;
      }
      if (i + 2 >= encoded.length) {
        return null;
      }
      final hex = encoded.substring(i + 1, i + 3);
      if (!_isHexByte(hex)) {
        return null;
      }
      bytes.add(int.parse(hex, radix: 16));
      i += 2;
    }
    if (bytes.contains(0)) {
      return null;
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: false);
    }
  }

  static bool _isHexByte(String hex) {
    if (hex.length != 2) return false;
    return RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(hex);
  }

  static OfficialAnkiMediaNameDecision classifyDecodedName(String decoded) {
    if (decoded.isEmpty || decoded.contains('\u0000')) {
      return OfficialAnkiMediaNameDecision.denied('empty_or_nul');
    }
    if (decoded.contains('/') || decoded.contains('\\')) {
      return OfficialAnkiMediaNameDecision.denied('separator');
    }
    if (decoded == '.' || decoded == '..') {
      return OfficialAnkiMediaNameDecision.denied('dotdot');
    }
    if (decoded.startsWith('/') || _looksAbsolute(decoded)) {
      return OfficialAnkiMediaNameDecision.denied('absolute');
    }
    if (_hasResidualEncodedTraversal(decoded)) {
      return OfficialAnkiMediaNameDecision.denied('double_encoding');
    }
    return OfficialAnkiMediaNameDecision.allowed(decoded);
  }

  static OfficialAnkiMediaNameDecision classifyEncodedName(String encodedName) {
    if (encodedName.contains('/') || encodedName.contains('\\')) {
      return OfficialAnkiMediaNameDecision.denied('separator');
    }
    final decoded = decodeOnce(encodedName);
    if (decoded == null) {
      return OfficialAnkiMediaNameDecision.denied('malformed_percent');
    }
    return classifyDecodedName(decoded);
  }

  static OfficialAnkiRequestTarget classifyEncodedPath(String encodedPath) {
    if (encodedPath.startsWith(assetPrefix)) {
      final name = encodedPath.substring(assetPrefix.length);
      if (!_isSafeAssetName(name)) {
        return OfficialAnkiRequestTarget.denied('asset_name');
      }
      return OfficialAnkiRequestTarget.asset(name);
    }
    if (!encodedPath.startsWith(mediaPrefix)) {
      return OfficialAnkiRequestTarget.denied('prefix');
    }
    final encodedName = encodedPath.substring(mediaPrefix.length);
    final decision = classifyEncodedName(encodedName);
    if (!decision.allowed || decision.filename == null) {
      return OfficialAnkiRequestTarget.denied(decision.reason ?? 'media_name');
    }
    return OfficialAnkiRequestTarget.media(decision.filename!);
  }

  static String encodedPathFromUri(Uri uri) {
    final raw = uri.toString();
    final schemeSep = raw.indexOf('://');
    if (schemeSep < 0) {
      return uri.path;
    }
    final afterHost = raw.indexOf('/', schemeSep + 3);
    if (afterHost < 0) {
      return uri.path;
    }
    var path = raw.substring(afterHost);
    final hash = path.indexOf('#');
    if (hash >= 0) path = path.substring(0, hash);
    final query = path.indexOf('?');
    if (query >= 0) path = path.substring(0, query);
    return path;
  }

  static bool originAllowed({
    required String scheme,
    required String host,
    int? port,
  }) {
    if (scheme != 'https') return false;
    if (host != originHost) return false;
    if (port != null && port != 443 && port != 0) return false;
    return true;
  }

  static bool _isSafeAssetName(String name) {
    if (name.isEmpty || name.startsWith('/')) return false;
    if (name.split('/').contains('..')) return false;
    return RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(name) && !name.contains('//');
  }

  static bool isAllowedAsset(String name) => _isSafeAssetName(name);

  static bool _hasResidualEncodedTraversal(String decoded) {
    final lower = decoded.toLowerCase();
    return lower.contains('%2f') ||
        lower.contains('%5c') ||
        lower.contains('%00') ||
        lower.contains('%2e%2e');
  }

  static bool _looksAbsolute(String name) {
    if (name.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:').hasMatch(name);
  }

  static bool isDeniedScheme(String uri) {
    final lower = uri.toLowerCase();
    return lower.startsWith('file:') ||
        lower.startsWith('content:') ||
        lower.startsWith('http:') ||
        lower.startsWith('intent:') ||
        lower.startsWith('javascript:') ||
        lower.startsWith('ws:') ||
        lower.startsWith('wss:');
  }
}

class OfficialAnkiMediaNameDecision {
  const OfficialAnkiMediaNameDecision._({
    required this.allowed,
    this.filename,
    this.reason,
  });

  factory OfficialAnkiMediaNameDecision.denied(String reason) =>
      OfficialAnkiMediaNameDecision._(allowed: false, reason: reason);

  factory OfficialAnkiMediaNameDecision.allowed(String filename) =>
      OfficialAnkiMediaNameDecision._(allowed: true, filename: filename);

  final bool allowed;
  final String? filename;
  final String? reason;
}

class OfficialAnkiRequestTarget {
  const OfficialAnkiRequestTarget._({
    required this.allowed,
    this.assetName,
    this.mediaName,
    this.reason,
  });

  factory OfficialAnkiRequestTarget.denied(String reason) =>
      OfficialAnkiRequestTarget._(allowed: false, reason: reason);

  factory OfficialAnkiRequestTarget.asset(String name) =>
      OfficialAnkiRequestTarget._(allowed: true, assetName: name);

  factory OfficialAnkiRequestTarget.media(String name) =>
      OfficialAnkiRequestTarget._(allowed: true, mediaName: name);

  final bool allowed;
  final String? assetName;
  final String? mediaName;
  final String? reason;
}
