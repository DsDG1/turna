// Layering guard: codifies the import-direction rules that the batch-1
// architecture cleanup established. These mirror the conventions in
// CLAUDE.md (分层导入规则); a failure here means a layer boundary broke.
//
// Scanning parses import/export *directives* (single/double quotes, absolute
// `package:turna/` and relative paths) instead of substring-matching file
// text, so comments/strings never false-positive and relative imports that
// sneak across a layer boundary are caught.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `import '<target>';` / `export "<target>";` — captures the quote char so
/// mixed quoting is handled, and the raw target for later resolution.
final RegExp _directivePattern = RegExp(
  r"""^\s*(?:import|export)\s+(['"])([^'"]+)\1""",
);

bool _isGenerated(File file) {
  final path = file.path.replaceAll('\\', '/');
  if (path.endsWith('.g.dart') || path.endsWith('.gr.dart')) return true;
  if (path.endsWith('.freezed.dart')) return true;
  if (path.startsWith('lib/gen/')) return true;
  return false;
}

/// Collapse `.` / `..` segments in a slash-separated path.
String _normalize(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}

/// Every import/export target of [file] that resolves inside this package's
/// `lib/`, as normalized `lib/…` paths. `dart:` and foreign packages are
/// dropped; relative targets are resolved against the file's directory.
Set<String> _importedLibPaths(File file) {
  final filePath = file.path.replaceAll('\\', '/');
  final dir = filePath.substring(0, filePath.lastIndexOf('/'));
  final targets = <String>{};
  for (final line in file.readAsStringSync().split('\n')) {
    final match = _directivePattern.firstMatch(line);
    if (match == null) continue;
    final target = match.group(2)!;
    if (target.startsWith('dart:')) continue;
    if (target.startsWith('package:turna/')) {
      targets
          .add(_normalize('lib/${target.substring('package:turna/'.length)}'));
    } else if (!target.startsWith('package:')) {
      // Relative: resolve against the importing file, then keep it only if
      // it lands inside lib/.
      final resolved = _normalize('$dir/$target');
      if (resolved.startsWith('lib/')) targets.add(resolved);
    }
  }
  return targets;
}

Iterable<File> _dartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !_isGenerated(f));
}

/// Files under [roots] whose imports reach [forbiddenDir] (any depth).
List<String> _scanPrefix(List<String> roots, String forbiddenDir) {
  final violations = <String>[];
  for (final root in roots) {
    for (final file in _dartFiles(root)) {
      final path = file.path.replaceAll('\\', '/');
      final hits =
          _importedLibPaths(file).where((t) => t.startsWith('$forbiddenDir/'));
      if (hits.isNotEmpty) {
        violations.add('$path imports $forbiddenDir/ (${hits.join(', ')})');
      }
    }
  }
  return violations;
}

