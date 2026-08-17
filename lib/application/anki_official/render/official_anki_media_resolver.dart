import 'dart:io';

import 'package:turna/application/anki_official/render/official_anki_media_path.dart';
import 'package:turna/application/anki_official/render/official_anki_mime.dart';

/// Canonical media path rules shared by Flutter AV playback and the Android
/// WebView interceptor. Unicode names are matched as stored on disk; this
/// resolver never NFC/NFD-renames files.
class OfficialAnkiMediaResolver {
  OfficialAnkiMediaResolver(this.mediaRoot);

  static const originHost = OfficialAnkiMediaPath.originHost;
  static const assetPrefix = OfficialAnkiMediaPath.assetPrefix;
  static const mediaPrefix = OfficialAnkiMediaPath.mediaPrefix;

  final Directory mediaRoot;

  OfficialAnkiMediaDecision resolveUri(Uri uri) {
    if (!OfficialAnkiMediaPath.originAllowed(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    )) {
      if (uri.scheme != 'https') {
        return OfficialAnkiMediaDecision.denied('scheme');
      }
      if (uri.host != originHost) {
        return OfficialAnkiMediaDecision.denied('host');
      }
      return OfficialAnkiMediaDecision.denied('port');
    }
    return resolveEncodedPath(OfficialAnkiMediaPath.encodedPathFromUri(uri));
  }

  OfficialAnkiMediaDecision resolveEncodedPath(String encodedPath) {
    final target = OfficialAnkiMediaPath.classifyEncodedPath(encodedPath);
    if (!target.allowed) {
      return OfficialAnkiMediaDecision.denied(target.reason ?? 'denied');
    }
    if (target.assetName != null) {
      return OfficialAnkiMediaDecision.asset(target.assetName!);
    }
    return resolveRelativeName(target.mediaName!);
  }

  OfficialAnkiMediaDecision resolveRelativeName(String rawName) {
    final decision = OfficialAnkiMediaPath.classifyDecodedName(rawName);
    if (!decision.allowed || decision.filename == null) {
      return OfficialAnkiMediaDecision.denied(decision.reason ?? 'name');
    }
    final name = decision.filename!;
    final root = mediaRoot.resolveSymbolicLinksSync();
    final candidate = File('${mediaRoot.path}${Platform.pathSeparator}$name');
    if (!candidate.existsSync()) {
      return OfficialAnkiMediaDecision.denied('missing');
    }
    final resolved = candidate.resolveSymbolicLinksSync();
    final rootPrefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (resolved != root && !resolved.startsWith(rootPrefix)) {
      return OfficialAnkiMediaDecision.denied('escape');
    }
    final type = FileSystemEntity.typeSync(resolved, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return OfficialAnkiMediaDecision.denied('directory');
    }
    if (type == FileSystemEntityType.link) {
      return OfficialAnkiMediaDecision.denied('symlink');
    }
    return OfficialAnkiMediaDecision.file(
      File(resolved),
      mimeType: OfficialAnkiMime.mimeForName(name),
    );
  }

  static bool isAllowedAsset(String name) =>
      OfficialAnkiMediaPath.isAllowedAsset(name);

  static String mimeForName(String name) => OfficialAnkiMime.mimeForName(name);

  static String? encodingForMime(String mime) =>
      OfficialAnkiMime.encodingForMime(mime);

  static bool isDeniedScheme(String uri) =>
      OfficialAnkiMediaPath.isDeniedScheme(uri);
}

class OfficialAnkiMediaDecision {
  const OfficialAnkiMediaDecision._({
    required this.allowed,
    this.file,
    this.assetName,
    this.mimeType,
    this.reason,
  });

  factory OfficialAnkiMediaDecision.denied(String reason) =>
      OfficialAnkiMediaDecision._(allowed: false, reason: reason);

  factory OfficialAnkiMediaDecision.file(File file, {required String mimeType}) =>
      OfficialAnkiMediaDecision._(
        allowed: true,
        file: file,
        mimeType: mimeType,
      );

  factory OfficialAnkiMediaDecision.asset(String name) =>
      OfficialAnkiMediaDecision._(
        allowed: true,
        assetName: name,
        mimeType: OfficialAnkiMime.mimeForName(name),
      );

  final bool allowed;
  final File? file;
  final String? assetName;
  final String? mimeType;
  final String? reason;
}
