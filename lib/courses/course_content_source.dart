import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:turna/application/language_registry.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_json_parser.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/section.dart';

/// The index and expression versions used by the existing reseed key.
typedef CourseContentVersion = ({int index, int expressions});

typedef _ContentSnapshot = ({
  CourseContentVersion version,
  Map<String, String> files,
  bool downloaded,
});

/// Selects one complete source for a builtin language's course JSON.
///
/// Downloads live under the application's documents directory in
/// `content_updates/<language>/`. Index version takes precedence, followed by
/// expression version; bundled assets win ties. A selected download is fully
/// parsed and validated before use, then held as an immutable JSON snapshot
/// until [invalidate] so a read cannot mix downloaded and bundled files.
class CourseContentSource {
  CourseContentSource({
    AssetBundle? bundle,
    Future<Directory?> Function()? updatesDirectory,
  })  : _bundle = bundle ?? rootBundle,
        _updatesDirectory = updatesDirectory ?? _defaultUpdatesDirectory;

  /// The shared source used by builtin seeding and index-level overlays.
  static final CourseContentSource instance = CourseContentSource();

  final AssetBundle _bundle;
  final Future<Directory?> Function() _updatesDirectory;
  final Map<(String, String), Future<_ContentSnapshot>> _selections = {};

  /// Compares versions by index first, then by expressions.
  static int compareVersions(CourseContentVersion a, CourseContentVersion b) {
    final indexOrder = a.index.compareTo(b.index);
    return indexOrder != 0
        ? indexOrder
        : a.expressions.compareTo(b.expressions);
  }

