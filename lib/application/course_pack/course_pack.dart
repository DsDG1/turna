import 'dart:convert';

import 'package:turna/application/course_pack/course_pack_media.dart';

/// Parsed `.turnapack` document. Values in [files] are JSON strings.
///
/// v1 is a single JSON file (no media). v2 is typically a zip whose
/// `pack.json` uses this same object plus a `media/` tree.
class CoursePack {
  const CoursePack({
    required this.format,
    required this.packVersion,
    required this.language,
    required this.license,
    required this.files,
  });

  final String format;
  final int packVersion;
  final CoursePackLanguage language;
  final CoursePackLicense license;
  final Map<String, String> files;

  static const String formatV1 = 'turnapack/1';
  static const String formatV2 = 'turnapack/2';
  static const Set<String> supportedFormats = {formatV1, formatV2};
  static const int maxBytes = 20 * 1024 * 1024;
  static final RegExp codePattern = RegExp(r'^[a-z]{2,3}$');

  static const _mediaKeys = {'audioAsset', 'imageAsset'};
  static const _mediaListKeys = {'audioAssets', 'imageAssets'};

  factory CoursePack.parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const CoursePackFormatException('Pack root must be a JSON object');
    }
    return CoursePack.fromJson(decoded);
  }

  factory CoursePack.fromJson(Map<String, dynamic> json) {
    final format = '${json['format'] ?? ''}';
    if (!supportedFormats.contains(format)) {
      throw CoursePackFormatException('不受支持的包版本: $format');
    }
    final languageRaw = json['language'];
    if (languageRaw is! Map) {
      throw const CoursePackFormatException('Pack language descriptor is required');
    }
    final licenseRaw = json['license'];
    if (licenseRaw is! Map) {
      throw const CoursePackFormatException('Pack license is required');
    }
    final filesRaw = json['files'];
    if (filesRaw is! Map) {
      throw const CoursePackFormatException('Pack files map is required');
    }
    final files = <String, String>{};
    filesRaw.forEach((key, value) {
      final rel = '$key';
      if (value is String) {
        files[rel] = value;
      } else {
        files[rel] = jsonEncode(value);
      }
    });
    return CoursePack(
      format: format,
      packVersion: json['packVersion'] is int
          ? json['packVersion'] as int
          : int.tryParse('${json['packVersion'] ?? 1}') ?? 1,
      language: CoursePackLanguage.fromJson(
        Map<String, dynamic>.from(languageRaw),
      ),
      license: CoursePackLicense.fromJson(
        Map<String, dynamic>.from(licenseRaw),
      ),
      files: files,
    );
  }

  Map<String, dynamic> toMetaJson() => {
        ...language.toJson(),
        'packVersion': packVersion,
        'license': license.toJson(),
      };

  /// `media/…` paths referenced by known media fields in pack JSON files.
  Set<String> mediaRelativeRefs() {
    final out = <String>{};
    for (final raw in files.values) {
      try {
        _collectMediaRefs(jsonDecode(raw), out);
      } catch (_) {
        // Non-JSON payloads cannot carry structured media refs.
      }
    }
    return out;
  }

  /// Rewrite `media/file.ext` refs to `turnapack://<code>/file.ext`.
  CoursePack withRewrittenMediaRefs() {
    final code = language.code;
    final next = <String, String>{};
    files.forEach((key, raw) {
      try {
        final decoded = jsonDecode(raw);
        _rewriteMediaNode(decoded, code);
        next[key] = jsonEncode(decoded);
      } catch (_) {
        next[key] = raw;
      }
    });
    return CoursePack(
      format: format,
      packVersion: packVersion,
      language: language,
      license: license,
      files: next,
    );
  }

  static void _collectMediaRefs(dynamic node, Set<String> out) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        if (_mediaKeys.contains(key) && value is String) {
          final n = value.replaceAll('\\', '/').trim();
          if (CoursePackMedia.isMediaRelative(n)) {
            out.add(n.substring('media/'.length));
          }
        } else if (_mediaListKeys.contains(key) && value is List) {
          for (final item in value) {
            if (item is! String) continue;
            final n = item.replaceAll('\\', '/').trim();
            if (CoursePackMedia.isMediaRelative(n)) {
              out.add(n.substring('media/'.length));
            }
          }
        } else {
          _collectMediaRefs(value, out);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _collectMediaRefs(item, out);
      }
    }
  }

  static void _rewriteMediaNode(dynamic node, String code) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final value = node[key];
        final keyName = '$key';
        if (_mediaKeys.contains(keyName) && value is String) {
          node[key] = CoursePackMedia.rewrite(value, code);
        } else if (_mediaListKeys.contains(keyName) && value is List) {
          node[key] = [
            for (final item in value)
              item is String ? CoursePackMedia.rewrite(item, code) : item,
          ];
        } else {
          _rewriteMediaNode(value, code);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _rewriteMediaNode(item, code);
      }
    }
  }
}

class CoursePackLanguage {
  const CoursePackLanguage({
    required this.code,
    required this.displayName,
    required this.ttsLocale,
    required this.nativeLabel,
    this.signatureChars,
  });

  final String code;
  final String displayName;
  final String ttsLocale;
  final String nativeLabel;
  final String? signatureChars;

  factory CoursePackLanguage.fromJson(Map<String, dynamic> json) {
    return CoursePackLanguage(
      code: '${json['code'] ?? ''}'.trim(),
      displayName: '${json['displayName'] ?? ''}'.trim(),
      ttsLocale: '${json['ttsLocale'] ?? ''}'.trim(),
      nativeLabel: '${json['nativeLabel'] ?? json['displayName'] ?? ''}'.trim(),
      signatureChars: json['signatureChars'] == null
          ? null
          : '${json['signatureChars']}',
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'displayName': displayName,
        'ttsLocale': ttsLocale,
        'nativeLabel': nativeLabel,
        if (signatureChars != null) 'signatureChars': signatureChars,
      };
}

class CoursePackLicense {
  const CoursePackLicense({
    required this.name,
    required this.attribution,
    required this.link,
  });

  final String name;
  final String attribution;
  final String link;

  factory CoursePackLicense.fromJson(Map<String, dynamic> json) {
    return CoursePackLicense(
      name: '${json['name'] ?? ''}'.trim(),
      attribution: '${json['attribution'] ?? ''}'.trim(),
      link: '${json['link'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'attribution': attribution,
        'link': link,
      };
}

class CoursePackFormatException implements Exception {
  const CoursePackFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CoursePackImportException implements Exception {
  const CoursePackImportException(this.errors);
  final List<String> errors;
  @override
  String toString() => errors.join('\n');
}

class CoursePackMissingException implements Exception {
  const CoursePackMissingException();
  @override
  String toString() => 'Persisted course pack is missing';
}

/// The user declined the "replace the existing course for this language?"
/// confirmation. Nothing was written — distinct from
/// [CoursePackImportException] so the UI can show a quiet cancel instead
/// of an error dialog.
class CoursePackImportCancelled implements Exception {
  const CoursePackImportCancelled(this.code);
  final String code;
  @override
  String toString() => 'Import of "$code" cancelled by user';
}

enum CoursePackImportPhase { decoding, validating, writing }

class CoursePackImportResult {
  const CoursePackImportResult({
    required this.code,
    required this.displayName,
    required this.sectionCount,
    required this.wordCount,
    required this.attribution,
  });

  final String code;
  final String displayName;
  final int sectionCount;
  final int wordCount;
  final String attribution;
}
