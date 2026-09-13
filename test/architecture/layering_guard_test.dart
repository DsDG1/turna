// Layering guard: codifies the import-direction rules that the batch-1
// architecture cleanup established. These mirror the conventions in
// CLAUDE.md (分层导入规则); a failure here means a layer boundary broke.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _isGenerated(File file) {
  final path = file.path.replaceAll('\\', '/');
  if (path.endsWith('.g.dart') || path.endsWith('.gr.dart')) return true;
  if (path.endsWith('.freezed.dart')) return true;
  if (path.startsWith('lib/gen/')) return true;
  return false;
}

/// Files under [roots] that import anything under [forbiddenPrefix].
List<String> _scanPrefix(List<String> roots, String forbiddenPrefix) {
  final violations = <String>[];
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_isGenerated(entity)) continue;
      final content = entity.readAsStringSync();
      if (content.contains("import '$forbiddenPrefix")) {
        violations.add('${entity.path} imports $forbiddenPrefix…');
      }
    }
  }
  return violations;
}

void main() {
  group('layering guard', () {
    test('views must not import the data layer', () {
      // Views reach data only through application services / repository
      // interfaces. Generated files are exempt (they import what they wrap).
      expect(
        _scanPrefix(['lib/views'], 'package:turna/data/'),
        isEmpty,
        reason: 'views → data shortcut; route through an application service '
            'or a domain repository interface instead',
      );
    });

    test('application/domain/core must not import views', () {
      // The UI layer is a leaf; nothing below it may depend on it. DI
      // modules under lib/di are exempt by design (they wire renderers).
      expect(
        _scanPrefix(
          ['lib/application', 'lib/domain', 'lib/core'],
          'package:turna/views/',
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
        _scanPrefix(['lib/domain'], 'package:turna/application/'),
        isEmpty,
        reason: 'domain → application dependency; extract an interface in '
            'domain and let the application type implement it',
      );
      expect(
        _scanPrefix(['lib/domain'], 'package:turna/data/'),
        isEmpty,
        reason: 'domain → data dependency; expose domain models from the '
            'repository interface instead of drift row types',
      );
    });
  });
}