/// Batch-6 outcome: application must not import `lib/data` at all — DAOs and
/// repositories are consumed through `domain/repositories` interfaces. The
/// map below is the only exception list; each entry names the exact allowed
/// import target so an exception cannot silently widen, and a stale entry
/// (allowlisted but no longer imported) fails the guard too.
///
/// Justification classes:
///  * **handle** — threads the `CourseDatabase` connection as a typed
///    parameter into storage helpers. The handle itself is the dependency;
///    hiding Drift behind a domain type gains nothing at these seams.
///  * **drift-ops** — runs Drift queries/transactions/companions that are
///    inherently data-layer (maintenance, migration serialization, V2 store).
///  * **local-handle construction** — builds a DAO/repository against a
///    `CourseDatabase` handle that may differ from the registered singleton
///    (`CourseLoader.databaseOrNull()` / `overrideDatabase` test seam), so
///    resolving via GetIt would change semantics.
const Map<String, Set<String>> _allowedApplicationDataImports = {
  // ── Drift connection threading ─────────────────────────────────────────
  'lib/application/anki_import/anki_import_dependencies.dart': {
    'lib/data/course_database.dart', // handle: wires db into the import DAG
  },
  'lib/application/anki_import/anki_import_official_flow.dart': {
    'lib/data/course_database.dart', // handle: import flow ctor param
  },
  'lib/application/anki_official/anki_deck_manager.dart': {
    'lib/data/course_database.dart', // handle: lazy _courseDatabase() seam
  },
  'lib/application/anki_official/import/official_anki_official_first_service.dart':
      {
    'lib/data/course_database.dart', // handle: ctor param threading
  },
  'lib/application/anki_official/lifecycle/official_anki_maintenance.dart': {
    'lib/data/course_database.dart', // drift-ops: rebuild/verify queries
  },
  'lib/application/anki_official/lifecycle/official_anki_repair_executor.dart':
      {
    'lib/data/course_database.dart', // handle: repair target param
  },
  'lib/application/anki_official/lifecycle/official_anki_startup_recovery.dart':
      {
    'lib/data/course_database.dart', // handle: threads db into recoverers
  },
  'lib/application/anki_official/projection/official_anki_course_entry.dart': {
    'lib/data/course_database.dart', // handle: static courseOf seam + params
  },
  'lib/application/anki_official/projection/official_anki_lesson_card_index.dart':
      {
    'lib/data/course_database.dart', // handle: resolves db for index reads
  },
  // ── Official V2 storage services (own their tables directly) ────────────
  'lib/application/anki_official/v2/official_anki_v2_course_read.dart': {
    'lib/data/course_database.dart', // drift-ops: V2 read model queries
  },
  'lib/application/anki_official/v2/official_anki_v2_import_service.dart': {
    'lib/data/course_database.dart', // drift-ops: V2 import writes
    'lib/data/anki_unification_dao.dart', // local-handle construction
  },
  'lib/application/anki_official/v2/official_anki_v2_lesson_content.dart': {
    'lib/data/course_database.dart', // drift-ops: lesson content queries
  },
  'lib/application/anki_official/v2/official_anki_v2_post_retire_reclaimer.dart':
      {
    'lib/data/course_database.dart', // drift-ops: retire reclaimer writes
  },
  'lib/application/anki_official/v2/official_anki_v2_retire_service.dart': {
    'lib/data/course_database.dart', // drift-ops: retire writes
  },
  'lib/application/anki_official/v2/official_anki_v2_view_rebuilder.dart': {
    'lib/data/course_database.dart', // drift-ops: filtered-view rebuild SQL
  },
  'lib/application/anki_official/v2/official_anki_v2_view_store.dart': {
    'lib/data/course_database.dart', // drift-ops: filtered-view store
  },
  // ── Course tree writers / importers ─────────────────────────────────────
  'lib/application/ai/ai_course_provider.dart': {
    'lib/data/course_database.dart', // drift-ops: lesson writes w/ companions
  },
  'lib/application/builtin_language_service.dart': {
    'lib/data/course_database.dart', // handle: databaseOrNull + seeder wiring
    'lib/data/course_database_seeder.dart', // DatabaseSeeder + static helpers
    'lib/data/course_repository.dart', // local-handle construction
  },
  'lib/application/course_pack/course_pack_importer.dart': {
    'lib/data/course_database.dart', // drift-ops: import staging queries
    'lib/data/course_database_seeder.dart', // DatabaseSeeder (pack seeding)
    'lib/data/course_repository.dart', // local-handle construction
  },
  'lib/application/course_pack/imported_languages.dart': {
    'lib/data/course_database.dart', // drift-ops: registry hydration queries
  },
  'lib/application/course_catalog.dart': {
    'lib/data/course_database.dart', // drift-ops: aggregate card-count query
  },
  'lib/application/course_provider.dart': {
    'lib/data/course_database.dart', // handle: databaseOrNull + V2 read seam
    'lib/data/course_repository.dart', // local-handle construction
  },
  // ── Maintenance / diagnostics / migration serialization ─────────────────
  'lib/application/fun_lab_snapshot_service.dart': {
    'lib/data/course_database.dart', // handle: snapshot ctor param
  },
  'lib/application/maintenance/database_doctor_service.dart': {
    'lib/data/course_database.dart', // drift-ops: integrity checks
  },
  'lib/application/maintenance/official_storage_optimize_service.dart': {
    'lib/data/course_database.dart', // drift-ops: VACUUM/PRAGMA optimize
  },
  'lib/application/maintenance/storage_inventory_service.dart': {
    'lib/data/anki_import_dao.dart', // local-handle construction
    'lib/data/course_database.dart', // handle + drift-ops: size queries
  },
  'lib/application/maintenance/storage_maintenance_service.dart': {
    'lib/data/course_database.dart', // drift-ops: cleanup queries
  },
  'lib/application/migration/turna_migration_export.dart': {
    'lib/data/course_database.dart', // drift-ops: serializes raw tables
  },
  'lib/application/migration/turna_migration_import.dart': {
    'lib/data/course_database.dart', // drift-ops: restores raw tables
  },
  'lib/application/system_health_monitor.dart': {
    'lib/data/course_database.dart', // drift-ops: health probes
  },
};