  /// Fully validates a downloaded course directory and returns its version.
  ///
  /// OTA installation and runtime source selection deliberately share this
  /// parser/validator path: a package must be usable by the reader before it
  /// can replace the currently installed directory.
  static Future<CourseContentVersion> validateDownloadedDirectory(
    Directory directory,
    String languageCode,
  ) async {
    final code = LanguageCodes.canonicalize(languageCode);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code) ||
        !await directory.exists()) {
      throw const FormatException('Invalid downloaded course directory');
    }
    final resolvedRoot = await directory.resolveSymbolicLinks();
    Future<String> read(String path) async {
      validateRelativePath(path);
      final file = File(p.joinAll([directory.path, ...path.split('/')]));
      final resolvedFile = await file.resolveSymbolicLinks();
      if (!p.isWithin(resolvedRoot, resolvedFile)) {
        throw const FormatException('Course JSON escapes update directory');
      }
      return file.readAsString();
    }

    final metadata = await _readMetadata(read, code, downloaded: true);
    final validated = await _validateUpdate(metadata, read);
    return validated.version;
  }

  /// Rejects paths that could read outside a course or load non-JSON data.
  static void validateRelativePath(String relativePath) {
    final segments = relativePath.split('/');
    if (!relativePath.endsWith('.json') ||
        relativePath.contains('\\') ||
        relativePath.contains(':') ||
        segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException('Invalid course JSON path: $relativePath');
    }
  }

  /// Reads JSON from the selected source without falling through per file.
  Future<String> loadCourseJson(
    String languageCode,
    String relativePath,
  ) async {
    final read = await readerFor(languageCode);
    return read(relativePath);
  }

  /// Pins a source for a complete seed, even if another caller invalidates it.
  Future<Future<String> Function(String)> readerFor(String languageCode) async {
    final (baseDir, content) = await _contentFor(languageCode);
    return (String relativePath) async {
      validateRelativePath(relativePath);
      final cached = content.files[relativePath];
      if (cached != null) return cached;
      if (content.downloaded) {
        throw FormatException('Downloaded course is missing $relativePath');
      }
      return _bundle.loadString('$baseDir/$relativePath');
    };
  }

  /// Returns the version of the selected, usable course content.
  Future<CourseContentVersion> versionFor(String languageCode) async {
    final (_, content) = await _contentFor(languageCode);
    return content.version;
  }

  /// Drops source selections after a complete update is installed or removed.
  ///
  /// In-flight readers retain their snapshot. The caller must also reseed and
  /// reload the course and language lookup caches before displaying new data.
  void invalidate([String? languageCode]) {
    if (languageCode == null) {
      _selections.clear();
      return;
    }
    final code = LanguageCodes.canonicalize(languageCode);
    _selections.removeWhere((key, _) => key.$1 == code);
  }

  Future<(String, _ContentSnapshot)> _contentFor(String languageCode) async {
    final registry = LanguageRegistry.instance;
    if (!registry.isLoaded) await registry.load(bundle: _bundle);
    final code = LanguageCodes.canonicalize(languageCode);
    if (!registry.languages.any((language) => language.code == code)) {
      throw StateError('No builtin course registered for $code');
    }
    final baseDir = registry.byCode(code).assetBaseDir;
    // Include the manifest directory so a selection made before a manifest
    // change cannot pin a language to its previous asset tree.
    final key = (code, baseDir);
    final pending = _selections.putIfAbsent(key, () => _select(code, baseDir));
    try {
      return (baseDir, await pending);
    } catch (_) {
      // A failed source lookup must be retryable after the content is repaired.
      if (identical(_selections[key], pending)) {
        final _ = _selections.remove(key);
      }
      rethrow;
    }
  }

  Future<_ContentSnapshot> _select(String code, String baseDir) async {
    _ContentSnapshot? bundled;
    try {
      bundled = await _readMetadata(
        (path) => _bundle.loadString('$baseDir/$path'),
        code,
        downloaded: false,
      );
    } catch (error, stackTrace) {
      logger.w('Builtin course metadata unavailable for $code',
          error: error, stackTrace: stackTrace);
    }

    try {
      final root = await _updatesDirectory();
      if (root != null) {
        // Only manifest languages reach here; reject unsafe codes before
        // using them as sandbox directory names.
        if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code)) {
          throw FormatException('Invalid builtin language code: $code');
        }
        final directory = Directory(p.join(root.path, code));
        if (await directory.exists()) {
          final resolvedRoot = await directory.resolveSymbolicLinks();
          Future<String> read(String path) async {
            validateRelativePath(path);
            final file = File(p.joinAll([directory.path, ...path.split('/')]));
            final resolvedFile = await file.resolveSymbolicLinks();
            if (!p.isWithin(resolvedRoot, resolvedFile)) {
              throw FormatException('Course JSON escapes update directory');
            }
            return file.readAsString();
          }

          final update = await _readMetadata(read, code, downloaded: true);
          if (bundled == null ||
              compareVersions(update.version, bundled.version) > 0) {
            final validated = await _validateUpdate(update, read);
            logger.i('Using downloaded course $code '
                '${validated.version.index}+${validated.version.expressions}');
            return validated;
          }
        }
      }
    } catch (error, stackTrace) {
      logger.w('Course update for $code is unusable; using bundled assets',
          error: error, stackTrace: stackTrace);
    }

    if (bundled != null) return bundled;
    throw StateError('No usable builtin course content for $code');
  }

  static Future<_ContentSnapshot> _readMetadata(
    Future<String> Function(String) read,
    String code, {
    required bool downloaded,
  }) async {
    final files = <String, String>{'index.json': await read('index.json')};
    final index = jsonDecode(files['index.json']!);
    if (index
        case Map<String, dynamic> indexMap && {'sections': List<Object?> _}) {
      final version =
          _parseVersion(indexMap['version'], downloaded: downloaded);
      final language = indexMap['language'];
      if (language != null &&
          (language is! String ||
              LanguageCodes.canonicalize(language) != code)) {
        throw FormatException('Course index language does not match $code');
      }
      final expressions = await _readOptional(read, 'expressions.json');
      var expressionsVersion = 0;
      if (expressions != null) {
        files['expressions.json'] = expressions;
        switch (jsonDecode(expressions)) {
          case Map<String, dynamic> expressionMap:
            expressionsVersion =
                _parseVersion(expressionMap['version'], downloaded: downloaded);
          default:
            throw const FormatException('Invalid expressions version');
        }
      }
      return (
        version: (index: version, expressions: expressionsVersion),
        files: files,
        downloaded: downloaded,
      );
    }
    throw const FormatException('Invalid course index or version');
  }

  static int _parseVersion(Object? value, {required bool downloaded}) =>
      switch (value) {
        int version when version >= 0 => version,
        // Historic asset bundles also use numeric strings or omit versions.
        String raw when !downloaded && (int.tryParse(raw) ?? -1) >= 0 =>
          int.parse(raw),
        null when !downloaded => 0,
        _ => throw const FormatException('Invalid course content version'),
      };

  static Future<_ContentSnapshot> _validateUpdate(
    _ContentSnapshot metadata,
    Future<String> Function(String) read,
  ) async {
    final files = Map<String, String>.of(metadata.files);
    final index = jsonDecode(files['index.json']!) as Map<String, dynamic>;
    final sections = <Section>[];
    final paths = <String>{};
    for (final entry in index['sections'] as List<dynamic>) {
      if (entry case {'id': String id, 'file': String path}) {
        validateRelativePath(path);
        if (!path.startsWith('sections/') || !paths.add(path)) {
          throw FormatException('Invalid or duplicate section path: $path');
        }
        final raw = await read(path);
        final section = parseSection(raw);
        if (section.id != id) {
          throw FormatException('Section id does not match index: $path');
        }
        sections.add(section);
        files[path] = raw;
      } else {
        throw const FormatException('Invalid course section index entry');
      }
    }
    if (sections.isEmpty) {
      throw const FormatException('Downloaded course has no sections');
    }
    files['vocab.json'] = await read('vocab.json');
    final grammar = await _readOptional(read, 'grammar_points.json');
    if (grammar != null) files['grammar_points.json'] = grammar;
    validateCourse(
      sections,
      parseVocabulary(files['vocab.json']!),
      files['expressions.json'] == null
          ? const []
          : parseExpressions(files['expressions.json']!),
      grammar == null ? const [] : parseGrammarPoints(grammar),
    );
    return (
      version: metadata.version,
      files: Map<String, String>.unmodifiable(files),
      downloaded: true,
    );
  }

  static Future<String?> _readOptional(
    Future<String> Function(String) read,
    String path,
  ) async {
    try {
      return await read(path);
    } on FileSystemException catch (error) {
      // Optional pools may be absent, but permission and I/O failures must
      // reject a download rather than silently changing its version.
      if (error.osError?.errorCode == 2 || error.osError?.errorCode == 3) {
        return null;
      }
      rethrow;
    } on FlutterError {
      // AssetBundle reports an absent optional asset as FlutterError.
      return null;
    }
  }

  static Future<Directory?> _defaultUpdatesDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'content_updates'));
  }
}
