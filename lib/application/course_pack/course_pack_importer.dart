import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide Expression;
import 'package:path/path.dart' as p;
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_pack/course_pack.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/data/course_database.dart'
    hide Section, GrammarPoint, Unit, Lesson, LessonContent, Vocabulary;
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Orchestrates `.turnapack` import: decode → guard → validate → seed → meta.
class CoursePackImporter {
  CoursePackImporter(
    this.db, {
    this.onImportingActiveCode,
    this.onPhase,
    this.persistDirectory,
    this.afterTablesCleared,
  });

  final CourseDatabase db;

  /// When the pack language is the active builtin scope, switch away first.
  final Future<void> Function(String code)? onImportingActiveCode;

  /// Coarse progress signal for the import dialog (decode → validate → write).
  final void Function(CoursePackImportPhase phase)? onPhase;

  /// Override `imported_courses/` for tests. Production uses app support.
  final Directory? persistDirectory;

  /// Forwarded to [DatabaseSeeder.debugAfterLanguageTablesCleared].
  final Future<void> Function()? afterTablesCleared;

  static const Set<String> reservedCodes = {'anki'};

  Future<CoursePackImportResult> importFromFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw const CoursePackImportException(['Pack file does not exist']);
    }
    return importFromBytes(await file.readAsBytes(), sourcePath: path);
  }

  Future<CoursePackImportResult> importFromBytes(
    List<int> bytes, {
    String? sourcePath,
  }) async {
    if (CoursePackMedia.looksLikeZip(bytes)) {
      if (bytes.length > CoursePackMedia.maxZipBytes) {
        throw const CoursePackImportException(['Pack exceeds 80 MB zip limit']);
      }
      onPhase?.call(CoursePackImportPhase.decoding);
      final decoded = _decodeZip(bytes);
      return _importPack(
        decoded.pack,
        sourcePath: sourcePath,
        persistBytes: Uint8List.fromList(bytes),
        extractedMedia: decoded.media,
      );
    }
    if (bytes.length > CoursePack.maxBytes) {
      throw const CoursePackImportException(['Pack exceeds 20 MB limit']);
    }
    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException {
      throw const CoursePackImportException(['Pack is not valid UTF-8']);
    }
    return importFromString(raw, sourcePath: sourcePath);
  }

  Future<CoursePackImportResult> importFromString(
    String raw, {
    String? sourcePath,
  }) async {
    onPhase?.call(CoursePackImportPhase.decoding);
    CoursePack pack;
    try {
      pack = CoursePack.parse(raw);
    } on CoursePackFormatException catch (e) {
      throw CoursePackImportException([e.message]);
    } on FormatException catch (e) {
      throw CoursePackImportException(['Invalid JSON: $e']);
    }
    return _importPack(
      pack,
      sourcePath: sourcePath,
      persistText: raw,
    );
  }

  Future<CoursePackImportResult> _importPack(
    CoursePack pack, {
    String? sourcePath,
    String? persistText,
    Uint8List? persistBytes,
    Map<String, List<int>> extractedMedia = const {},
  }) async {
    onPhase?.call(CoursePackImportPhase.validating);

    final errors = <String>[];
    final code = pack.language.code;
    if (!CoursePack.codePattern.hasMatch(code)) {
      errors.add('language.code must match ^[a-z]{2,3}\$ (got $code)');
    }
    if (reservedCodes.contains(code)) {
      errors.add('language.code "$code" is reserved');
    }
    if (!LanguageRegistry.instance.isLoaded) {
      await LanguageRegistry.instance.load();
    }
    if (LanguageRegistry.instance.languages.any((l) => l.code == code)) {
      errors.add('language.code "$code" conflicts with a built-in course');
    }
    if (pack.language.displayName.isEmpty ||
        pack.license.name.isEmpty ||
        pack.license.attribution.isEmpty) {
      errors.add('language.displayName and license name/attribution are required');
    }
    if (!pack.files.containsKey('index.json')) {
      errors.add('files.index.json is required');
    }
    if (!pack.files.containsKey('vocab.json')) {
      errors.add('files.vocab.json is required');
    }
    if (errors.isNotEmpty) {
      throw CoursePackImportException(errors);
    }

    final mediaRefs = pack.mediaRelativeRefs();
    if (mediaRefs.isNotEmpty && extractedMedia.isEmpty) {
      throw const CoursePackImportException([
        'Pack references media/ files but is not a zip with a media/ tree',
      ]);
    }
    for (final rel in mediaRefs) {
      if (!extractedMedia.containsKey(rel)) {
        errors.add('Missing media file media/$rel');
      } else if (!CoursePackMedia.isAllowedMediaName(rel)) {
        errors.add('Unsupported media file media/$rel');
      }
    }
    if (errors.isNotEmpty) {
      throw CoursePackImportException(errors);
    }

    pack = pack.withRewrittenMediaRefs();

    Map<String, dynamic> index;
    try {
      index = jsonDecode(pack.files['index.json']!) as Map<String, dynamic>;
    } catch (e) {
      throw CoursePackImportException(['index.json is not valid JSON: $e']);
    }
    final indexLanguage = LanguageCodes.canonicalize('${index['language'] ?? ''}');
    if (indexLanguage != code) {
      throw CoursePackImportException([
        'index.language ($indexLanguage) != language.code ($code)',
      ]);
    }

    final sectionEntries =
        (index['sections'] as List<dynamic>? ?? const []).whereType<Map>().toList();
    final listedFiles = <String>{
      for (final entry in sectionEntries) '${entry['file'] ?? ''}',
    };
    listedFiles.remove('');
    final packSectionFiles = {
      for (final key in pack.files.keys)
        if (key.startsWith('sections/')) key,
    };
    if (listedFiles.length != packSectionFiles.length ||
        !listedFiles.containsAll(packSectionFiles)) {
      throw CoursePackImportException([
        'index.json sections[].file must match files keys under sections/',
      ]);
    }

    final prefix = 'll-$code-';
    List<WordEntry> vocab;
    try {
      vocab = parseVocabulary(pack.files['vocab.json']!);
    } catch (e) {
      throw CoursePackImportException(['vocab.json parse failed: $e']);
    }
    List<Expression> expressions = const [];
    final expressionsRaw = pack.files['expressions.json'];
    if (expressionsRaw != null) {
      try {
        expressions = parseExpressions(expressionsRaw);
      } catch (e) {
        throw CoursePackImportException(['expressions.json parse failed: $e']);
      }
    }
    List<GrammarPoint> grammarPoints = const [];
    final grammarRaw = pack.files['grammar_points.json'];
    if (grammarRaw != null) {
      try {
        grammarPoints = parseGrammarPoints(grammarRaw);
      } catch (e) {
        throw CoursePackImportException(['grammar_points.json parse failed: $e']);
      }
    }

    final sections = <Section>[];
    for (final entry in sectionEntries) {
      final file = '${entry['file']}';
      final rawSection = pack.files[file];
      if (rawSection == null) {
        throw CoursePackImportException(['Missing section file $file']);
      }
      try {
        final section = parseSection(rawSection);
        final declaredId = '${entry['id'] ?? ''}';
        if (declaredId.isNotEmpty && declaredId != section.id) {
          throw CoursePackImportException([
            'index.json sections[].id "$declaredId" != $file id '
            '"${section.id}"',
          ]);
        }
        sections.add(section);
      } on CoursePackImportException {
        rethrow;
      } catch (e) {
        throw CoursePackImportException(['Failed to parse $file: $e']);
      }
    }

    for (final id in _collectResourceIds(sections, vocab, expressions, grammarPoints)) {
      if (!id.startsWith(prefix)) {
        errors.add('id "$id" must start with $prefix');
      }
    }
    if (errors.isNotEmpty) {
      throw CoursePackImportException(errors);
    }

    try {
      validateCourse(sections, vocab, expressions, grammarPoints);
    } on CourseValidationException catch (e) {
      throw CoursePackImportException(e.errors);
    }

    final seenUnitIds = <String>{
      for (final row in await (db.selectOnly(db.units)
            ..addColumns([db.units.id])
            ..where(
              db.units.languageCode.equals(code).not() &
                  db.units.languageCode.equals('anki').not(),
            ))
          .get())
        row.read(db.units.id)!,
    };
    final seenLessonIds = <String>{
      for (final row in await (db.selectOnly(db.lessons)
            ..addColumns([db.lessons.id])
            ..where(
              db.lessons.languageCode.equals(code).not() &
                  db.lessons.languageCode.equals('anki').not(),
            ))
          .get())
        row.read(db.lessons.id)!,
    };
    final cross = <String>[];
    for (final section in sections) {
      cross.addAll(
        DatabaseSeeder.collectCrossCourseIdErrorsAgainst(
          section,
          seenUnitIds: seenUnitIds,
          seenLessonIds: seenLessonIds,
        ),
      );
    }
    if (cross.isNotEmpty) {
      throw CoursePackImportException(cross);
    }

    final persistDir = persistDirectory ?? await _defaultPersistDir();
    await persistDir.create(recursive: true);

    // Media lands only after the DB write succeeded, so a failed seed never
    // deletes/replaces the previously installed course's extracted media.
    onPhase?.call(CoursePackImportPhase.writing);
    await onImportingActiveCode?.call(code);

    final seeder = DatabaseSeeder(
      db,
      source: (assetKey) async => pack.files[assetKey],
    );
    seeder.debugAfterLanguageTablesCleared = afterTablesCleared;
    await seeder.seedLanguageFromSource(code, force: true);
    // Cleared only after a successful seed: a failed reimport of a previously
    // uninstalled language must leave the marker so it stays restorable.
    await CourseRepository(db).clearLanguageUninstallMarker(code);

    if (extractedMedia.isEmpty) {
      await CoursePackMedia.deleteExtractedMedia(code, persist: persistDir);
    } else {
      await _writeExtractedMedia(code, persistDir, extractedMedia);
    }

    final meta = pack.toMetaJson();
    await db.into(db.courseMeta).insertOnConflictUpdate(
          CourseMetaCompanion.insert(
            key: ImportedLanguageRegistry.metaKeyFor(code),
            value: jsonEncode(meta),
          ),
        );
    ImportedLanguageRegistry.instance.remember(code, meta);

    final dest = File('${persistDir.path}/$code.turnapack');
    if (sourcePath != null) {
      await File(sourcePath).copy(dest.path);
    } else if (persistBytes != null) {
      await dest.writeAsBytes(persistBytes);
    } else {
      await dest.writeAsString(persistText ?? jsonEncode({
        'format': pack.format,
        'packVersion': pack.packVersion,
        'language': pack.language.toJson(),
        'license': pack.license.toJson(),
        'files': pack.files,
      }));
    }

    LanguageContentStore.drop(code);
    CourseLoader.invalidateCaches();

    return CoursePackImportResult(
      code: code,
      displayName: pack.language.displayName,
      sectionCount: sections.length,
      wordCount: vocab.length,
      attribution: pack.license.attribution,
    );
  }

  static Future<File?> persistedPackFile(
    String languageCode, {
    Directory? persistDirectory,
  }) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final dir = persistDirectory ?? await _defaultPersistDir();
    final file = File('${dir.path}/$code.turnapack');
    return file.existsSync() ? file : null;
  }

  static Future<Directory> _defaultPersistDir() =>
      CoursePackMedia.persistRoot();

  static bool _isUnsafeZipName(String name) {
    final n = name.replaceAll('\\', '/');
    if (n.startsWith('/') || n.startsWith('~/') || n == '~') return true;
    if (n.contains('..')) return true;
    if (n.contains(':')) return true;
    return false;
  }

  static String _normalizeZipName(String name) {
    var n = name.replaceAll('\\', '/');
    while (n.startsWith('./')) {
      n = n.substring(2);
    }
    return n;
  }

  static ({CoursePack pack, Map<String, List<int>> media}) _decodeZip(
    List<int> bytes,
  ) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw CoursePackImportException(['Invalid zip: $e']);
    }

    ArchiveFile? packEntry;
    var uncompressed = 0;
    final media = <String, List<int>>{};
    for (final entry in archive) {
      final name = _normalizeZipName(entry.name);
      if (_isUnsafeZipName(name)) {
        throw const CoursePackImportException(['Zip entry escapes pack root']);
      }
      if (!entry.isFile) continue;
      // entry.size is the declared header size — a forged header can
      // under-report; content is the real decompressed length.
      final content = entry.content;
      uncompressed += content.length;
      if (uncompressed > CoursePackMedia.maxUncompressedBytes) {
        throw const CoursePackImportException([
          'Uncompressed pack exceeds 200 MB limit',
        ]);
      }
      if (name == 'pack.json') {
        if (content.length > CoursePack.maxBytes) {
          throw const CoursePackImportException([
            'pack.json exceeds 20 MB limit',
          ]);
        }
        packEntry = entry;
        continue;
      }
      if (content.length > CoursePackMedia.maxSingleFileBytes) {
        throw CoursePackImportException([
          'Media file $name exceeds 15 MB limit',
        ]);
      }
      if (name == 'media' || !name.startsWith('media/')) continue;
      final relative = name.substring('media/'.length);
      if (relative.isEmpty || relative.endsWith('/')) continue;
      // Media refs are flat `media/<file>` — a nested path would write under
      // `media/media/` on disk while `turnapack://` resolution strips one
      // level, so the reference would never resolve.
      if (relative.startsWith('media/')) {
        throw CoursePackImportException(['Nested media path $name']);
      }
      if (!CoursePackMedia.isAllowedMediaName(relative)) {
        throw CoursePackImportException(['Unsupported media file $name']);
      }
      media[relative] = List<int>.from(content);
    }
    if (packEntry == null) {
      throw const CoursePackImportException(['Zip is missing pack.json']);
    }
    final packRaw = utf8.decode(packEntry.content);
    try {
      return (pack: CoursePack.parse(packRaw), media: media);
    } on CoursePackFormatException catch (e) {
      throw CoursePackImportException([e.message]);
    } on FormatException catch (e) {
      throw CoursePackImportException(['Invalid pack.json: $e']);
    }
  }

  /// Files land in a sibling `media.staging/` directory first and are moved
  /// into place only after every write succeeded — a mid-write failure
  /// (disk full, killed process) never leaves a half-written `media/`.
  static Future<void> _writeExtractedMedia(
    String code,
    Directory persistDir,
    Map<String, List<int>> extractedMedia,
  ) async {
    final dir = await CoursePackMedia.mediaDirectory(code, persist: persistDir);
    final staging = Directory('${dir.path}.staging');
    if (staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
    staging.createSync(recursive: true);
    try {
      for (final entry in extractedMedia.entries) {
        final relative = entry.key;
        if (!CoursePackMedia.isAllowedMediaName(relative)) continue;
        final destPath = p.normalize(p.join(staging.path, relative));
        final dest = File(destPath);
        if (!p.isWithin(staging.path, destPath) && destPath != staging.path) {
          throw CoursePackImportException(['Unsafe media path $relative']);
        }
        dest.parent.createSync(recursive: true);
        dest.writeAsBytesSync(entry.value);
      }
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      staging.renameSync(dir.path);
    } catch (_) {
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  static Iterable<String> _collectResourceIds(
    List<Section> sections,
    List<WordEntry> vocab,
    List<Expression> expressions,
    List<GrammarPoint> grammarPoints,
  ) sync* {
    for (final section in sections) {
      yield section.id;
      for (final unit in section.units) {
        yield unit.id;
        for (final lesson in unit.lessons) {
          yield lesson.id;
        }
      }
    }
    for (final word in vocab) {
      yield word.id;
    }
    for (final expression in expressions) {
      yield expression.id;
    }
    for (final point in grammarPoints) {
      yield point.id;
    }
  }
}

/// Used by the management page to switch the active course before overwrite.
Future<void> switchAwayFromImportedCode({
  required String importingCode,
  required String activeWire,
  required Future<void> Function(dynamic scope) setScope,
  required List<CourseCatalogEntry> catalog,
}) async {
  const scopePrefix = 'course-scope:v1:builtin:';
  if (!activeWire.startsWith(scopePrefix)) return;
  final activeCode = activeWire.substring(scopePrefix.length);
  if (LanguageCodes.canonicalize(activeCode) !=
      LanguageCodes.canonicalize(importingCode)) {
    return;
  }
  await setScope(CourseCatalog.fallbackBuiltin(catalog));
}