/// views files that import an official-anki `*_dao.dart` or instantiate a
/// `*Dao(` — the catalog facade ([OfficialAnkiCatalogService]) is the only
/// sanctioned path (P1-2 收口; the DAO classes live under
/// application/anki_official/storage + lifecycle where the import scan
/// cannot reach them by prefix alone).
List<String> _scanOfficialAnkiDaoUsage() {
  final violations = <String>[];
  final daoCtor = RegExp(r'\b[A-Za-z_]\w*Dao\s*\(');
  final dir = Directory('lib/views');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_isGenerated(entity)) continue;
    final path = entity.path.replaceAll('\\', '/');
    final content = entity.readAsStringSync();
    for (final line in content.split('\n')) {
      if (line.startsWith('import ') &&
          line.contains('package:turna/application/anki_official/') &&
          line.contains('_dao.dart')) {
        violations.add('$path imports an official-anki dao file: '
            '${line.trim()}');
      }
    }
    for (final match in daoCtor.allMatches(content)) {
      violations.add('$path instantiates a DAO: ${match.group(0)}');
    }
  }
  return violations;
}

void main() {
  group('layering guard', () {
    test('views must not touch official-anki DAOs directly', () {
      expect(
        _scanOfficialAnkiDaoUsage(),
        isEmpty,
        reason: 'views → official-anki DAO shortcut; consume '
            'OfficialAnkiCatalogService (application facade) instead',
      );
    });

    test('views must not import the data layer', () {
      // Views reach data only through application services / repository
      // interfaces. Generated files are exempt (they import what they wrap).
      expect(
        _scanPrefix(['lib/views'], 'lib/data'),
        isEmpty,
        reason: 'views → data shortcut; route through an application service '
            'or a domain repository interface instead',
      );
    });

    test('application/domain/core/service must not import views', () {
      // The UI layer is a leaf; nothing below it may depend on it. DI
      // modules under lib/di are exempt by design (they wire renderers).
      expect(
        _scanPrefix(
          ['lib/application', 'lib/domain', 'lib/core', 'lib/service'],
          'lib/views',
        ),
        isEmpty,
        reason: 'downward layer imports views; move the shared symbol '
            '(theme, state model, data class) into core/application/domain',
      );
    });

    test('domain must not import application or data', () {
      // Domain stays a pure vocabulary/model layer. Repository interfaces
      // live in domain/repositories and expose domain types only.
      expect(
        _scanPrefix(['lib/domain'], 'lib/application'),
        isEmpty,
        reason: 'domain → application dependency; extract an interface in '
            'domain and let the application type implement it',
      );
      expect(
        _scanPrefix(['lib/domain'], 'lib/data'),
        isEmpty,
        reason: 'domain → data dependency; expose domain models from the '
            'repository interface instead of drift row types',
      );
    });

    test('application must not import the data layer (documented exceptions)',
        () {
      // Hard rule: batch 6 (DAO 接口化) moved every DAO/repository behind a
      // domain interface, so new application code must never import
      // `lib/data`. The allowlist above pins the surviving seams to exact
      // import targets — removing a data import must also remove its entry
      // (stale entries fail), and adding one needs an ADR-level reason.
      final violations = <String>[];
      for (final file in _dartFiles('lib/application')) {
        final path = file.path.replaceAll('\\', '/');
        final imports = _importedLibPaths(file);
        final dataHits =
            imports.where((t) => t.startsWith('lib/data/')).toSet();
        final allowed =
            _allowedApplicationDataImports[path] ?? const <String>{};
        for (final hit in dataHits.difference(allowed)) {
          violations.add('$path imports $hit');
        }
        for (final stale in allowed.difference(dataHits)) {
          violations.add(
              '$path allowlists $stale but no longer imports it — prune the exception');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'application → data import outside the allowlist:\n'
            '${violations.join('\n')}',
      );
    });
  });
}
